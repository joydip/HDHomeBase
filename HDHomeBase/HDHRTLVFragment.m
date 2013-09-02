//
//  HDHRTLVFragment.m
//  HDHomeBase
//
//  Created by Joydip Basu on 4/20/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HDHRTLVFragment.h"

@implementation HDHRTLVFragment

+ (instancetype)tlvFragmentWithTag:(HDHRTag)tag uint8Value:(UInt8)value
{
    return [[self alloc] initWithTag:tag uint8Value:value];
}

+ (instancetype)tlvFragmentWithTag:(HDHRTag)tag uint32Value:(UInt32)value
{
    return [[self alloc] initWithTag:tag uint32Value:value];
}

+ (instancetype)tlvFragmentWithTag:(HDHRTag)tag dataValue:(NSData *)value
{
    return [[self alloc] initWithTag:tag dataValue:value];
}

+ (instancetype)tlvFragmentWithTag:(HDHRTag)tag stringValue:(NSString *)value
{
    return [[self alloc] initWithTag:tag stringValue:value];
}

- (instancetype)initWithTag:(HDHRTag)tag uint8Value:(UInt8)value
{
    return [self initWithTag:tag bytesValue:&value bytesLength:1];
}

- (instancetype)initWithTag:(HDHRTag)tag uint32Value:(UInt32)value
{
    UInt32 bigEndianValue = NSSwapHostIntToBig(value);
    return [self initWithTag:tag bytesValue:&bigEndianValue bytesLength:4];
}

- (instancetype)initWithTag:(HDHRTag)tag bytesValue:(const void *)value bytesLength:(NSUInteger)length
{
    return [self initWithTag:tag dataValue:[NSData dataWithBytes:value length:length]];
}

- (instancetype)initWithTag:(HDHRTag)tag stringValue:(NSString *)value
{
    return [self initWithTag:tag dataValue:[value dataUsingEncoding:NSASCIIStringEncoding]];
}

- (instancetype)initWithTag:(HDHRTag)tag dataValue:(NSData *)value
{
    if ((self = [super init])) {
        _tag = tag;
        _valueData = value;
    }
    
    return self;
}

- (NSData *)tlvData
{
    NSUInteger valueDataLength = self.valueData.length;
    
    if (valueDataLength > 255)
        return nil;
    
    UInt8 lengthSize = (valueDataLength > 127) ? 2 : 1;
    UInt8 singleLengthByte = (UInt8)valueDataLength;
    
    NSMutableData *tlvData = [NSMutableData dataWithCapacity:1+lengthSize+singleLengthByte];
    [tlvData appendBytes:&_tag length:1];
    
    switch (lengthSize) {
        case 1:
            [tlvData appendBytes:&singleLengthByte length:1];
            break;
            
        case 2: {
            UInt8 firstLengthByte = (singleLengthByte & 0x7F) | 0x80;
            UInt8 secondLengthByte = singleLengthByte >> 7;
            
            [tlvData appendBytes:&firstLengthByte length:1];
            [tlvData appendBytes:&secondLengthByte length:1];
        }
            break;
    }
    
    [tlvData appendData:self.valueData];
    
    return [tlvData copy];
}

- (UInt8)uint8Value
{
    return *(UInt8 *)self.valueData.bytes;
}

- (UInt32)uint32Value
{
    return NSSwapBigIntToHost(*(UInt32 *)self.valueData.bytes);
}

- (NSString *)stringValue
{
    return [NSString stringWithFormat:@"%s", self.valueData.bytes];
}

@end
