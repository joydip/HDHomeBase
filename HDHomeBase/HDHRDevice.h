//
//  HDHRDevice.h
//  HDHomeBase
//
//  Created by Joydip Basu on 4/20/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

@class HDHRPacket;

@interface HDHRDevice : NSObject

typedef void (^hdhr_response_block_t)(HDHRPacket *);

@property (nonatomic, copy, readonly) NSString *deviceID;
@property (nonatomic, copy, readonly) NSString *deviceIPAddress;
@property (nonatomic, copy, readonly) NSString *targetIPAddress;
@property (nonatomic, assign, readonly) UInt8 tunerCount;


+ (instancetype)deviceWithID:(NSString *)deviceID
             deviceIPAddress:(NSString *)deviceIPAddress
             targetIPAddress:(NSString *)targetIPAddress
                  tunerCount:(UInt8)tunerCount;

- (instancetype)initWithID:(NSString *)deviceID
           deviceIPAddress:(NSString *)deviceIPAddress
           targetIPAddress:(NSString *)targetIPAddress
                tunerCount:(UInt8)tunerCount;

- (void)getValueForName:(NSString *)name responseBlock:(hdhr_response_block_t)responseBlock;
- (void)setValueForName:(NSString *)name value:(NSString *)value responseBlock:(hdhr_response_block_t)responseBlock;

@end
