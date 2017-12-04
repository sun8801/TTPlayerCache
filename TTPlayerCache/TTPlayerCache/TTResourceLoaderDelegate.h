//
//  TTResourceLoaderDelegate.h
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/11/9.
//  Copyright © 2017年 szt. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVAssetResourceLoader.h>

/** [resourceLoader setDelegate:self.resourceLoaderDelegate queue:TT_resourceLoader_delegate_queue()] */
extern dispatch_queue_t TT_resourceLoader_delegate_queue(void);

@interface TTResourceLoaderDelegate : NSObject<AVAssetResourceLoaderDelegate>

@end




/**   下载任务    **/
@protocol TTResourceLoaderDownloadTaskDelegate;
@interface TTResourceLoaderDownloadTask : NSObject<NSURLSessionTaskDelegate,NSURLSessionDataDelegate>

@property (nonatomic, weak) id <TTResourceLoaderDownloadTaskDelegate> downloadDelegate;

@end

@protocol TTResourceLoaderDownloadTaskDelegate <NSObject>

- (void)TT_downloadTaskDataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response;
- (void)TT_downloadTaskTask:(NSURLSessionTask *)task
       didCompleteWithError:(NSError *)error;
- (void)TT_downloadTaskDataTask:(NSURLSessionDataTask *)dataTask
                 didReceiveData:(NSData *)data;

@end
