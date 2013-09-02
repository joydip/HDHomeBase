//
//  HBRecording.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/2/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBRecording.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <ifaddrs.h>

#import "HDHRPacket.h"
#import "HDHRTLVFragment.h"
#import "HDHRDevice.h"
#import "HBScheduler.h"

@implementation HBRecording

- (id)init
{
    if ((self = [super init])) {
        _paddingOptions = @[ @"None", @"30 minutes", @"1 hour", @"2 hours", @"3 hours", @"6 hours" ];
        _statusIconImage = [NSImage imageNamed:@"history"];
    }
    
    return self;
}

- (void)logStatus:(NSString *)string
{
    NSLog(@"%@", string);
    self.status = string;
}

- (NSDateFormatter *)dateFormatter
{
    NSDateFormatter *dateFormatter = [NSDateFormatter new];
    [dateFormatter setDateFormat:@"yyyyMMddHHmm"];
    return dateFormatter;
}

- (void)startRecording:(id)sender
{
    NSLog(@"starting device discovery...");
    self.statusIconImage = [NSImage imageNamed:@"statusYellow"];
    self.device = nil;
    [self.deviceManager startDiscoveryAndError:NULL];
    [NSTimer scheduledTimerWithTimeInterval:3.0f
                                     target:self
                                   selector:@selector(stopDeviceDiscovery)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)stopDeviceDiscovery
{
    NSLog(@"stopping device discovery");
    
    [self.deviceManager stopDiscovery];
    NSLog(@"%lu device(s) found", (unsigned long)self.deviceManager.devices.count);

    if (self.deviceManager.devices.count) {
        NSLog(@"searching for an available tuner...");
        [self findAvailableTunerOnDevices:self.deviceManager.devices
                              deviceIndex:0
                               tunerIndex:0];
    } else {
        NSLog(@"no devices available");
        self.statusIconImage = [NSImage imageNamed:@"alert"];
    }
}

- (void)findAvailableTunerOnDevices:(NSArray *)devices
                        deviceIndex:(UInt8)deviceIndex
                         tunerIndex:(UInt8)tunerIndex
{
    HDHRDevice *device = [devices objectAtIndex:deviceIndex];
    
    hdhr_response_block_t responseBlock = ^(HDHRPacket *responsePacket) {
        NSString *name = nil;
        NSString *value = nil;
        
        for (HDHRTLVFragment *tlvFragment in responsePacket.tlvFragments) {
            switch (tlvFragment.tag) {
                case HDHRGetSetNameTag:
                    name = tlvFragment.stringValue;
                    value = nil;
                    break;

                case HDHRGetSetValueTag:
                    value = tlvFragment.stringValue;
                    break;
                    
                default:
                    break;
            }

            if ((name && value) && ([name hasSuffix:@"target"])) {
                if ([value isEqualToString:@"none"]) {
                    NSLog(@"tuner %hhu is available", tunerIndex);
                    self.device = device;
                    self.tunerIndex = tunerIndex;
                    [self tuneChannel];
                }
            
                else {
                    NSLog(@"tuner %hhu not available", tunerIndex);
                    
                    if (tunerIndex+1 < device.tunerCount) {
                        NSLog(@"trying tuner %hhu...", (UInt8)(tunerIndex+1));
                        [self findAvailableTunerOnDevices:devices
                                              deviceIndex:deviceIndex
                                               tunerIndex:tunerIndex+1];
                    }
                    
                    else {
                        NSLog(@"no more tuners available on device");
                        
                        if (deviceIndex+1 < devices.count) {
                            NSLog(@"trying device %hhu", (UInt8)(deviceIndex+1));
                            [self findAvailableTunerOnDevices:devices
                                                  deviceIndex:deviceIndex+1
                                                   tunerIndex:0];
                        } else {
                            NSLog(@"no more devices available");
                        }
                    }
                }
            }
        }
    };

    [device getValueForName:[NSString stringWithFormat:@"/tuner%hhu/target", tunerIndex]
              responseBlock:responseBlock];
}

- (void)tuneChannel
{
    NSLog(@"tuning to channel %@", self.rfChannel);

    hdhr_response_block_t responseBlock = ^(HDHRPacket *responsePacket) {
        // XXX check if response failure
        [self startSavingUDPStream];
    };

    [self.device setValueForName:[NSString stringWithFormat:@"/tuner%hhu/vchannel", self.tunerIndex]
                           value:self.rfChannel
                   responseBlock:responseBlock];
}

- (BOOL)startSavingUDPStream
{
    NSLog(@"saving UDP stream");
    NSString *startDateString = [self.dateFormatter stringFromDate:self.startDate];
    NSMutableString *baseName = [self.title mutableCopy];
    
    if (self.episode.length)
        [baseName appendFormat:@" - %@", self.episode];
    
    NSString *fileName = [NSString stringWithFormat:@"%@ (%@ %@).ts", baseName, self.channelName, startDateString];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSMoviesDirectory,
                                                         NSUserDomainMask,
                                                         YES);
    NSString *fullPath = [NSString pathWithComponents:@[[paths objectAtIndex:0], fileName]];
    NSLog(@"saving to %@", fullPath);
    
    dispatch_io_t outputChannel = dispatch_io_create_with_path(DISPATCH_IO_STREAM,
                                                          [fullPath cStringUsingEncoding:NSASCIIStringEncoding],
                                                           O_CREAT|O_WRONLY,
                                                           S_IWUSR|S_IRUSR,
                                                           dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
                                                           ^(int error) {
                                                               if (error)
                                                                   NSLog(@"There was a problem opening the recording file. %d (%s)\n",
                                                                         error,
                                                                         strerror(error));
                                                           });
    NSLog(@"opening UDP socket");
    int socketfd = socket(PF_INET, SOCK_DGRAM, 0);
    
    if (socketfd == -1) {
        NSLog(@"a");
        return NO;
    }
 
    NSLog(@"setting UDP socket to non-blocking");
    if (fcntl(socketfd, F_SETFL, O_NONBLOCK) == -1) {
        close(socketfd);
        NSLog(@"b");
        return NO;
    }
    
    struct sockaddr_in sockAddrIn;
    sockAddrIn.sin_family = AF_INET;
    sockAddrIn.sin_port = htons(0);
    sockAddrIn.sin_addr.s_addr = inet_addr([self.device.targetIPAddress cStringUsingEncoding:NSASCIIStringEncoding]);
    memset(sockAddrIn.sin_zero, '\0', sizeof(sockAddrIn.sin_zero));
    
    if (bind(socketfd, (struct sockaddr *)&sockAddrIn, sizeof(sockAddrIn)) != 0) {
        NSLog(@"c");
        return NO;
    }
    
    socklen_t addressLength = sizeof(sockAddrIn);
    if (getsockname(socketfd, (struct sockaddr *)&sockAddrIn, &addressLength) != 0) {
        NSLog(@"d");
        return NO;
    }
    
    self.targetPort = ntohs(sockAddrIn.sin_port);
    NSLog(@"bound UDP socket to %hu", self.targetPort);
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_source_t socketReadSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, socketfd, 0, queue);
    
    self.udpSource = socketReadSource;
    
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
            // NSLog(@"received %lu bytes", receivedByteCount);
            dispatch_data_t data = dispatch_data_create(bytes, receivedByteCount, dispatch_get_global_queue(0, 0), ^{ free(bytes); });
            dispatch_io_write(outputChannel, 0, data, dispatch_get_global_queue(0, 0), ^(bool done, dispatch_data_t data, int error) {  });
        }
    });
    
    dispatch_source_set_cancel_handler(socketReadSource, ^{
        NSLog(@"close UDP socket");
        
        close(socketfd);
        dispatch_io_close(outputChannel, 0);
    });
    
    dispatch_resume(socketReadSource);
    
    [self startStreaming];
    return YES;
}

- (void)startStreaming
{
    NSLog(@"starting stream");
    hdhr_response_block_t responseBlock = ^(HDHRPacket *responsePacket) {
    };
    
    [self.device setValueForName:[NSString stringWithFormat:@"/tuner%hhu/target", self.tunerIndex]
                           value:[NSString stringWithFormat:@"%@:%hu", self.device.targetIPAddress, self.targetPort]
                   responseBlock:responseBlock];
    self.statusIconImage = [NSImage imageNamed:@"statusRed"];

}

- (void)stopRecording:(id)sender
{
    self.statusIconImage = [NSImage imageNamed:@"statusGreen"];
    dispatch_source_cancel(self.udpSource);
    //self.udpSource = nil;
}

@end
