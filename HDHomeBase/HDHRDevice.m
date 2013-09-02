//
//  HDHRDevice.m
//  HDHomeBase
//
//  Created by Joydip Basu on 4/20/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HDHRDevice.h"
#import "HDHRPacket.h"
#import "HDHRTLVFragment.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>


@implementation HDHRDevice

+ (instancetype)deviceWithID:(NSString *)deviceID
             deviceIPAddress:(NSString *)deviceIPAddress
             targetIPAddress:(NSString *)targetIPAddress
                  tunerCount:(UInt8)tunerCount
{
    return [[self alloc] initWithID:deviceID
                    deviceIPAddress:deviceIPAddress
                    targetIPAddress:targetIPAddress
                         tunerCount:tunerCount];
}

- (instancetype)initWithID:(NSString *)deviceID
           deviceIPAddress:(NSString *)deviceIPAddress
           targetIPAddress:(NSString *)targetIPAddress
                tunerCount:(UInt8)tunerCount
{
    if ((self = [super init])) {
        _deviceID = deviceID;
        _deviceIPAddress = [deviceIPAddress copy];
        _targetIPAddress = [targetIPAddress copy];
        _tunerCount = tunerCount;
    }
    
    return self;
}

- (void)getValueForName:(NSString *)name responseBlock:(hdhr_response_block_t)responseBlock
{
    HDHRPacket *getRequestPacket = [[HDHRPacket alloc] initWithType:HDHRPacketGetSetRequest
                                                       tlvFragments:[HDHRTLVFragment tlvFragmentWithTag:HDHRGetSetNameTag stringValue:name], nil];
    
    [self sendRequestPacket:getRequestPacket responseBlock:responseBlock];
}

- (void)setValueForName:(NSString *)name value:(NSString *)value responseBlock:(hdhr_response_block_t)responseBlock
{
    HDHRPacket *getRequestPacket = [[HDHRPacket alloc] initWithType:HDHRPacketGetSetRequest
                                                       tlvFragments:[HDHRTLVFragment tlvFragmentWithTag:HDHRGetSetNameTag stringValue:name],
                                                                    [HDHRTLVFragment tlvFragmentWithTag:HDHRGetSetValueTag stringValue:value],
                                                                    nil];
    
    [self sendRequestPacket:getRequestPacket responseBlock:responseBlock];
}

- (BOOL)sendRequestPacket:(HDHRPacket *)requestPacket responseBlock:(hdhr_response_block_t)responseBlock
{
    __autoreleasing NSError **error = NULL;
    
    // NSLog(@"opening control socket");

    int socketfd = socket(PF_INET, SOCK_STREAM, 0);
    
    if (socketfd == -1) {
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];

        return NO;
    }
    
    struct sockaddr_in sockAddrIn;
    sockAddrIn.sin_family = AF_INET;
    sockAddrIn.sin_port = htons(65001);
    sockAddrIn.sin_addr.s_addr = inet_addr([self.deviceIPAddress cStringUsingEncoding:NSASCIIStringEncoding]);
    memset(sockAddrIn.sin_zero, '\0', sizeof(sockAddrIn.sin_zero));
    
    int result = connect(socketfd, (struct sockaddr *)&sockAddrIn, sizeof(sockAddrIn));

    if (result != 0) {
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
                    NSLog(@"foo2");
        return NO;
    }
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t socketReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, socketfd, 0, queue);
    
    dispatch_source_set_event_handler(socketReadSource, ^{
        size_t estimatedReadLength = dispatch_source_get_data(socketReadSource);
        UInt8 *bytes = (UInt8 *)malloc(estimatedReadLength);
        
        if (bytes) {
            ssize_t receivedByteCount = recv(socketfd,
                                             bytes,
                                             estimatedReadLength,
                                             0);

            NSData *data = [NSData dataWithBytes:bytes length:receivedByteCount];

            if (responseBlock)
                responseBlock([[HDHRPacket alloc] initWithPacketData:data]);
            
            free(bytes);
            dispatch_source_cancel(socketReadSource);
        }
    });
    
    dispatch_source_set_cancel_handler(socketReadSource, ^{
        // NSLog(@"closing control socket");
        close(socketfd);
    });
    
    dispatch_resume(socketReadSource);
    
    
    NSUInteger totalNumberOfBytesSent = 0;
    
    while (totalNumberOfBytesSent < requestPacket.data.length) {
        // XXX need to peek here to make sure this is at least 23 bytes
        ssize_t numberOfBytesSent = send(socketfd,
                                         requestPacket.data.bytes,
                                         requestPacket.data.length,
                                         0);
        
        if (numberOfBytesSent == -1) {
            if (error)
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            NSLog(@"fooi8");
            dispatch_source_cancel(socketReadSource);
            
            return NO;
        }
        
        totalNumberOfBytesSent += numberOfBytesSent;
    }

    return YES;
}

@end
