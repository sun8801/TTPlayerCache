//
//  TTResourceLoaderCache.m
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/12/1.
//  Copyright © 2017年 szt. All rights reserved.
//

#import "TTResourceLoaderCache.h"
#import "TTPlayerCacheMacro.h"
#import <CommonCrypto/CommonDigest.h>

/** 缓存本地存储目录名 */
static NSString * const TTVideoCachePath = @"TTVideoCache";

static NSString *TTCachedFileNameForKey(NSString *key) {
    const char *str = [key UTF8String];
    if (str == NULL) {
        str = "";
    }
    unsigned char r[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), r);
    NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                          r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10],
                          r[11], r[12], r[13], r[14], r[15]];
    
    return filename;
}

/** 视频存储目录 */
NSString *TTCacheLocalDirectory(void) {
    static NSString *loaclDirectory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loaclDirectory = [NSString stringWithFormat:@"%@/%@",NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject,TTVideoCachePath];
    });
    return loaclDirectory;
}

/** 返回视频文件地址 （沙盒+md5(url)） */
NSString *TTLocalFilePath(NSString *url) {
    NSString *localFilePath = TTCacheLocalDirectory();
    localFilePath = [localFilePath stringByAppendingPathComponent:TTCachedFileNameForKey(url)];
    return localFilePath;
}
/** 存储视频类型地址*/
NSString *TTLocalMediaInfoPath(NSString *url) {
    return [NSString stringWithFormat:@"%@_media.plist",TTLocalFilePath(url)];
}


NSString * const TTPlayerCustomScheme = @"MMTT";
NSString * const TTPlayerCustomProtocol = @"MMTT://";
NSString * const TTVideoDownloadSpeedNotification = @"TTVideoDownloadSpeedNotification";
NSString * const TTVideoDownloadFailNotification  = @"TTVideoDownloadFailNotification";
NSString * const TTDownloadSpeed = @"TTDownloadSpeed";
NSString * const TTDownloadFinished = @"TTDownloadFinished";
NSString * const TTDownloadError = @"TTDownloadError";
BOOL TTOpenLog = NO;

/** 把正常URL 转换成 当前代理识别URL 即在url前加上MMTT://  */
NSString *TTResourceUrlFromOrigianllUrl(NSString * originalUrl) {
    if (!originalUrl) {
        return nil;
    }
    if (![originalUrl hasPrefix:TTPlayerCustomProtocol]) {
        originalUrl = [NSString stringWithFormat:@"%@%@",TTPlayerCustomProtocol,originalUrl];
    }
    return originalUrl;
}

@implementation TTResourceLoaderCache

+ (NSUInteger)getCacheSize {
    NSString *folderPath = TTCacheLocalDirectory();
    NSFileManager* manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:folderPath]) return 0;
    __block NSUInteger folderSize = 0;
    [[manager subpathsAtPath:folderPath] enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString* fileAbsolutePath = [folderPath stringByAppendingPathComponent:obj];
        folderSize += [self fileSizeAtPath:fileAbsolutePath];
    }];
    return folderSize;
}

+ (NSUInteger) fileSizeAtPath:(NSString*) filePath{
    NSFileManager* manager = [NSFileManager defaultManager];
    if ([manager fileExistsAtPath:filePath]){
        return (NSUInteger)[[manager attributesOfItemAtPath:filePath error:nil] fileSize];
    }
    return 0;
}

+ (void)clearCache {
    NSString *folderPath = TTCacheLocalDirectory();
    NSFileManager* fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:folderPath error:nil];
    [fileManager createDirectoryAtPath:folderPath
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:NULL];
}

+ (void)removeCacheVideoForUrl:(NSString *)url {
    if (!url) {
        return;
    }
    url = TTResourceUrlFromOrigianllUrl(url);
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:TTLocalFilePath(url) error:nil];
    [fileManager removeItemAtPath:TTLocalMediaInfoPath(url) error:nil];
    
}

@end
