//
//  HDHRTunerReservation.h
//  HDHomeBase
//
//  Created by Joydip Basu on 9/2/14.
//  Copyright (c) 2014 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HDHRDevice;


@interface HDHRTunerReservation : NSObject

@property (nonatomic, strong, readonly) HDHRDevice *device;
@property (nonatomic, assign, readonly) UInt8 tunerIndex;

+ (instancetype)tunerReservationWithDevice:(HDHRDevice *)device
                                tunerIndex:(UInt8)tunerIndex;

- (instancetype)initWithDevice:(HDHRDevice *)device
                    tunerIndex:(UInt8)tunerIndex;

- (NSString *)targetIPAddress;

- (void)tuneToChannel:(NSString *)channel tuningCompletedBlock:(void (^)(void))block;
- (void)startStreamingToIPAddress:(NSString *)ipAddress port:(UInt16)port;

@end
