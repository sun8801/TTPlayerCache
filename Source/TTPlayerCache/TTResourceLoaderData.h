//
//  TTData.h
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/11/14.
//  Copyright © 2017年 szt. All rights reserved.
//

#import <Foundation/Foundation.h>

@class AVAssetResourceLoadingRequest;
@interface TTResourceLoaderData : NSObject

+ (instancetype)new  NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;


/**
 初始化

 @param url 原始URL 有MMTT://
 @return <#return value description#>
 */
- (instancetype)initWithURL:(NSString *)url;

/**
 判断是否设置过视频contentLength、MIMEType
 */
@property (nonatomic, assign, readonly) BOOL hasConfigured;

@property (nonatomic, assign, readonly) long long contentLength;

/**
 设置视频数据 contentLength 与MIMEType
 
 当收到网络响应的时候先判断 hasConfigured  ,if NO call configContentLength:MIMEType:
 
 @param contentLength 视频完整的长度
 @param MIMEType MIMEType response.MIMEType
 */
- (void)configContentLength:(long long)contentLength MIMEType:(NSString *)MIMEType;

/**
 当前AVAssetResourceLoadingRequest 是否需要继续做网络连接

 @param loadingRequest <#loadingRequest description#>
 @return NO（直接return 不需要）
 */
- (BOOL)needContinueNetworking:(AVAssetResourceLoadingRequest *)loadingRequest;

/**
 组装下载任务与loadingRequest

 @param loadingRequest <#loadingRequest description#>
 @param dataTask <#dataTask description#>
 */
- (void)addLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest dataTask:(NSURLSessionDataTask *)dataTask;

/**
 当网络下载完成的时候调用，

 @param error <#error description#>
 @param taskIdentifier <#taskIdentifier description#>
 */
- (void)taskCompleteWithError:(NSError *)error taskId:(NSUInteger)taskIdentifier;

/**
 当网络重新连接上时，刷新播放器
 */
- (void)reloadLoadingRequestWhenHasNetError;

/**
 是否有正在进行下载在task

 @return <#return value description#>
 */
- (BOOL)hasDataTaskRequesting;

/**
 设置当前的任务下载的数据，不填充loadingRequest

 @param taskIdentifier <#taskIdentifier description#>
 */
- (void)cancelLoadingRequestWithTaskId:(NSUInteger)taskIdentifier;

/**
 取消TT_requestsAllDataToEndOfResource == NO 的下载任务
 
 当开始新的下载任务（TT_requestsAllDataToEndOfResource == YES ）时调用，
 */
- (void)cancelNoRequestsAllDataToEndOfResourceTask;

/**
 根据下载任务ID 保存收到的数据

 @param data <#data description#>
 @param taskIdentifier <#taskIdentifier description#>
 */
- (void)appendData:(NSData *)data taskId:(NSUInteger)taskIdentifier;





#pragma mark - CLASS METHOD
/**
 根据响应计算数据总长度

 @param response <#response description#>
 @return <#return value description#>
 */
+ (long long)caculateVideoResponseContentLength:(NSHTTPURLResponse *)response;


@end
