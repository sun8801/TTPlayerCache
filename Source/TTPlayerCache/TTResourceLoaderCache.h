//
//  TTResourceLoaderCache.h
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/12/1.
//  Copyright © 2017年 szt. All rights reserved.
// 缓存管理

#import <Foundation/Foundation.h>

@interface TTResourceLoaderCache : NSObject

/**
 获取视频缓存size

 @return <#return value description#>
 */
+ (NSUInteger)getCacheSize;

/**
 清除本地视频缓存
 */
+ (void)clearCache;

/**
 删除具体某个视频缓存

 @param url <#url description#>
 */
+ (void)removeCacheVideoForUrl:(NSString *)url;

@end
