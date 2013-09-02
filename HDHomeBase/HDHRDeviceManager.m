//
//  HDHRDeviceManager.m
//  HDHomeBase
//
//  Created by Joydip Basu on 4/18/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HDHRDeviceManager.h"
#import "HDHRPacket.h"
#import "HDHRTLVFragment.h"
#import "HDHRDevice.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>

@interface HDHRDeviceManager ()

@property (nonatomic, strong) NSMutableArray *openSocketSources;
@property (strong) NSMutableArray *discoveredDevices;

@end

@implementation HDHRDeviceManager

- (BOOL)startDiscoveryAndError:(NSError **)error
{
    self.openSocketSources = [NSMutableArray new];
    self.discoveredDevices = [NSMutableArray new];
    
    struct ifaddrs *ifAddrs;
    
    if (getifaddrs(&ifAddrs) != 0) {
        if (*error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        
        return NO;
    }
    
    for (struct ifaddrs *ifAddr = ifAddrs; ifAddr; ifAddr = ifAddr->ifa_next) {
        // if the interface is not UP, move on
        if (!(ifAddr->ifa_flags & IFF_UP))
            continue;

        struct sockaddr *sockAddr = ifAddr->ifa_addr;
        
        // if there's no IP address, move on
        if (!sockAddr)
            continue;
        
        // if there's an IPv4 address and the interface supports broadcasting, send a discovery packet
        if ((sockAddr->sa_family == AF_INET) && (ifAddr->ifa_flags & IFF_BROADCAST)) {
            struct sockaddr_in *sockAddrIn = (struct sockaddr_in *)sockAddr;
            struct sockaddr_in *broadcastSockAddrIn = (struct sockaddr_in *)ifAddr->ifa_broadaddr;
            
            if (![self broadcastDiscoveryPacketFromAddress:*sockAddrIn toAddress:*broadcastSockAddrIn error:error])
                return NO;
        }
    }
    
    freeifaddrs(ifAddrs);
    
    return YES;
}

- (BOOL)broadcastDiscoveryPacketFromAddress:(struct sockaddr_in)sockAddrIn toAddress:(struct sockaddr_in)broadcastSockAddrIn error:(NSError **)error
{    
    int socketfd = socket(PF_INET, SOCK_DGRAM, 0);
    
	if (socketfd == -1) {
		if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        
        return NO;
	}
    
	if (fcntl(socketfd, F_SETFL, O_NONBLOCK) == -1) {
		if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        
		close(socketfd);
		return NO;
	}
    
	const int socketfdOptions = 1;
	if (setsockopt(socketfd, SOL_SOCKET, SO_BROADCAST, &socketfdOptions, sizeof(socketfdOptions)) != 0) {
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        
        return NO;
    }
    
    sockAddrIn.sin_port = htons(0);
    if (bind(socketfd, (struct sockaddr *)&sockAddrIn, sizeof(sockAddrIn)) != 0) {
        if (error)
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        
        return NO;
    }
    
    broadcastSockAddrIn.sin_port = htons(65001);
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t socketReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, socketfd, 0, queue);
    
    [self.openSocketSources addObject:socketReadSource];
    
    dispatch_source_set_event_handler(socketReadSource, ^{
        size_t estimatedReadLength = dispatch_source_get_data(socketReadSource);
        UInt8 *bytes = (UInt8 *)malloc(estimatedReadLength);

        if (bytes) {
            struct sockaddr_in theirAddress;
            socklen_t addressLength = sizeof(theirAddress);
            
            ssize_t receivedByteCount = recvfrom(socketfd,
                                                 bytes,
                                                 estimatedReadLength,
                                                 0,
                                                 (struct sockaddr *)&theirAddress,
                                                 &addressLength);
            
            struct in_addr remoteIPAddress = ((struct sockaddr_in *)&theirAddress)->sin_addr;
            struct in_addr localIPAddress = ((struct sockaddr_in *)&sockAddrIn)->sin_addr;
            
            NSString *remoteIPAddressString = [NSString stringWithCString:inet_ntoa(remoteIPAddress)
                                                                 encoding:NSASCIIStringEncoding];
            NSString *localIPAddressString = [NSString stringWithCString:inet_ntoa(localIPAddress)
                                                                 encoding:NSASCIIStringEncoding];

            [self examineDiscoverReplyBytes:bytes
                                     length:receivedByteCount
                            remoteIPAddress:remoteIPAddressString
                             localIPAddress:localIPAddressString];
            free(bytes);
        }
    });
    
    dispatch_source_set_cancel_handler(socketReadSource, ^{
        close(socketfd);
    });
    
    dispatch_resume(socketReadSource);

    // send the discover request
    HDHRPacket *discoverRequestPacket = [HDHRPacket discoverRequestPacket];

    NSUInteger totalNumberOfBytesSent = 0;
    
    while (totalNumberOfBytesSent < discoverRequestPacket.data.length) {
        // XXX need to peek here to make sure this is at least 23 bytes
        ssize_t numberOfBytesSent = sendto(socketfd,
                                           discoverRequestPacket.data.bytes,
                                           discoverRequestPacket.data.length,
                                           0,
                                           (struct sockaddr *)&broadcastSockAddrIn,
                                           sizeof(broadcastSockAddrIn));
        
        if (numberOfBytesSent == -1) {
            if (error)
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            
            dispatch_source_cancel(socketReadSource);
            
            return NO;
        }
        
        totalNumberOfBytesSent += numberOfBytesSent;
    }
    
    return YES;
}

- (void)stopDiscovery
{    
    for (dispatch_source_t openSocketSource in self.openSocketSources)
        dispatch_source_cancel(openSocketSource);

    _devices = [self.discoveredDevices copy];

    self.openSocketSources = nil;
    self.discoveredDevices = nil;
}

- (void)examineDiscoverReplyBytes:(const UInt8 *)bytes
                           length:(ssize_t)length
                  remoteIPAddress:(NSString *)remoteIPAddress
                   localIPAddress:(NSString *)localIPAddress
{
    NSData *receivedData = [NSData dataWithBytes:bytes length:length];

    /*
    NSLog(@"discover reply:");
    NSLog(@"\tsource address: %@", remoteIPAddress);
    NSLog(@"\tlength: %lu", (unsigned long)length);
    NSLog(@"\tdata: %@", receivedData);
    */
    
    NSArray *tlvFragments = [[[HDHRPacket alloc] initWithPacketData:receivedData] tlvFragments];
    
    NSString *deviceIDString = nil;
    UInt8 tunerCount = 0;
    
    for (HDHRTLVFragment *fragment in tlvFragments) {
        switch (fragment.tag) {
            case HDHRDeviceIDTag: {
                UInt8 *deviceIDBytes = (UInt8 *)fragment.valueData.bytes;
                deviceIDString = [NSString stringWithFormat:@"%0X%0X%0X%0X",
                                  deviceIDBytes[0],
                                  deviceIDBytes[1],
                                  deviceIDBytes[2],
                                  deviceIDBytes[3]];
            }
                break;
            
            case HDHRTunerCountTag:
                tunerCount = fragment.uint8Value;
                
            default:
                break;
        }
    }
    
    if (deviceIDString && tunerCount) {        
        HDHRDevice *device = [HDHRDevice deviceWithID:deviceIDString
                                      deviceIPAddress:remoteIPAddress
                                      targetIPAddress:localIPAddress
                                           tunerCount:tunerCount];
        
        [self.discoveredDevices addObject:device];
    }
}

@end
