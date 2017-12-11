//
//  AVAssetResourceLoadingDataRequest+TTCategory.h
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/12/5.
//  Copyright © 2017年 szt. All rights reserved.
//requestsAllDataToEndOfResource 在iOS 9以下

#import <AVFoundation/AVFoundation.h>

@interface AVAssetResourceLoadingDataRequest (TTCategory)

//- (BOOL)TT_requestsAllDataToEndOfResource;

@property (nonatomic, assign) BOOL TT_requestsAllDataToEndOfResource;

@end
