//
//  HDHRPacket.h
//  HDHomeBase
//
//  Created by Joydip Basu on 4/19/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HDHRTypes.h"

@class HDHRTLVFragment;

#define HDHRMaxPacketSize 1460

@interface HDHRPacket : NSObject

@property (nonatomic, readonly) HDHRPacketType type;
@property (nonatomic, readonly, strong) NSData *data;

+ (instancetype)discoverRequestPacket;

- (instancetype)initWithPacketData:(NSData *)data;
- (instancetype)initWithType:(HDHRPacketType)type tlvFragments:(HDHRTLVFragment *)firstTLVFragment, ...;

- (NSArray *)tlvFragments;

@end
