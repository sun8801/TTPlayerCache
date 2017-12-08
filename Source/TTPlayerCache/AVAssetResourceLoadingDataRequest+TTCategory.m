//
//  AVAssetResourceLoadingDataRequest+TTCategory.m
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/12/5.
//  Copyright © 2017年 szt. All rights reserved.
//

#import "AVAssetResourceLoadingDataRequest+TTCategory.h"
#import <objc/runtime.h>

@implementation AVAssetResourceLoadingDataRequest (TTCategory)

- (BOOL)TT_requestsAllDataToEndOfResource {
    return [objc_getAssociatedObject(self, @selector(setTT_requestsAllDataToEndOfResource:)) boolValue];
}

- (void)setTT_requestsAllDataToEndOfResource:(BOOL)TT_requestsAllDataToEndOfResource {
    objc_setAssociatedObject(self, _cmd, @(TT_requestsAllDataToEndOfResource), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
