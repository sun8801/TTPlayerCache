# TTPlayerCache
AVPlayer 视频离线缓存、可以边下边播放、部分缓存、断网处理、AVAssetResourceLoaderDelegate

# [简书地址](http://www.jianshu.com/p/7fe8bce3d76)

# CocoaPods
  > pod  'TTPlayerCache' '~> 0.2.0'
  
 ### 用法:
```
#import <TTPlayerCache.h>
...
//把视频播放地址转成系统不能识别的URL
NSString *videoUrl = @"http://....";
BOOL isMP4 = YES; //是否是mp4格式
videoUrl = isMP4? TTResourceUrlFromOrigianllUrl(videoUrl): videoUrl;
...
...
//设置AVPLayer播放
//初始化代理
self.resourceLoaderDelegate = [TTResourceLoaderDelegate new];
self.urlAsset = [AVURLAsset assetWithURL:self.videoURL];
[self.urlAsset.resourceLoader setDelegate:self.resourceLoaderDelegate queue:TT_resourceLoader_delegate_queue()];
...
```
### 其他
播放除MP4外的格式时，url不需要转换(现不支持MP4格式外的缓存)
    
