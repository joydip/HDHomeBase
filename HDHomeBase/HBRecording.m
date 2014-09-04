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

#import "HDHRTunerReservation.h"
#import "HDHRDeviceManager.h"
#import <IOKit/pwr_mgt/IOPMLib.h>


@interface HBRecording ()

@property (strong) HDHRTunerReservation *tunerReservation;

@property (assign) UInt16 targetPort;
@property (nonatomic, strong) dispatch_source_t udpSource;

@end


@implementation HBRecording

- (id)init
{
    if ((self = [super init])) {
        _statusIconImage = [NSImage imageNamed:@"history"];
    }
    
    return self;
}

- (void)updateStatusOnMainThread:(NSString *)string
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.status = string;
    });
}

- (void)startRecording:(id)sender
{
    self.statusIconImage = [NSImage imageNamed:@"statusYellow"];
    
    [self updateStatusOnMainThread:@"searching for available tuner…"];

    [self.deviceManager requestTunerReservation:^(HDHRTunerReservation *tunerReservation, dispatch_semaphore_t sema) {
        self.tunerReservation = tunerReservation;
    
        [self updateStatusOnMainThread:[NSString stringWithFormat:@"tuning to channel %@…", self.rfChannel]];
        [tunerReservation tuneToChannel:self.rfChannel tuningCompletedBlock:^{
            [self updateStatusOnMainThread:@"starting stream…"];
            [self startSavingUDPStream];
            [tunerReservation startStreamingToIPAddress:tunerReservation.targetIPAddress port:self.targetPort];
            dispatch_semaphore_signal(sema);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateStatusOnMainThread:@"recording"];
                self.statusIconImage = [NSImage imageNamed:@"statusRed"];
                self.currentlyRecording = YES;
            });
        }];
    }];
}

- (BOOL)startSavingUDPStream
{
    NSLog(@"saving UDP stream to %@", self.recordingPath);

    [[NSFileManager defaultManager] createFileAtPath:self.recordingPath contents:nil attributes:nil];
    NSFileHandle *recordingFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.recordingPath];
    
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
    sockAddrIn.sin_addr.s_addr = inet_addr([self.tunerReservation.targetIPAddress cStringUsingEncoding:NSASCIIStringEncoding]);
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
            [recordingFileHandle writeData:[NSData dataWithBytesNoCopy:bytes length:receivedByteCount]];
        }
    });
    
    dispatch_source_set_cancel_handler(socketReadSource, ^{
        NSLog(@"close UDP socket");
        close(socketfd);
    });
    
    IOPMAssertionID assertionID;
    IOReturn success = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep,
                                                   kIOPMAssertionLevelOn,
                                                   (__bridge CFStringRef)self.recordingPath,
                                                   &assertionID);
    
    if (success != kIOReturnSuccess)
        NSLog(@"unable to create power assertion");

    dispatch_resume(socketReadSource);
    
    success = IOPMAssertionRelease(assertionID);

    return YES;
}

- (void)stopRecording:(id)sender
{
    self.statusIconImage = [NSImage imageNamed:@"statusGreen"];
    [self updateStatusOnMainThread:@"finished"];

    if (self.udpSource)
        dispatch_source_cancel(self.udpSource);
    self.udpSource = nil;
    self.currentlyRecording = NO;
}

/*
 else {
 NSLog(@"no devices available");
 self.statusIconImage = [NSImage imageNamed:@"alert"];
 }
*/

@end
