//
//  TTPlayerCacheMacro.h
//  TTPlayerCacheMacro
//
//  Created by sunzongtang on 2017/11/9.
//  Copyright © 2017年 szt. All rights reserved.
//

#ifndef TTPlayerCacheMacro_h
#define TTPlayerCacheMacro_h

/** 在视频URL前添加的标识scheme(MMTT) */
extern NSString * const TTPlayerCustomScheme;
/** MMTT:// 使系统不识别URL 自己代理数据  */
extern NSString * const TTPlayerCustomProtocol;

/** 把正常URL 转换成 当前代理识别URL 即在url前加上MMTT://  */
extern NSString *TTResourceUrlFromOrigianllUrl(NSString * originalUrl);

/** 视频存储目录 */
extern NSString *TTCacheLocalDirectory(void);
/** 返回视频文件地址 （沙盒+md5(url)） */
extern NSString *TTLocalFilePath(NSString *url);
/** 存储视频类型地址 */
extern NSString *TTLocalMediaInfoPath(NSString *url);

/** 获得视频下载速度 通知 */
extern NSString * const TTVideoDownloadSpeedNotification;
extern NSString * const TTDownloadSpeed;
extern NSString * const TTDownloadFinished;

//打印加载日志
extern BOOL TTOpenLog; //YES打印， 默认NO
#define TTLog(format, ...) \
     if (TTOpenLog) fprintf(stderr, "%s", [[NSString stringWithFormat:format, ##__VA_ARGS__] UTF8String]);

#endif /* TTPlayerCache_h */
