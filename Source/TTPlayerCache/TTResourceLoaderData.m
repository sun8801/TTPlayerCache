//
//  TTData.m
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/11/14.
//  Copyright © 2017年 szt. All rights reserved.
//

#import "TTResourceLoaderData.h"
#import "TTPlayerCache.h"

#import <AVFoundation/AVAssetResourceLoader.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h>

//////////////缓存数据区间/////////
static NSUInteger  TTCacheCellBytes = 1024;
static NSUInteger  TTNotNeedNetMaxIntervalBytes = 2048; //相差1024 *2 B不需继续请求
static NSUInteger  TTCachedMinIntervalBytes = 1<<20; //1M

static NSString *const TTReceivedDataInfoText  = @"receivedDataInfo";
static NSString *const TTMediaContentLengthText= @"contentLength";
static NSString *const TTMediaMIMETypeText     = @"MIMEType";

struct _TTReceivedDataPoint {
    long long begin;
    long long end;
} ;
typedef struct _TTReceivedDataPoint TTReceivedDataPointType;
typedef struct _TTReceivedDataPoint *  TTReceivedDataPoint;

TTReceivedDataPointType TTMakeReceivedDataPoint(long long begin, long long end) {
    TTReceivedDataPointType r;
    r.begin = begin;
    r.end   = end;
    return r;
}


CFComparisonResult TTComparatorFunction( void *val1, void *val2, void *context) {
    TTReceivedDataPoint t0 = val1;
    TTReceivedDataPoint t1 = val2;
    if (t0->begin > t1->begin) {
        return kCFCompareGreaterThan;
    }
    if (t0->begin == t1->begin) {
        return kCFCompareEqualTo;
    }
    return kCFCompareLessThan;
}

#pragma mark - ****TTTaskModel****
@interface TTTaskModel : NSObject
@property (nonatomic, strong) AVAssetResourceLoadingRequest *loadingRequest;
@property (nonatomic, strong) NSURLSessionDataTask *dataTask;
// allHTTPHeaderFields-> Range [requestRangeBegin - ]
@property (nonatomic, assign) long long requestRangeBegin;
@property (nonatomic, assign) BOOL isCanceled;

@end
@implementation TTTaskModel
@end
#pragma mark - ****TTResourceLoaderData****
@interface TTResourceLoaderData ()
{
    NSMutableData *_data;
    NSMutableDictionary <NSNumber *, TTTaskModel *>*_taskModelDict;
    
    NSString *_MIMEType;
    long long _contentLength;
    NSString *_url;
    NSString *_localFilePath;
    NSString *_localMediaInfoPath;
    NSString *_lastSaveInfo;
    
    NSFileManager *_fileManager;
    
    CFMutableArrayRef _receivedDataPointArray;
    
    long long _downAllBytes;
    NSUInteger _errorTaskIdentifier;
    NSUInteger _bufferLength;
    
    dispatch_semaphore_t _cancel_finish_semaphore_t;
    BOOL _shouldCancel;
}
@end
@implementation TTResourceLoaderData

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    //存储数据
    [self saveFileToLocal:nil];
    
    CFIndex count = CFArrayGetCount(_receivedDataPointArray);
    for (CFIndex i = 0; i < count; i++) {
        TTReceivedDataPoint dataPoint = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, i);
        free(dataPoint);
    }
    CFRelease(_receivedDataPointArray);
    _receivedDataPointArray = NULL;
    [_taskModelDict removeAllObjects];
    _taskModelDict = nil;
}

- (instancetype)initWithURL:(NSString *)url {
    if (self = [super init]) {
        _receivedDataPointArray = CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
        
        _taskModelDict = [NSMutableDictionary dictionary];
        _hasConfigured = NO;
        _url = url;
        
        _localFilePath = TTLocalFilePath(_url);
        _localMediaInfoPath = TTLocalMediaInfoPath(_url);
        
        _fileManager = [NSFileManager defaultManager];
        if (![_fileManager fileExistsAtPath:TTCacheLocalDirectory()]) {
            [_fileManager createDirectoryAtPath:TTCacheLocalDirectory() withIntermediateDirectories:YES attributes:nil error:nil];
        }
        [self readFromLocalFile];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveFileToLocal:) name:UIApplicationWillTerminateNotification object:nil];
    }
    return self;
}

- (void)configContentLength:(long long)contentLength MIMEType:(NSString *)MIMEType{
    if (contentLength == _contentLength && [MIMEType isEqualToString:_MIMEType]) {
        return;
    }
    _contentLength = contentLength;
    _MIMEType      = MIMEType;
    _data          = [NSMutableData dataWithLength:contentLength];
    _hasConfigured = YES;
    TTLog(@"****视频内存长度%lld MIMETyep:%@",contentLength,MIMEType);
    TTLog(@"****视频大小%.2fM",contentLength/1024.0/1024.0);
}

- (long long)contentLength {
    return _contentLength;
}

- (BOOL)needContinueNetworking:(AVAssetResourceLoadingRequest *)loadingRequest {
    
    if (_contentLength != 0 && loadingRequest.dataRequest.requestedOffset >= _contentLength) {
        return NO;
    }
    
    __block BOOL need = YES; //继续网络任务
    
    TTLog(@"\n\n****判断是否本地加载开始：***");
    TTLog(@"%@",[self transformCFArrayToNSObject]);
    TTLog(@"%@",loadingRequest.dataRequest);
    
    long long requestedOffset  = loadingRequest.dataRequest.requestedOffset;
    long long requestedLength =  loadingRequest.dataRequest.requestedLength;
    long long requestEnd = requestedOffset + requestedLength -1;
    
    /***********判断本地数据-> 填充***********/
    
    [self trimReceivedDataOffsetDict];
    
    CFIndex arrayCount = CFArrayGetCount(_receivedDataPointArray);
    for (CFIndex index = 0; index < arrayCount; index ++) {
        TTReceivedDataPoint dataPoint = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, index);
        long long begin = dataPoint->begin;
        long long end   = dataPoint->end;
        if (begin != end) {
            if (requestedOffset >= begin && requestedOffset < end) {
                if (requestEnd <=  end) {
                    //loadingRequest 加载数据
                    TTLog(@"***********全部从本地数据加载**********");
                    [self respondDataForLoadingRequest:loadingRequest responsedLength:0 continued:NULL];
                    [loadingRequest finishLoading];
                    need = NO;
                    break;
                }else {
                    BOOL isContinueLoop = [self isContinueLoopWithRequest:loadingRequest dataPoint:dataPoint needNet:&need];
                    if (!isContinueLoop) break;
                }
            }
        }
    }
    
    if (need) {
        /***********判断新的loadingRequest 是否能替换上次的request***************/
        TTTaskModel *taskModel = [self getTaskModelWithLoadingRequest:loadingRequest isEqual:NO];
        if (taskModel) {
            BOOL inMaxSpace = (requestedOffset - (taskModel.requestRangeBegin + taskModel.dataTask.countOfBytesReceived)) <= TTNotNeedNetMaxIntervalBytes;
            if (inMaxSpace) {
                taskModel.loadingRequest = loadingRequest;
                taskModel.isCanceled = NO;
                need = NO;
            }
        }
    }
    
    if (_cancel_finish_semaphore_t) {
        _shouldCancel = NO;
        dispatch_semaphore_signal(_cancel_finish_semaphore_t);
    }
    
    return need;
}

- (BOOL)isContinueLoopWithRequest:(AVAssetResourceLoadingRequest *)loadingRequest dataPoint:(TTReceivedDataPoint)dataPoint needNet:(BOOL *)needNet{
    BOOL loop = YES;
    long long requestOffset  = loadingRequest.dataRequest.requestedOffset;
    long long end   = dataPoint->end;
    
    TTTaskModel *taskModel = [self getTaskModelWithLoadingRequest:loadingRequest isEqual:NO];
    if (taskModel) {
        //填充数据 ，把当前loadingRequest 。。。
        TTLog(@"**********中间填充数据**********");
        taskModel.loadingRequest = loadingRequest;
        taskModel.isCanceled = NO;
        [self respondDataForLoadingRequest:loadingRequest responsedLength:0 continued:NULL];
        *needNet = NO;
        loop = NO;
    }else {
        if ((requestOffset + TTCacheCellBytes) <= end) {
            //如果缓存区间大于1024*1024  1M 先不下载
            if ((requestOffset + TTCachedMinIntervalBytes) <= end) {
                *needNet = NO;
            }
            TTLog(@"******部分加载》》 %@*******",((*needNet)?@"继续网络":@"只加载本地"));
            //不暂停0.5秒，无法播放 或用下面分段加载
            if (requestOffset == 0) {
                [NSThread sleepForTimeInterval:0.5];
            }
            [self respondDataForLoadingRequest:loadingRequest responsedLength:0 continued:NULL];
            if (!(*needNet)) {
                [loadingRequest finishLoading];
            }
            
            
            //                            //模拟网络下载分段加载数据
            //                            [self respondDataForLoadingRequest:loadingRequest responsedLength:TTCachedMinIn/4];
            //                            [self respondDataForLoadingRequest:loadingRequest responsedLength:0];
            //                            if (!need) {
            //                                [loadingRequest finishLoading];
            //                            }
            loop = NO;
        }
    }
    return loop;
}

/**
 获取在 loadingRequest【requestRangeBegin < requestedOffset】 内的 requestsAllDataToEndOfResource == YES 的 TTTaskModel
 
 @param loadingRequest <#loadingRequest description#>
 @param needEqual 用于判断是否需要requestoffset 与lastLoadingRequest.crrentOffset 相等
 @return <#return value description#>
 */
- (TTTaskModel *)getTaskModelWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
                                        isEqual:(BOOL)needEqual{
    long long requestedOffset = loadingRequest.dataRequest.requestedOffset;
    
    __block TTTaskModel *taskModel = nil;
    [_taskModelDict enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, TTTaskModel * _Nonnull obj, BOOL * _Nonnull stop) {
        if ((obj.loadingRequest.dataRequest.
            requestsAllDataToEndOfResource ||
             obj.requestRangeBegin == 0) &&
            (obj.dataTask.state == NSURLSessionTaskStateRunning || obj.dataTask.state == NSURLSessionTaskStateSuspended)
            ) {
            if (obj.requestRangeBegin <= requestedOffset) {
                taskModel = obj;
                *stop = YES;
            }
        }
    }];
    return taskModel;
}

- (void)addLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest dataTask:(NSURLSessionDataTask *)dataTask {
    TTTaskModel *taskModel   = [TTTaskModel new];
    taskModel.loadingRequest = loadingRequest;
    taskModel.dataTask       = dataTask;
    taskModel.requestRangeBegin = loadingRequest.dataRequest.currentOffset;
    taskModel.isCanceled = NO;
    _taskModelDict[@(dataTask.taskIdentifier)] = taskModel;
}

- (void)taskCompleteWithError:(NSError *)error taskId:(NSUInteger)taskIdentifier {
    TTLog(@"共下载多少字节 %lld == %.2fM",_downAllBytes,_downAllBytes/1024.0/1024.0);
    //全部下载完保存
    [self autoSaveCacheToLocal:taskIdentifier];
    if (error) {
        if (error.code == NSURLErrorCancelled) {
            TTLog(@"*******Cancelled request**********");
        }else if(error.code == NSURLErrorTimedOut) {
            TTTaskModel *taskModel = _taskModelDict[@(taskIdentifier)];
            TTLog(@"****请求error:%@",error);
            [taskModel.loadingRequest finishLoadingWithError:error];
        }else {
            TTLog(@"\n*******网络错误%@*************\n",error);
            //#error 判断下载失败后的反馈。。。。保存数据问题
            [self removeTask:_errorTaskIdentifier];
            _errorTaskIdentifier = taskIdentifier;
            return;
        }
    }else {
        TTLog(@"*********网络请求完成--succeed-**********");
    }
    [self removeTask:taskIdentifier];
}

- (void)reloadLoadingRequestWhenHasNetError {
    TTTaskModel *taskModel = _taskModelDict[@(_errorTaskIdentifier)];
    [taskModel.loadingRequest finishLoadingWithError:taskModel.dataTask.error];
    [self removeTask:_errorTaskIdentifier];
}

- (BOOL)hasDataTaskRequesting {
    __block BOOL has = NO;
    [_taskModelDict enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, TTTaskModel * _Nonnull obj, BOOL * _Nonnull stop) {
        if (obj.dataTask.state == NSURLSessionTaskStateRunning) {
            has = YES;
            *stop = YES;
        }
    }];
    return has;
}

- (void)cancelLoadingRequestWithTaskId:(NSUInteger)taskIdentifier {
    TTTaskModel *taskModel = _taskModelDict[@(taskIdentifier)];
    taskModel.isCanceled = YES;
}

- (void)cancelNoRequestsAllDataToEndOfResourceTask {
    [_taskModelDict enumerateKeysAndObjectsUsingBlock:^(NSNumber * _Nonnull key, TTTaskModel * _Nonnull obj, BOOL * _Nonnull stop) {
        if (obj.loadingRequest.dataRequest.requestedOffset != 0 && obj.loadingRequest.dataRequest.
            requestsAllDataToEndOfResource == NO) {
            obj.isCanceled = YES;
            [obj.dataTask cancel];
        }
    }];
}

- (void)appendData:(NSData *)data taskId:(NSUInteger)taskIdentifier {
    
    _downAllBytes += data.length;
    
    if (_contentLength == 0 || _MIMEType == nil) {
        NSAssert(NO, @"需先配置视频信息-- configContentLength: mimeType:");
    }
    
    TTTaskModel *taskModel = _taskModelDict[@(taskIdentifier)];
    
    if (!taskModel) {
        TTLog(@"****taskModel 被删除了*****");
        return;
    }
    
    AVAssetResourceLoadingRequest *loadingRequest = taskModel.loadingRequest;
    NSURLSessionDataTask *dataTask = taskModel.dataTask;
    
    long long startOffset = taskModel.requestRangeBegin + dataTask.countOfBytesReceived - data.length;
    
    if (!data || data.length == 0) {
        TTLog(@"不能存储数据。。。。。");
        return;
    }
    
    long long end = startOffset + data.length -1;
    if ((end +1) > _contentLength) {
        end = _contentLength-1;
    }
    
    CFIndex sameBeginIndex = [self findSameRequestOffsetFromReceivedDataPointArray:taskModel.requestRangeBegin];
    if (sameBeginIndex != -1) {
        TTReceivedDataPoint findData = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, sameBeginIndex);
        findData->end = end;
    }else {
        TTReceivedDataPoint dataPoint = malloc(sizeof(TTReceivedDataPointType));
        dataPoint->begin = taskModel.requestRangeBegin;
        dataPoint->end   = end;
        CFArrayAppendValue(_receivedDataPointArray, dataPoint);
    }
    
    NSRange replaceRange = NSMakeRange(startOffset, end -startOffset +1);
    if (replaceRange.length > 0) {
        [_data replaceBytesInRange:replaceRange withBytes:data.bytes length:replaceRange.length];
    }
    
    if (taskModel.isCanceled) {
        return;
    }
    BOOL isContinue;
    [self trimReceivedDataOffsetDict];
    BOOL didRespondFinished = [self respondDataForLoadingRequest:loadingRequest responsedLength:0 continued:&isContinue];
    if (!isContinue) {
        return;
    }
    loadingRequest.response = dataTask.response;
    if (didRespondFinished) {
        if (loadingRequest.dataRequest.requestsAllDataToEndOfResource) {
            _cancel_finish_semaphore_t = dispatch_semaphore_create(0);
            //是否需要取消
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                _shouldCancel = YES;
                dispatch_semaphore_wait(_cancel_finish_semaphore_t, dispatch_time(DISPATCH_TIME_NOW, 1 *NSEC_PER_SEC));
                _cancel_finish_semaphore_t = nil;
                if (_shouldCancel) [taskModel.dataTask cancel];
            });
        }
        TTLog(@"填充完毕==offset==%lld",loadingRequest.dataRequest.requestedOffset);
        [loadingRequest finishLoading];
        return;
    }
    if (loadingRequest.dataRequest.requestsAllDataToEndOfResource) {
        long long currentResponedEnd = taskModel.requestRangeBegin + dataTask.countOfBytesReceived;
        if ((loadingRequest.dataRequest.currentOffset - currentResponedEnd) >= TTNotNeedNetMaxIntervalBytes) {
            //当响应到重叠下载部分
            [loadingRequest finishLoadingWithError:[NSError errorWithDomain:@"中间有缓存。。重新开始。。" code:NSURLErrorUnknown userInfo:nil]];
            return;
        }
    }
}

/**
 解除下载关联
 
 @param taskIdentifier <#taskIdentifier description#>
 */
- (void)removeTask:(NSUInteger)taskIdentifier {
    TTLog(@"删除任务");
    TTTaskModel *taskModel = _taskModelDict[@(taskIdentifier)];
    if (taskModel.dataTask.state == NSURLSessionTaskStateRunning && taskModel.dataTask.countOfBytesExpectedToReceive != taskModel.dataTask.countOfBytesReceived) {
        TTLog(@"不删除。。。");
        return;
    }
    [_taskModelDict removeObjectForKey:@(taskIdentifier)];
}

/**
 保存缓存信息到本地 --delloc或 程序杀死是调用
 */
- (void)saveFileToLocal:(NSNotification *)noti {
    
    if (_contentLength == 0 || !_MIMEType || !_data) {
        return;
    }
    [self trimReceivedDataOffsetDict];
    NSString *receivedDataInfoText = [self transformCFArrayToNSObject];
    if ([receivedDataInfoText isEqualToString:_lastSaveInfo]) {
        return;
    }
    _lastSaveInfo = receivedDataInfoText;
    
    TTLog(@"*****存储视频到->>%@",_localFilePath);
    
    NSData *writeData = _data;
    NSString *localFilePath = _localFilePath;
    NSString *localMediaInfoPath = _localMediaInfoPath;
    
    NSDictionary *meidaInfoDict =
    @{
      TTReceivedDataInfoText:receivedDataInfoText,
      TTMediaContentLengthText:@(_contentLength),
      TTMediaMIMETypeText:_MIMEType
      };
    
    void (^callBlock)(void) = ^{
        [[NSFileManager defaultManager] removeItemAtPath:localMediaInfoPath error:nil];
        if (![[NSFileManager defaultManager] fileExistsAtPath:_localFilePath]) {
            [[NSFileManager defaultManager] createFileAtPath:_localFilePath contents:nil attributes:nil];
        }
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:localFilePath];
        [fileHandle seekToFileOffset:0];
        [fileHandle writeData:writeData];
        [fileHandle closeFile];
        [meidaInfoDict writeToFile:localMediaInfoPath atomically:YES];
    };
    
    if ([NSThread isMainThread]) {
        dispatch_sync(dispatch_get_global_queue(0, 0), ^{
            callBlock();
        });
    }else {
        callBlock();
    }
}

/**
 读取本地缓存信息
 */
- (void)readFromLocalFile {
    
    NSError *error;
    _data = [[NSMutableData alloc] initWithContentsOfFile:TTLocalFilePath(_url) options:NSDataReadingMappedIfSafe error:&error];
    
    NSDictionary *mediaInfo = [NSDictionary dictionaryWithContentsOfFile:TTLocalMediaInfoPath(_url)];
    
    if (error || !mediaInfo) {
        return;
    }
    TTLog(@"本地缓存信息：%@",mediaInfo);
    
    _contentLength = [mediaInfo[TTMediaContentLengthText] longLongValue];
    _MIMEType      = mediaInfo[TTMediaMIMETypeText];
    
    NSString *receivedDataInfoString = mediaInfo[TTReceivedDataInfoText];
    _lastSaveInfo = receivedDataInfoString;
    if (_contentLength > 0 && _data.length > 0) {
        _hasConfigured = YES;
        if (receivedDataInfoString.length > 1) {
            NSArray <NSString *> *separatedArray0 = [receivedDataInfoString componentsSeparatedByString:@";"];
            [separatedArray0 enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                NSRange range = [obj rangeOfString:@"-"];
                if (range.location != NSNotFound) {
                    long long begin = [[obj substringToIndex:range.location] longLongValue];
                    long long end   = [[obj substringFromIndex:range.location+1] longLongValue];
                    TTReceivedDataPoint dataPoint = malloc(sizeof(TTReceivedDataPointType));
                    dataPoint->begin = begin;
                    dataPoint->end   = end;
                    CFArrayAppendValue(_receivedDataPointArray, dataPoint);
                }
            }];
        }
    }
}

//当视频全部下载完后自动保存
- (void)autoSaveCacheToLocal:(NSUInteger)taskIdentifier {
    TTTaskModel *taskModel = _taskModelDict[@(taskIdentifier)];
    if (taskModel.loadingRequest.dataRequest.requestedLength > TTCacheCellBytes) {
        [self trimReceivedDataOffsetDict];
        CFIndex arrayCount = CFArrayGetCount(_receivedDataPointArray);
        if (arrayCount == 1) {
            TTReceivedDataPoint dataPoint = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, 0);
            if (dataPoint->begin == 0 && (dataPoint->end +1) == _contentLength) {
                [self saveFileToLocal:nil];
                _data = nil;
            }
        }
    }
}

#pragma mark ---
/**  在数组中查找相同的begin  */
- (CFIndex)findSameRequestOffsetFromReceivedDataPointArray:(long long)requestOffset {
    CFIndex index = -1;
    CFIndex count = CFArrayGetCount(_receivedDataPointArray);
    for (CFIndex i = count -1; i >= 0; i--) {
        TTReceivedDataPoint dataPoint = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, i);
        if (dataPoint->begin == requestOffset) {
            return i;
        }
    }
    return index;
}

//整理 _receivedDataOffsetDict 交叉数据 组合下载进度
- (void)trimReceivedDataOffsetDict {
    
    CFIndex arrayCount = CFArrayGetCount(_receivedDataPointArray);
    
    if (arrayCount < 2) {
        return;
    }
    CFArraySortValues(_receivedDataPointArray, CFRangeMake(0, arrayCount), (CFComparatorFunction)(&TTComparatorFunction), NULL);
    
    TTReceivedDataPoint dataPoint_i;
    TTReceivedDataPoint dataPoint_j;
    long long end_i = 0;
    for (CFIndex i = 0; i <= arrayCount -2; i++) {
        dataPoint_i = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, i);
        end_i = dataPoint_i->end +1;
        for (CFIndex j = i+1; j <= arrayCount -1; j++) {
            dataPoint_j = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, j);
            
            if (dataPoint_j->begin <= end_i) {
                if (dataPoint_j->end <= end_i) {
                }else {
                    dataPoint_i->end = dataPoint_j->end;
                    end_i = dataPoint_j->end + 1;;
                }
                arrayCount --;
                CFArrayRemoveValueAtIndex(_receivedDataPointArray, j);
                free(dataPoint_j);
                j--;
            }
        }
    }
    [self transformCFArrayToNSObject];
}

//计算填充数据的结束位置
- (long long)filledRequestEndPoint:(AVAssetResourceLoadingRequest *)loadingRequest {
    
    long long requestOffset = loadingRequest.dataRequest.requestedOffset;
    long long requestEnd   = loadingRequest.dataRequest.requestedLength + requestOffset -1;
    long long requestEnd_r = 0;
    
    CFIndex sameBeginIndex = [self findSameRequestOffsetFromReceivedDataPointArray:requestOffset];
    if (sameBeginIndex != -1) {
        TTReceivedDataPoint dataPoint = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, sameBeginIndex);
        requestEnd_r = dataPoint->end;
    }
    
    if (requestEnd_r == requestOffset) {
        return 0;
    }
    if (requestEnd_r == 0) {
        CFIndex arrayCount = CFArrayGetCount(_receivedDataPointArray);
        TTReceivedDataPoint dataPoint;
        for (CFIndex i = 0; i < arrayCount; i++) {
            dataPoint = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, i);
            long long keyLong = dataPoint->begin;
            long long objLong = dataPoint->end;
            if (requestOffset >= keyLong && requestOffset <= objLong) {
                if (requestEnd > objLong) {
                    requestEnd_r = objLong;
                }else {
                    requestEnd_r = requestEnd;
                }
                break;
            }
        }
    }
    return requestEnd_r;
}

/**
 <#Description#>
 
 @param loadingRequest <#loadingRequest description#>
 @param responsedLength 0时忽略  否则使用，当缓存未完成是，使播放器响应（一次填充，当快进时有问题）
 @param isContinue  用于返回判断
 @return 当前loadingRequest是否填充完数据
 */
- (BOOL)respondDataForLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest responsedLength:(long)responsedLength continued:(BOOL *)isContinue{
    if (isContinue != NULL) {
        *isContinue = NO;
    }
    if (!loadingRequest || loadingRequest.isFinished || loadingRequest.isCancelled ||loadingRequest.dataRequest.currentOffset >= (loadingRequest.dataRequest.requestedOffset+ loadingRequest.dataRequest.requestedLength)) {
        return NO;
    }
    
    [self setResourceLoadingContentInformationRequestInformation:loadingRequest.contentInformationRequest];
    
    long long filled_endPoint = [self filledRequestEndPoint:loadingRequest] +1;
    
    if (filled_endPoint > _contentLength) {
        filled_endPoint = _contentLength;
    }
    
    long long startOffset = loadingRequest.dataRequest.currentOffset;
    long long requsedtLength  = loadingRequest.dataRequest.requestedLength;
    
    if (startOffset == requsedtLength) {
        return NO;
    }
    
    if (startOffset < 0) {
        TTLog(@"=====>>>>>>>");
        startOffset = 0;
    }
    
    if (filled_endPoint <= startOffset) {
        if (startOffset == requsedtLength) {
            return YES;
        }
        return NO;
    }
    
    long long unReadLength = filled_endPoint - startOffset;
    long long needResponseDataLength = MIN(requsedtLength, unReadLength);
    
    if (responsedLength != 0) {
        needResponseDataLength = MIN(responsedLength, needResponseDataLength);
    }
    
    if (needResponseDataLength <= 0) {
        return NO;
    }
    NSData *respondData = [_data subdataWithRange:NSMakeRange(startOffset, needResponseDataLength)];
    [loadingRequest.dataRequest respondWithData:respondData];
    //    TTLog(@"填充数据长度%ld",respondData.length);
    respondData = nil;
    
    if (isContinue != NULL) {
        *isContinue = YES;
    }
    if (loadingRequest.dataRequest.currentOffset >= (loadingRequest.dataRequest.requestedOffset + loadingRequest.dataRequest.requestedLength)) {
        return YES;
    }
    return NO;
}

- (NSString *)transformCFArrayToNSObject {
    CFIndex count = CFArrayGetCount(_receivedDataPointArray);
    if (count == 0) {
        return @"";
    }
    NSMutableString *mString = [NSMutableString string];
    for (CFIndex i = 0 ; i < count; i++) {
        TTReceivedDataPoint dataPoint = (TTReceivedDataPoint)CFArrayGetValueAtIndex(_receivedDataPointArray, i);
        [mString appendFormat:@"%lld-%lld;",dataPoint->begin,dataPoint->end];
    }
    [mString deleteCharactersInRange:NSMakeRange(mString.length-1, 1)];
    return mString;
}

/**
 设置contentInformationRequest 的contentType 、contentLength(=视频数据总长度)
 */
- (void)setResourceLoadingContentInformationRequestInformation:(AVAssetResourceLoadingContentInformationRequest *)contentInformationRequest{
    if (!contentInformationRequest) {
        return;
    }
    NSString *mimeType = _MIMEType;
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    contentInformationRequest.byteRangeAccessSupported = YES;
    contentInformationRequest.contentType = CFBridgingRelease(contentType);
    contentInformationRequest.contentLength = _contentLength;
}


+ (long long)caculateVideoResponseContentLength:(NSHTTPURLResponse *)response {
    long long videoContentLength = 0;
    NSString *content_range = response.allHeaderFields[@"Content-Range"];
    NSString *contentLength = [[content_range componentsSeparatedByString:@"/"] lastObject];
    videoContentLength = [contentLength longLongValue];
    return videoContentLength;
}

@end
