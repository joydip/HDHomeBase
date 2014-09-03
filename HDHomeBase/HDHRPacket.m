//
//  HDHRPacket.m
//  HDHomeBase
//
//  Created by Joydip Basu on 4/19/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HDHRPacket.h"
#import "HDHRTLVFragment.h"
#import "HDHRTypes.h"

@interface HDHRPacket ()

@property (nonatomic, strong) NSData *data;

@end

@implementation HDHRPacket

+ (UInt32)crc32ForData:(NSData *)data
{
    const UInt8 *bytes = (const UInt8 *)data.bytes;
    NSUInteger dataLength = data.length;

    UInt32 crc32 = 0xFFFFFFFF;
    
	for (NSUInteger index = 0; index < dataLength; index++) {
		UInt8 x = (UInt8)(crc32) ^ bytes[index];
		crc32 >>= 8;
		if (x & 0x01) crc32 ^= 0x77073096;
		if (x & 0x02) crc32 ^= 0xEE0E612C;
		if (x & 0x04) crc32 ^= 0x076DC419;
		if (x & 0x08) crc32 ^= 0x0EDB8832;
		if (x & 0x10) crc32 ^= 0x1DB71064;
		if (x & 0x20) crc32 ^= 0x3B6E20C8;
		if (x & 0x40) crc32 ^= 0x76DC4190;
		if (x & 0x80) crc32 ^= 0xEDB88320;
	}

	return crc32 ^ 0xFFFFFFFF;
}
         
+ (instancetype)discoverRequestPacket
{
    return [[self alloc] initWithType:HDHRPacketDiscoverRequest
                         tlvFragments:
            [HDHRTLVFragment tlvFragmentWithTag:HDHRDeviceTypeTag
                                    uint32Value:HDHRDeviceTypeTuner],
            [HDHRTLVFragment tlvFragmentWithTag:HDHRDeviceIDTag
                                    uint32Value:HDHRDeviceIDWildcard],
            nil];
}

- (instancetype)initWithPacketData:(NSData *)data
{
    if ((self = [super init]))
        _data = [data copy];
    
    return self;
}

- (instancetype)initWithType:(HDHRPacketType)type tlvFragments:(HDHRTLVFragment *)firstTLVFragment, ...
{
    NSMutableData *payloadMutableData = [NSMutableData data];
    
    HDHRTLVFragment *eachTLVFragment;
    va_list argumentList;

    if (firstTLVFragment) {
        [payloadMutableData appendData:firstTLVFragment.tlvData];
        
        va_start(argumentList, firstTLVFragment);
        while ((eachTLVFragment = va_arg(argumentList, HDHRTLVFragment *)))
            [payloadMutableData appendData:eachTLVFragment.tlvData];
        va_end(argumentList);
    }

    if (payloadMutableData.length > 1452)
        return nil;
    
    NSMutableData *packetMutableData = [NSMutableData data];
    
    UInt16 bigEndianType = NSSwapHostShortToBig(type);
    [packetMutableData appendBytes:&bigEndianType length:2];

    UInt16 bigEndianLength = NSSwapHostShortToBig((UInt16)payloadMutableData.length);
    [packetMutableData appendBytes:&bigEndianLength length:2];
    
    [packetMutableData appendData:payloadMutableData];
    
    UInt32 littleEndianCRC32 = NSSwapHostIntToLittle([[self class] crc32ForData:packetMutableData]);
    [packetMutableData appendBytes:&littleEndianCRC32 length:4];
    
    return [self initWithPacketData:packetMutableData];
}

- (HDHRPacketType)type
{
    return NSSwapBigShortToHost(*(UInt16 *)self.data.bytes);
}

- (NSData *)payloadData
{
    // use advertised length?
    return [self.data subdataWithRange:NSMakeRange(4, self.data.length-8)];
}

- (NSArray *)tlvFragments
{
    NSMutableArray *tlvFragments = [NSMutableArray new];
    
    const UInt8 *payloadBytes = self.payloadData.bytes;
    
    NSUInteger index = 0;
    NSUInteger payloadLength = self.payloadData.length;
    
    while (index < payloadLength) {
        HDHRTag tag = payloadBytes[index];
        index++;
        UInt8 length = payloadBytes[index];
        index++;
        NSData *value = [NSData dataWithBytes:(void *)&payloadBytes[index] length:length];
        index += length;
        [tlvFragments addObject:[HDHRTLVFragment tlvFragmentWithTag:tag dataValue:value]];
    }
    
    return [tlvFragments copy];
}

@end
