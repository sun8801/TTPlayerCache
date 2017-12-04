//
//  TTReachabilityManager.h
//  TTPlayerCache
//
//  Created by sunzongtang on 2017/11/21.
//  Copyright © 2017年 szt. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^TTReachabilityStateChangedBlock)(BOOL isReachable);

@interface TTReachabilityManager : NSObject

+ (instancetype)sharedReachabilityManager;

@property (nonatomic, copy) TTReachabilityStateChangedBlock reachableStatusChanged;

@end
