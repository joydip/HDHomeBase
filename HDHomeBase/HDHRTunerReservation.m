//
//  HDHRTunerReservation.m
//  HDHomeBase
//
//  Created by Joydip Basu on 9/2/14.
//  Copyright (c) 2014 Joydip Basu. All rights reserved.
//

#import "HDHRTunerReservation.h"
#import "HDHRDevice.h"

@implementation HDHRTunerReservation


+ (instancetype)tunerReservationWithDevice:(HDHRDevice *)device
                                tunerIndex:(UInt8)tunerIndex
{
    return [[self alloc] initWithDevice:device tunerIndex:tunerIndex];
}

- (instancetype)initWithDevice:(HDHRDevice *)device
                    tunerIndex:(UInt8)tunerIndex
{
    if ((self = [super init])) {
        _device = device;
        _tunerIndex = tunerIndex;
    }
    
    return self;
}

- (NSString *)targetIPAddress
{
    return self.device.targetIPAddress;
}

- (void)tuneToChannel:(NSString *)channel tuningCompletedBlock:(void (^)(void))block
{
    NSLog(@"tuning to channel %@", channel);
    
    hdhr_response_block_t responseBlock = ^(HDHRPacket *responsePacket) {
        // XXX check if response failure
        block();
    };
    
    [self.device setValueForName:[NSString stringWithFormat:@"/tuner%hhu/vchannel", self.tunerIndex]
                    value:channel
            responseBlock:responseBlock];
}

- (void)startStreamingToIPAddress:(NSString *)ipAddress port:(UInt16)port
{
    hdhr_response_block_t responseBlock = ^(HDHRPacket *responsePacket) {
    };
    
    [self.device setValueForName:[NSString stringWithFormat:@"/tuner%hhu/target", self.tunerIndex]
                           value:[NSString stringWithFormat:@"%@:%hu", ipAddress, port]
                   responseBlock:responseBlock];
}

@end
