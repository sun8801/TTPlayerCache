//
//  TTPlayerView.h
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/11/9.
//  Copyright © 2017年 szt. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface TTPlayerView : UIView

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

+ (instancetype)playerViewWith:(NSURL *)url;

- (void)prepareToPlay;

- (void)play;
- (void)pause;


- (void)seekNextTime;

/**
 播放到指定时间

 @param time <#time description#>
 */
- (void)seekToTime:(NSTimeInterval)time;


@end
