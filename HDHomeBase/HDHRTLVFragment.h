//
//  HDHRTLVFragment.h
//  HDHomeBase
//
//  Created by Joydip Basu on 4/20/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HDHRTypes.h"

@interface HDHRTLVFragment : NSObject

@property (nonatomic, readonly, assign) HDHRTag tag;
@property (nonatomic, readonly, strong) NSData *valueData;

+ (instancetype)tlvFragmentWithTag:(HDHRTag)tag uint8Value:(UInt8)value;
+ (instancetype)tlvFragmentWithTag:(HDHRTag)tag uint32Value:(UInt32)value;
+ (instancetype)tlvFragmentWithTag:(HDHRTag)tag dataValue:(NSData *)value;
+ (instancetype)tlvFragmentWithTag:(HDHRTag)tag stringValue:(NSString *)value;

- (instancetype)initWithTag:(HDHRTag)tag uint8Value:(UInt8)value;
- (instancetype)initWithTag:(HDHRTag)tag uint32Value:(UInt32)value;
- (instancetype)initWithTag:(HDHRTag)tag dataValue:(NSData *)value;
- (instancetype)initWithTag:(HDHRTag)tag stringValue:(NSString *)value;


- (NSData *)tlvData;

- (UInt8)uint8Value;
- (UInt32)uint32Value;
- (NSString *)stringValue;

@end
