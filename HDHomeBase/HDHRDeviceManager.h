//
//  HDHRDeviceManager.h
//  HDHomeBase
//
//  Created by Joydip Basu on 4/18/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HDHRTunerReservation;

@interface HDHRDeviceManager : NSObject

@property (nonatomic, readonly, strong) NSArray *devices;

- (BOOL)startDiscoveryAndError:(NSError **)error;
- (void)stopDiscovery;

- (void)requestTunerReservation:(void (^)(HDHRTunerReservation *, dispatch_semaphore_t))block;

@end
