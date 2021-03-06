//
//  RTListener.m
//  backendlessAPI
/*
 * *********************************************************************************************************************
 *
 *  BACKENDLESS.COM CONFIDENTIAL
 *
 *  ********************************************************************************************************************
 *
 *  Copyright 2018 BACKENDLESS.COM. All Rights Reserved.
 *
 *  NOTICE: All information contained herein is, and remains the property of Backendless.com and its suppliers,
 *  if any. The intellectual and technical concepts contained herein are proprietary to Backendless.com and its
 *  suppliers and may be covered by U.S. and Foreign Patents, patents in process, and are protected by trade secret
 *  or copyright law. Dissemination of this information or reproduction of this material is strictly forbidden
 *  unless prior written permission is obtained from Backendless.com.
 *
 *  ********************************************************************************************************************
 */

#import "RTListener.h"
#import "RTClient.h"
#import "RTSubscription.h"
#import "Backendless.h"

@interface RTListener() {
    NSMutableDictionary<NSString *, NSMutableArray<RTSubscription *> *> *subscriptions;
    NSMutableDictionary<NSString *, NSMutableArray *> *simpleListeners;
    void(^onStop)(RTSubscription *);
    void(^onReady)(void);
}
@end

@implementation RTListener

-(instancetype)init {
    if (self = [super init]) {
        subscriptions = [NSMutableDictionary<NSString *, NSMutableArray<RTSubscription *> *> new];
        simpleListeners = [NSMutableDictionary<NSString *, NSMutableArray *> new];
    }
    return self;
}

-(void)addSubscription:(NSString *)type options:(NSDictionary *)options onResult:(void(^)(id))onResult onError:(void(^)(Fault *))onError handleResultSelector:(SEL)handleResultSelector fromClass:(id)subscriptionClassInstance {
    NSString *subscriptionId = [[NSUUID UUID] UUIDString];
    NSDictionary *data = @{@"id"        : subscriptionId,
                           @"name"      : type,
                           @"options"   : options};
    
    __weak NSMutableDictionary<NSString *, NSMutableArray<RTSubscription *> *> *weakSubscriptions = subscriptions;
    __weak NSMutableDictionary<NSString *, NSMutableArray *> *weakSimpleListeners = simpleListeners;
    
    onStop = ^(RTSubscription *subscription) {
        NSMutableArray *subscriptionStack = [NSMutableArray arrayWithArray:[weakSubscriptions valueForKey:subscription.type]] ? [NSMutableArray arrayWithArray:[weakSubscriptions valueForKey:type]] : [NSMutableArray new];
        [subscriptionStack removeObject:subscription];
    };
    
    onReady = ^{
        NSArray *readyCallbacks = [NSArray arrayWithArray:[weakSimpleListeners valueForKey:type]];
        for (int i = 0; i < [readyCallbacks count]; i++) {
            void(^readyBlock)(id) = [readyCallbacks objectAtIndex:i];
            readyBlock(nil);
        }
    };
    
    RTSubscription *subscription = [RTSubscription new];
    subscription.subscriptionId = subscriptionId;
    subscription.type = type;
    subscription.options = [NSDictionary dictionaryWithDictionary:options];
    subscription.onResult = onResult;
    subscription.onError = onError;
    subscription.onStop = onStop;
    subscription.onReady = onReady;
    subscription.ready = NO;
    subscription.handleResult = handleResultSelector;
    subscription.classInstance = subscriptionClassInstance;
    
    [rtClient subscribe:data subscription:subscription];
    
    NSString *typeName = [data valueForKey:@"name"];
    if ([typeName isEqualToString:OBJECTS_CHANGES]) {
        typeName = [[data valueForKey:@"options"] valueForKey:@"event"];
    }
    NSMutableArray *subscriptionStack = [NSMutableArray arrayWithArray:[subscriptions valueForKey:typeName]];
    if (!subscriptionStack) {
        subscriptionStack = [NSMutableArray new];
    }
    [subscriptionStack addObject:subscription];
    [subscriptions setObject:subscriptionStack forKey:typeName];
}

-(void)stopSubscription:(NSString *)event whereClause:(NSString *)whereClause {
    NSMutableArray *subscriptionStack = [NSMutableArray arrayWithArray:[subscriptions valueForKey:event]];
    if (event && subscriptionStack) {
        if (whereClause) {
            for (RTSubscription *subscription in subscriptionStack) {
                if ([subscription.options valueForKey:@"whereClause"] && [[subscription.options valueForKey:@"whereClause"] isEqualToString:whereClause]) {
                    [subscription stop];
                }
            }
        }
        else {
            for (RTSubscription *subscription in subscriptionStack) {
                [subscription stop];
            }
        }
    }
    else if (!event) {
        for (NSString *eventName in [subscriptions allKeys]) {
            NSMutableArray *subscriptionStack = [NSMutableArray arrayWithArray:[subscriptions valueForKey:eventName]];
            if (subscriptionStack) {
                for (RTSubscription *subscription in subscriptionStack) {
                    [subscription stop];
                }
            }
        }
    }
}

-(void)stopSubscriptionWithChannel:(Channel *)channel event:(NSString *)event whereClause:(NSString *)whereClause {
    NSMutableArray *subscriptionStack = [NSMutableArray arrayWithArray:[subscriptions valueForKey:event]];
    if (channel && event && subscriptionStack) {
        if (whereClause) {
            for (RTSubscription *subscription in subscriptionStack) {
                if ([subscription.options valueForKey:@"channel"] && [[subscription.options valueForKey:@"channel"] isEqualToString:channel.channelName] && [subscription.options valueForKey:@"selector"] && [[subscription.options valueForKey:@"selector"] isEqualToString:whereClause]) {
                    [subscription stop];
                }
            }
        }
        else {
            for (RTSubscription *subscription in subscriptionStack) {
                [subscription stop];
            }
        }
    }
    else if (!event) {
        for (NSString *eventName in [subscriptions allKeys]) {
            NSMutableArray *subscriptionStack = [NSMutableArray arrayWithArray:[subscriptions valueForKey:eventName]];
            if (subscriptionStack) {
                for (RTSubscription *subscription in subscriptionStack) {
                    [subscription stop];
                }
            }
        }
    }
    if ([subscriptionStack count] == 0) {
        channel.isJoined = NO;
    }
}

-(void)stopSubscriptionWithSharedObject:(NSString *)sharedObjectName event:(NSString *)event {
    NSMutableArray *subscriptionStack = [NSMutableArray arrayWithArray:[subscriptions valueForKey:event]];
    if (sharedObjectName && event && subscriptionStack) {
        for (RTSubscription *subscription in subscriptionStack) {
            [subscription stop];
        }
    }
    else if (!event) {
        for (NSString *eventName in [subscriptions allKeys]) {
            NSMutableArray *subscriptionStack = [NSMutableArray arrayWithArray:[subscriptions valueForKey:eventName]];
            if (subscriptionStack) {
                for (RTSubscription *subscription in subscriptionStack) {
                    [subscription stop];
                }
            }
        }
    }
}

-(void)removeAllListeners {
    [subscriptions removeAllObjects];
}

@end
