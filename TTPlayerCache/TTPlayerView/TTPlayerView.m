//
//  TTPlayerView.m
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/11/9.
//  Copyright © 2017年 szt. All rights reserved.
//

#import "TTPlayerView.h"
#import "TTResourceLoaderDelegate.h"
#import "TTPlayerCache.h"
#import <AVFoundation/AVFoundation.h>

NSString *TTFilmLengthTransformToTimeString(id filmLength) {
    NSInteger filmTimeLength = 0;
    if ([filmLength isKindOfClass:[NSString class]]) {
        if (((NSString *)filmLength).length == 0) {
            return @"00:00";
        }
    }
    if ([filmLength respondsToSelector:@selector(floatValue)]) {
        filmTimeLength = ceil([filmLength floatValue]);
    }else {
        if ([filmLength isKindOfClass:[NSNumber class]]) {
            filmTimeLength = ceil(((NSNumber *)filmLength).floatValue);
        }
    }
    if (filmTimeLength < 0) {
        filmTimeLength = 0;
    }
    
    NSInteger sec = filmTimeLength % 60;
    NSInteger min = filmTimeLength / 60;
    return [NSString stringWithFormat:@"%02ld:%02ld",min,sec];
}

@interface TTPlayerView ()

@property (nonatomic, strong) NSURL *videoURL;

/** 缓存代理*/
@property (nonatomic, strong) TTResourceLoaderDelegate *resourceLoaderDelegate;

/** 播放属性 */
@property (nonatomic, strong) AVPlayer               *player;
@property (nonatomic, strong) AVPlayerItem           *playerItem;
@property (nonatomic, strong) AVURLAsset             *urlAsset;
@property (nonatomic, strong) AVAssetImageGenerator  *imageGenerator;
@property (nonatomic, strong) id                     timeObserve;
/** playerLayer */
@property (nonatomic, weak) AVPlayerLayer            *playerLayer;

//控制 缓存进度
@property (nonatomic, strong) UIProgressView          *progressView;
//视频时长label
@property (nonatomic, strong) UILabel                 *timeLengthLabel;
//当缓存为空时的自动暂停
@property (nonatomic, assign) BOOL autoPauseByBufferEmpty;
@property (nonatomic, assign) Float64 seekTime;

@property (nonatomic, strong) UILabel *downloadSpeedLabel;

@end

@implementation TTPlayerView

#pragma mark -override super method

- (void)dealloc {
    [self pause];
    self.resourceLoaderDelegate = nil;
    
    [self.player removeTimeObserver:self.timeObserve];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
    [_playerItem removeObserver:self forKeyPath:@"status"];
    [_playerItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
    [_playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    [_playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
}

+ (Class)layerClass {
    return [AVPlayerLayer class];
}
- (AVPlayerLayer *)playerLayer {
    return (AVPlayerLayer *)self.layer;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadSpeedChanged:) name:TTVideoDownloadSpeedNotification object:nil];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutPlayerView];
}

#pragma mark -public method
+ (instancetype)playerViewWith:(NSURL *)url {
    CGFloat width = CGRectGetWidth([UIScreen mainScreen].bounds);
    TTPlayerView *playerView = [[self alloc] initWithFrame:CGRectMake(0, 0,width , width *9.0/16)];
    playerView.videoURL = url;
    return playerView;
}

- (void)prepareToPlay {
    [self configPlayer];
}

- (void)play {
    if (self.autoPauseByBufferEmpty) {
        [self.player seekToTime:CMTimeMakeWithSeconds(CMTimeGetSeconds(self.player.currentTime)+0.1, self.player.currentTime.timescale)];
    }
    [self.player play];
    self.autoPauseByBufferEmpty = NO;
}

- (void)pause {
    [self.player pause];
}

#pragma mark -快进
- (void)seekNextTime {
    Float64 currentTime = CMTimeGetSeconds(self.playerItem.currentTime);
    self.seekTime = currentTime+10;
    [self.player seekToTime:CMTimeMakeWithSeconds(self.seekTime, self.playerItem.currentTime.timescale)];
}

- (void)seekToTime:(NSTimeInterval)time {
//    __weak typeof(self) weakSelf = self;
    self.seekTime = time;
    [self.player seekToTime:CMTimeMakeWithSeconds(self.seekTime, self.playerItem.currentTime.timescale) toleranceBefore:CMTimeMakeWithSeconds(1, 1) toleranceAfter:CMTimeMakeWithSeconds(1, 1) completionHandler:^(BOOL finished) {
        
    }];
}

#pragma mark -private method

- (void)configPlayer {
    self.resourceLoaderDelegate = [TTResourceLoaderDelegate new];
    
    self.urlAsset = [AVURLAsset assetWithURL:self.videoURL];
//    //
    [self.urlAsset.resourceLoader setDelegate:self.resourceLoaderDelegate queue:TT_resourceLoader_delegate_queue()];
    // 初始化playerItem
    self.playerItem = [AVPlayerItem playerItemWithAsset:self.urlAsset];
    // 每次都重新创建Player，替换replaceCurrentItemWithPlayerItem:，该方法阻塞线程
    self.player = [AVPlayer playerWithPlayerItem:self.playerItem];
    
    // 初始化playerLayer
    self.playerLayer.player = self.player;
    
    self.backgroundColor = [UIColor blackColor];
    
    // 添加播放进度计时器
    [self createTimer];
}

- (void)createTimer {
    __weak typeof(self) weakSelf = self;
    self.timeObserve = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1, 1) queue:nil usingBlock:^(CMTime time){
        AVPlayerItem *currentItem = weakSelf.playerItem;
        NSArray *loadedRanges = currentItem.seekableTimeRanges;
        if (loadedRanges.count > 0 && currentItem.duration.timescale != 0) {
//            NSInteger currentTime = (NSInteger)CMTimeGetSeconds([currentItem currentTime]);
//            CGFloat totalTime     = (CGFloat)currentItem.duration.value / currentItem.duration.timescale;
//            CGFloat value         = CMTimeGetSeconds([currentItem currentTime]) / totalTime;
            
            [weakSelf setPlayerTimeLabel];
        }
    }];
}

- (void)setPlayerTimeLabel {
    NSInteger currentTime = (NSInteger)CMTimeGetSeconds([self.playerItem currentTime]);
    Float64 length = CMTimeGetSeconds(self.player.currentItem.duration);
    NSString *time = [NSString stringWithFormat:@"%@ /    %@",TTFilmLengthTransformToTimeString(@(currentTime)),TTFilmLengthTransformToTimeString(@(length))];
    self.timeLengthLabel.text = time;
}

- (void)layoutPlayerView {
    CGFloat width  = CGRectGetWidth(self.frame);
    CGFloat height = CGRectGetHeight(self.frame);
    
    self.progressView.frame = CGRectMake(20, height -15, width -20 *2, 15);
    self.timeLengthLabel.frame = CGRectMake((width -150)/2.0, CGRectGetMinY(self.progressView.frame)-30, 150, 25);
    self.downloadSpeedLabel.frame = CGRectMake(width -60, 0, 60, 30);
}


#pragma mark -设置
- (void)pauseByBufferEmpty {
    self.autoPauseByBufferEmpty = YES;
    [self pause];
    self.seekTime = 0;
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == self.player.currentItem) {
        if ([keyPath isEqualToString:@"status"]) {
            if (self.player.currentItem.status == AVPlayerItemStatusReadyToPlay) {
                NSLog(@"视频可以播放了。。。。");
                [self setPlayerTimeLabel];
            }
            NSLog(@"当前视频状态：%ld",self.player.currentItem.status);
        } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
            
            // 计算缓冲进度
            Float64 timeInterval = [self availableDuration];
            CMTime duration             = self.playerItem.duration;
            Float64 totalDuration       = CMTimeGetSeconds(duration);
            [self.progressView setProgress:timeInterval/totalDuration animated:YES];
            
//            Float64 currentTime = CMTimeGetSeconds([self.player.currentItem currentTime]);
            
            if (self.seekTime != 0 && ABS(timeInterval - self.seekTime) <= 0.5) {
                [self pauseByBufferEmpty];
            }
            
        } else if ([keyPath isEqualToString:@"playbackBufferEmpty"]) {
            
            // 当缓冲是空的时候
            if (self.playerItem.playbackBufferEmpty) {
                [self pauseByBufferEmpty];
            }
            
        } else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]) {
            
            // 当缓冲好的时候
            if (self.playerItem.playbackLikelyToKeepUp && self.autoPauseByBufferEmpty){
                [self play];
            }
        }
    }
}

#pragma mark -AVPlayerItemDidPlayToEndTimeNotification 播放完成
- (void)moviePlayDidEnd:(NSNotification *)noti {
    NSLog(@"播放结束");
}

#pragma mark -下载速度改变。。。
- (void)downloadSpeedChanged:(NSNotification *)noti {
    BOOL hidden = [noti.userInfo[TTDownloadFinished] boolValue];
    if (hidden) {
        [self performSelector:@selector(hiddenDownloadSpeedLabel) withObject:nil afterDelay:2];
    }else {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hiddenDownloadSpeedLabel) object:nil];
        self.downloadSpeedLabel.hidden = NO;
        NSString *speedString = noti.userInfo[TTDownloadSpeed];
        self.downloadSpeedLabel.text = speedString;
    }
}

- (void)hiddenDownloadSpeedLabel {
    self.downloadSpeedLabel.hidden = YES;
}

#pragma mark - 计算缓冲进度
    
/**
 *  计算缓冲进度
 *
 *  @return 缓冲进度
 */
- (Float64)availableDuration {
    NSArray *loadedTimeRanges = [[_player currentItem] loadedTimeRanges];
    CMTimeRange timeRange     = [loadedTimeRanges.firstObject CMTimeRangeValue];// 获取缓冲区域
    Float64 startSeconds        = CMTimeGetSeconds(timeRange.start);
    Float64 durationSeconds     = CMTimeGetSeconds(timeRange.duration);
    Float64 result     = startSeconds + durationSeconds;// 计算缓冲总进度
    return result;
}
    
#pragma mark -property method
/**
 *  根据playerItem，来添加移除观察者
 *
 *  @param playerItem playerItem
 */
- (void)setPlayerItem:(AVPlayerItem *)playerItem {
    if (_playerItem == playerItem) {return;}
    
    if (_playerItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
        [_playerItem removeObserver:self forKeyPath:@"status"];
        [_playerItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
        [_playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
        [_playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    }
    _playerItem = playerItem;
    if (playerItem) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(moviePlayDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];
        [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
        [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
        // 缓冲区空了，需要等待数据
        [playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
        // 缓冲区有足够数据可以播放了
        [playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    }
}

- (UIProgressView *)progressView {
    if (!_progressView) {
        _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressView.progressTintColor = [UIColor blueColor];
        _progressView.trackTintColor    = [UIColor whiteColor];
        _progressView.progress = 0;
        [self addSubview:_progressView];
    }
    return _progressView;
}

- (UILabel *)timeLengthLabel {
    if (!_timeLengthLabel) {
        _timeLengthLabel = [UILabel new];
        _timeLengthLabel.backgroundColor = [UIColor clearColor];
        _timeLengthLabel.textColor = [UIColor whiteColor];
        _timeLengthLabel.font = [UIFont systemFontOfSize:13];
        _timeLengthLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_timeLengthLabel];
    }
    return _timeLengthLabel;
}

- (UILabel *)downloadSpeedLabel {
    if (!_downloadSpeedLabel) {
        _downloadSpeedLabel = [UILabel new];
        _downloadSpeedLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3];
        _downloadSpeedLabel.textColor = [UIColor whiteColor];
        _downloadSpeedLabel.font = [UIFont systemFontOfSize:13];
        _downloadSpeedLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_downloadSpeedLabel];
    }
    return _downloadSpeedLabel;
}

@end
