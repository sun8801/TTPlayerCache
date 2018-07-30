//
//  TTResourceLoaderDelegate.m
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/11/9.
//  Copyright © 2017年 szt. All rights reserved.
//

#import "TTResourceLoaderDelegate.h"

#import "TTPlayerCacheMacro.h"
#import "TTResourceLoaderData.h"
#import "TTReachabilityManager.h"
#import "AVAssetResourceLoadingDataRequest+TTCategory.h"
#import <UIKit/UIKit.h>

dispatch_queue_t TT_resourceLoader_delegate_queue(void) {
    static dispatch_queue_t resourceLoader_delegate_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        resourceLoader_delegate_queue = dispatch_queue_create("TT.resourceLoader.delegate.queue", DISPATCH_QUEUE_SERIAL);
    });
    return resourceLoader_delegate_queue;
}

static dispatch_queue_t TT_resourceLoader_deal_queue(void) {
    static dispatch_queue_t resourceLoader_deal_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        resourceLoader_deal_queue = dispatch_queue_create("TT.resourceLoader.deal.queue", DISPATCH_QUEUE_SERIAL);
    });
    return resourceLoader_deal_queue;
}

#ifndef NSFoundationVersionNumber_iOS_8_0
#define NSFoundationVersionNumber_With_Fixed_5871104061079552_bug 1140.11
#else
#define NSFoundationVersionNumber_With_Fixed_5871104061079552_bug NSFoundationVersionNumber_iOS_8_0
#endif

static dispatch_queue_t url_session_manager_creation_queue() {
    static dispatch_queue_t af_url_session_manager_creation_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        af_url_session_manager_creation_queue = dispatch_queue_create("com.tt.networking.session.manager.creation", DISPATCH_QUEUE_SERIAL);
    });
    return af_url_session_manager_creation_queue;
}
static void url_session_manager_create_task_safely(dispatch_block_t block) {
    if (NSFoundationVersionNumber < NSFoundationVersionNumber_With_Fixed_5871104061079552_bug) {
        // Fix of bug
        // Open Radar:http://openradar.appspot.com/radar?id=5871104061079552 (status: Fixed in iOS8)
        // Issue about:https://github.com/AFNetworking/AFNetworking/issues/2093
        dispatch_sync(url_session_manager_creation_queue(), block);
    } else {
        block();
    }
}


@interface TTResourceLoaderDelegate ()<TTResourceLoaderDownloadTaskDelegate>
{
    TTResourceLoaderData *_data;
    NSString *_url;
    
    dispatch_semaphore_t _sync_semaphore_t;
    dispatch_semaphore_t _cancel_semaphore_t;
}

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *dataTask;

@property (nonatomic, weak) AVAssetResourceLoadingRequest *currentLoadingRequest;

@end

/**
 * contentInformationRequest.contentLength = 视频数据总长度
 */

/**
 * mp4 -系统请求顺序
 * 1、先请求两个字节 range 0-2
 * 2、请求全部的数据 range 0-
 * 3、请求中间部分的数据 range XXXX-XXXX （多个）
 * （判断第三步，不继续请求，缓存获取）
 * 一次只能有一个网络任务
 */

@implementation TTResourceLoaderDelegate

- (void)dealloc {
    TTLog(@"*****%@ ****dealloc***",self.class);
    _data = nil;
    [_session invalidateAndCancel];
    [self hideNetworkActivityIndicator];
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    TTLog(@"*****系统开始....******");
    if ([loadingRequest.request.URL.scheme isEqualToString:TTPlayerCustomScheme]) {
        self.currentLoadingRequest = loadingRequest;
        if (_sync_semaphore_t != NULL) {
            dispatch_semaphore_signal(_sync_semaphore_t);
        }
        dispatch_async(TT_resourceLoader_deal_queue(), ^{
            [self handleAssetResourceLoadingRequest:loadingRequest];
        });
        return YES;
    }
    return NO;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    //系统会自动处理大视频，当前缓存到一定程度，系统会调用当前方法=>取消下载
    self.currentLoadingRequest = nil;
    [_data cancelLoadingRequestWithTaskId:self.dataTask.taskIdentifier];
    TTLog(@"*****系统取消....******");
    dispatch_async(TT_resourceLoader_deal_queue(), ^{
        //信号量，等待currentLoadingRequest 赋值后继续执行
        _sync_semaphore_t = dispatch_semaphore_create(0);
        dispatch_semaphore_wait(_sync_semaphore_t, dispatch_time(DISPATCH_TIME_NOW, 1 *NSEC_PER_SEC));
        _sync_semaphore_t = NULL;
        if (!self.currentLoadingRequest) {
            TTLog(@"****取消中.....****");
            [self cancelDataTask:NO];
        }
    });
}

- (void)cancelDataTask:(BOOL)isSync {
    if (self.dataTask && self.dataTask.state != NSURLSessionTaskStateCompleted) {
        TTLog(@"**cancelDataTask:**开始取消。。。。");
        [self.dataTask cancel];
        self.dataTask = nil;
        if (isSync) {
            //如果cacel request ,等待代理调用完，在需要线程继续
            _cancel_semaphore_t = dispatch_semaphore_create(0);
            dispatch_semaphore_wait(_cancel_semaphore_t, dispatch_time(DISPATCH_TIME_NOW, 2 *NSEC_PER_SEC));
            _cancel_semaphore_t = NULL;
        }
    }
}

#pragma mark -处理AVAssetResourceLoadingRequest
- (void)handleAssetResourceLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest {
    if (!_data) {
        //初始化 存储DATA
        _data = [[TTResourceLoaderData alloc] initWithURL:loadingRequest.request.URL.absoluteString];
        __weak typeof(self) weakSelf = self;
        [TTReachabilityManager sharedReachabilityManager].reachableStatusChanged = ^(BOOL isReachable) {
            if (isReachable) {
                [weakSelf reloadLoadingRequestWhenHasNetError];
            }
        };
    }
    TTLog(@"\n\n ********************* 开始一次数据加载*********************\n");
    
    //TT_requestsAllDataToEndOfResource == NO 时新建请求，快进时会创建改loadingRequest

    if (@available(iOS 9.0, *)) {//iOS 9.0 以上
        loadingRequest.dataRequest.TT_requestsAllDataToEndOfResource = loadingRequest.dataRequest.requestsAllDataToEndOfResource;
    }else {
        AVAssetResourceLoadingDataRequest *dataRequest = loadingRequest.dataRequest;
        long long r_length = dataRequest.requestedOffset + dataRequest.requestedLength;
        if (_data.contentLength == r_length) {
            dataRequest.TT_requestsAllDataToEndOfResource = YES;
        }else {
            dataRequest.TT_requestsAllDataToEndOfResource = NO;
        }
    }
    
    if (loadingRequest.dataRequest.TT_requestsAllDataToEndOfResource == NO && loadingRequest.dataRequest.requestedOffset != 0) {
        NSURLRequest *request = [self requestWithLoadingRequest:loadingRequest toEnd:NO];
        __block NSURLSessionDataTask *dataTask = nil;
        url_session_manager_create_task_safely(^{
            dataTask = [self.session dataTaskWithRequest:request];
        });
        [_data addLoadingRequest:loadingRequest dataTask:dataTask];
        [dataTask resume];
        TTLog(@"***TT_requestsAllDataToEndOfResource ==NO***-%@--",loadingRequest);
        return;
    }
    
    if (![_data needContinueNetworking:loadingRequest]) {
        TTLog(@"读取本地缓存==》%@",loadingRequest);
        return;
    }
    
    [_data cancelLoadingRequestWithTaskId:self.dataTask.taskIdentifier];
    [_data cancelNoRequestsAllDataToEndOfResourceTask];
    
    NSURLRequest *request = [self requestWithLoadingRequest:loadingRequest toEnd:YES];
    
    [self cancelDataTask:YES];
    
    __block NSURLSessionDataTask *dataTask = nil;
    url_session_manager_create_task_safely(^{
        dataTask = [self.session dataTaskWithRequest:request];
    });
    self.dataTask = dataTask;

    [_data addLoadingRequest:loadingRequest dataTask:dataTask];

    [dataTask resume];

    TTLog(@"\n\n*******网络请求-loadingRequest:%@ \n",loadingRequest);
}

- (void)reloadLoadingRequestWhenHasNetError {
    dispatch_async(TT_resourceLoader_deal_queue(), ^{
        [_data reloadLoadingRequestWhenHasNetError];
    });
}

/**
 根据loadingRequest  组装新的NSURLRequest

 @param loadingRequest <#loadingRequest description#>
 @param toEnd YES 请求至结尾，NO组装
 @return <#return value description#>
 */
- (NSURLRequest *)requestWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest toEnd:(BOOL)toEnd{
    long long requestOffset  = loadingRequest.dataRequest.currentOffset;
    long long requsedtLength =  loadingRequest.dataRequest.requestedLength;
    long long requestEnd     = requestOffset + requsedtLength - 1;
    
    NSMutableURLRequest *mutableURLRequest = [loadingRequest.request mutableCopy];
    //设置缓存策略
    mutableURLRequest.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    
    _url = [loadingRequest.request.URL.absoluteString stringByReplacingOccurrencesOfString:TTPlayerCustomProtocol withString:@""];
    mutableURLRequest.URL = [NSURL URLWithString:_url];
    
    TTLog(@">>>下载URL>>:%@",_url);
    
    ////计算组装 Range ///////////////////
    if (toEnd) {
        [mutableURLRequest setValue:[NSString stringWithFormat:@"bytes=%lld-",requestOffset] forHTTPHeaderField:@"Range"];
    }else {
        [mutableURLRequest setValue:[NSString stringWithFormat:@"bytes=%lld-%lld",requestOffset,requestEnd] forHTTPHeaderField:@"Range"];
    }
    /////////////////////////////////////////////
    
    return mutableURLRequest;
}

#pragma mark -下载数据
- (void)TT_downloadTaskDataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response {
    [self showNetworkActivityIndicator];
    dispatch_sync(TT_resourceLoader_deal_queue(), ^{
        if (!_data.hasConfigured) {
            [_data configContentLength:[TTResourceLoaderData caculateVideoResponseContentLength:(NSHTTPURLResponse *)response] MIMEType:response.MIMEType];
        }
    });
}

- (void)TT_downloadTaskDataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [_data appendData:data taskId:dataTask.taskIdentifier];
}

- (void)TT_downloadTaskDataTask:(NSURLSessionDataTask *)task didCompleteWithError:(NSError *)error {
    [_data taskCompleteWithError:error taskId:task.taskIdentifier];
    if (error && error.code == NSURLErrorCancelled && _cancel_semaphore_t && self.dataTask == task) {
        dispatch_semaphore_signal(_cancel_semaphore_t);
    }
    [self hideNetworkActivityIndicator];
}


#pragma mark -----------------------
#pragma mark -seesion
- (NSURLSession *)session {
    if (!_session) {
        NSOperationQueue *operationQueue = [[NSOperationQueue alloc] init];
        operationQueue.name = @"tt.opeationQueue.download";
        operationQueue.maxConcurrentOperationCount = 1;
        TTResourceLoaderDownloadTask  *downloadTask = [TTResourceLoaderDownloadTask new];
        downloadTask.downloadDelegate = self;
        //NSURLSession delegate会retain 代理，故新建
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:downloadTask delegateQueue:operationQueue];
    }
    return _session;
}


#pragma mark -help
- (void)showNetworkActivityIndicator {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    });
}

- (void)hideNetworkActivityIndicator {
    if ([_data hasDataTaskRequesting]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    });
}

@end

@implementation TTResourceLoaderDownloadTask
{
    NSUInteger _dowloadTotal;
    NSUInteger _speed;
    CFAbsoluteTime _time;
    NSNotificationCenter *_notificationCenter;
}
- (void)dealloc {
    _notificationCenter = nil;
}

- (instancetype)init {
    if (self = [super init]) {
        _notificationCenter = [NSNotificationCenter defaultCenter];
    }
    return self;
}

/** 计算下载速度 */
- (void)caculateDownloadSpeed {
    CFAbsoluteTime currentTime = CFAbsoluteTimeGetCurrent();
    //计算一秒内的速度
    CFAbsoluteTime intervalTime = currentTime - _time; //间隔
    if (intervalTime >= 1) {
        _speed = _dowloadTotal/intervalTime;
        NSString *speedString ;
        if ([self respondsToSelector:@selector(transformBytesToString:)]) {
            speedString = [self transformBytesToString:_speed];
        }else {
            speedString = @"0";
        }
        dispatch_block_t block = ^() {
            [_notificationCenter postNotificationName:TTVideoDownloadSpeedNotification object:nil userInfo:@{TTDownloadSpeed:speedString}];
        };
        dispatch_async(dispatch_get_main_queue(), block);
        _dowloadTotal = 0;
        _time = currentTime;
    }
}

- (void)postDownloadFinishedNotificationWithError:(NSError *)error {
    dispatch_block_t block = ^() {
        [_notificationCenter postNotificationName:TTVideoDownloadSpeedNotification object:nil userInfo:@{TTDownloadFinished:@(YES)}];
        if (error && error.code != NSURLErrorCancelled) {
            [_notificationCenter postNotificationName:TTVideoDownloadFailNotification object:nil userInfo:@{TTDownloadError:error}];
        }
    };
    dispatch_async(dispatch_get_main_queue(), block);
}

/** 转换速度成 B/s KB/s M/s */
- (NSString *)transformBytesToString:(NSUInteger)speed {
    static NSUInteger cell_KB  = 1<<10; //1024
    static NSUInteger cell_M = 1 << 20;//1024 *1024
    NSString *speedString = nil;
    if (speed < cell_KB) {
        speedString = [NSString stringWithFormat:@"%luB/s",(unsigned long)speed];
    }else if (speed < cell_M) {
        speedString = [NSString stringWithFormat:@"%luKB/s",(unsigned long)(speed/cell_KB)];
    }else {
        speedString = [NSString stringWithFormat:@"%luM/s",(unsigned long)(speed/cell_M)];
    }
    return speedString;
}


#pragma mark -NSURLSessionDownloadDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if (_downloadDelegate && [_downloadDelegate respondsToSelector:@selector(TT_downloadTaskDataTask:didReceiveResponse:)]) {
        [_downloadDelegate TT_downloadTaskDataTask:dataTask didReceiveResponse:response];
    }else {
        completionHandler(NSURLSessionResponseCancel);
        return;
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(nullable NSError *)error {
    [_downloadDelegate TT_downloadTaskDataTask:(NSURLSessionDataTask *)task didCompleteWithError:error];
    [self postDownloadFinishedNotificationWithError:error];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data {
    [_downloadDelegate TT_downloadTaskDataTask:dataTask didReceiveData:data];
    
    _dowloadTotal += data.length;
    [self caculateDownloadSpeed];
}

@end
