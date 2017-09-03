//
//  HBRecording.m
//  HDHomeBase
//
//  Created by Joydip Basu on 11/22/14.
//  Copyright (c) 2014 Joydip Basu. All rights reserved.
//

#import "HBRecording.h"
#import "HBProgram.h"
#import "HBScheduler.h"
#include "hdhomerun.h"


@interface HBRecording ()

@property (readonly) NSString *canonicalChannel;
@property (readonly) NSDate *paddedStartDate;
@property (readonly) NSDate *paddedEndDate;
@property (readwrite) BOOL completed;

@property NSTimer *startTimer;
@property NSTimer *stopTimer;
@property FILE *filePointer;
@property struct hdhomerun_device_t *tunerDevice;
@property BOOL shouldStream;
@property BOOL streamReady;
@property NSUInteger recordingSize;


@end

@implementation HBRecording

+ (instancetype)recordingWithProgram:(HBProgram *)program
                   recordingFilePath:(NSString *)recordingFilePath
                           scheduler:(HBScheduler *)scheduler
{
    return [[self alloc] initWithProgram:program
                       recordingFilePath:recordingFilePath
                               scheduler:scheduler];
}

- (instancetype)initWithProgram:(HBProgram *)program
              recordingFilePath:(NSString *)recordingFilePath
                      scheduler:(HBScheduler *)scheduler
{
    if (self = [super init]) {
        _program = program;
        _recordingFilePath = [recordingFilePath copy];
        _scheduler = scheduler;
    }
    
    return self;
}

- (BOOL)recordingFileExists
{
    return [[NSFileManager defaultManager] fileExistsAtPath:self.recordingFilePath];
}

- (NSString *)canonicalChannel
{
    if ([self.program.mode isEqualToString:@"digital"])
        return [NSString stringWithFormat:@"%hu.%hu", self.program.psipMajor, self.program.psipMinor];
    
    return self.program.rfChannel;
}

- (NSDate *)paddedStartDate
{
    NSTimeInterval beginningPadding = [[NSUserDefaults standardUserDefaults] doubleForKey:@"BeginningPadding"];
    return [self.program.startDate dateByAddingTimeInterval:-beginningPadding];
}

- (NSDate *)paddedEndDate
{
    NSTimeInterval endingPadding = [[NSUserDefaults standardUserDefaults] doubleForKey:@"EndingPadding"];
    return [self.program.endDate dateByAddingTimeInterval:endingPadding];
}

- (BOOL)startDateOverlapsWithRecording:(HBRecording *)otherRecording
{
    NSDate *myStartDate = self.paddedStartDate;
    NSDate *otherEndDate = otherRecording.paddedEndDate;
    return ([myStartDate compare:otherEndDate] != NSOrderedDescending);
}

- (BOOL)hasEndDatePassed
{
    return ([self.program.endDate compare:[NSDate date]] != NSOrderedDescending);
}

- (void)scheduleStartTimer
{
    self.startTimer = [[NSTimer alloc] initWithFireDate:self.paddedStartDate
                                               interval:0
                                                 target:self
                                               selector:@selector(startRecordingTimerFired:)
                                               userInfo:self
                                                repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.startTimer
                              forMode:NSRunLoopCommonModes];
    
    
}

- (void)cancelStartTimer
{
    [self.startTimer invalidate];
    self.startTimer = nil;
}

- (void)scheduleStopTimer
{
    self.stopTimer = [[NSTimer alloc] initWithFireDate:self.paddedEndDate
                                              interval:0
                                                target:self
                                              selector:@selector(stopRecordingTimerFired:)
                                              userInfo:self
                                               repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.stopTimer
                              forMode:NSRunLoopCommonModes];
}

- (void)cancelStopTimer
{
    [self.stopTimer invalidate];
    self.stopTimer = nil;
}

- (void)cancelTimers
{
    [self cancelStartTimer];
    [self cancelStopTimer];
}

- (void)startRecordingTimerFired:(NSTimer *)timer
{
    [self startRecording];
}

- (void)stopRecordingTimerFired:(NSTimer *)timer
{
    [self stop];
}

- (void)scheduleTimers
{
    // only schedule the timers if the file doesn't exist
    if (!self.recordingFileExists) {
        [self scheduleStartTimer];
        [self scheduleStopTimer];
    } else [self markAsCompleted];
}

- (void)markAsCompleted
{
    self.statusIconImage = [NSImage imageNamed:@"clapperboard"];
    self.completed = YES;
    self.status = @"";
}

- (int)discoverDevicesUsingDeviceList:(struct hdhomerun_discover_device_t *)deviceList maxDeviceCount:(UInt8)maxDeviceCount
{
    UInt32 deviceID = (UInt32)[[NSUserDefaults standardUserDefaults] integerForKey:@"DeviceID"];
    self.status = @"searching for devices…";
    int devicesFoundCount = hdhomerun_discover_find_devices_custom_v2(0, // auto-detect IP address
                                                                   HDHOMERUN_DEVICE_TYPE_TUNER,
                                                                   deviceID,
                                                                   deviceList,
                                                                   maxDeviceCount);
    switch (devicesFoundCount) {
        case 0: [self abortWithErrorMessage:@"no devices found"]; break;
        case -1: [self abortWithErrorMessage:@"unable to discover devices"]; break;
    }
    
    return devicesFoundCount;
}

- (void)startRecording
{
    NSLog(@"starting recording at %@", self.recordingFilePath);
    self.statusIconImage = [NSImage imageNamed:@"yellow"];
    self.recordingSize = 0;

    UInt8 maxDeviceCount = 8;
    struct hdhomerun_discover_device_t deviceList[maxDeviceCount];
    int devicesFoundCount = [self discoverDevicesUsingDeviceList:deviceList maxDeviceCount:maxDeviceCount];
    if (devicesFoundCount <= 0) return;
    
    self.status = @"searching for available tuner…";
    
    for (UInt8 deviceIndex = 0; deviceIndex < devicesFoundCount; deviceIndex++) {
        struct hdhomerun_discover_device_t *discoveredDevice = &deviceList[deviceIndex];
        UInt8 tunerCount = discoveredDevice->tuner_count;
        NSLog(@"examining device %X with %hhu tuners", discoveredDevice->device_id, tunerCount);
        
        struct hdhomerun_device_t *device = hdhomerun_device_create(HDHOMERUN_DEVICE_ID_WILDCARD,
                                                                    discoveredDevice->ip_addr,
                                                                    0, // tuner index
                                                                    NULL); // no debug info
        if (device == NULL) continue;
        
        for (UInt8 tunerIndex = 0; tunerIndex < tunerCount; tunerIndex++) {
            NSLog(@"examining tuner %hhu", tunerIndex);
            
            hdhomerun_device_set_tuner(device, tunerIndex);
            char *tunerTargetBuffer;
            int result = hdhomerun_device_get_tuner_target(device, &tunerTargetBuffer);
            
            switch (result) {
                case 0:  NSLog(@"operation rejected"); continue;
                case -1: NSLog(@"communication error"); continue;
                default: break;
            }
            
            NSLog(@"tuner %hhu target is %s", tunerIndex, tunerTargetBuffer);
            
            if (strcmp(tunerTargetBuffer, "none") == 0) {
                NSLog(@"tuner %hhu is available", tunerIndex);
                self.tunerDevice = device;
                [self beginRecording];
                return;
            } else
                NSLog(@"tuner %hhu in use, skipping", tunerIndex);
        }
        
        // no tuners free on this device, so destroy it
        NSLog(@"no tuners available on device, skipping");
        hdhomerun_device_destroy(device);
    }
    
    // no more devices to try, fail the recording
    [self abortWithErrorMessage:@"no tuners available"];
}

- (BOOL)openRecordingFile
{
    FILE *filePointer = fopen([self.recordingFilePath fileSystemRepresentation], "wb");
    if (!filePointer) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"unable to create recording file (code %d: %s)", errno, strerror(errno)]];
        return NO;
    }
    
    self.filePointer = filePointer;
    return YES;
}

- (void)closeRecordingFile
{
    if (self.filePointer) {
        fclose(self.filePointer);
        self.filePointer = NULL;
    }
}

- (BOOL)tuneChannel
{
    int result = 0;
    
    if ([self.program.mode isEqualToString:@"digital"]) {
        NSLog(@"tuning digital broadcast");
        result = hdhomerun_device_set_tuner_channel(self.tunerDevice,
                                           [[@"auto:" stringByAppendingString:self.program.rfChannel]
                                            cStringUsingEncoding:NSASCIIStringEncoding]);
    } else if ([self.program.mode isEqualToString:@"digital_cable"]) {
        NSLog(@"tuning digital cable");
        result = hdhomerun_device_set_tuner_vchannel(self.tunerDevice,
                                            [self.program.rfChannel cStringUsingEncoding:NSASCIIStringEncoding]);
    } else {
        [self abortWithErrorMessage:[@"unknown mode " stringByAppendingString:self.program.mode]];
        return NO;
    }
    
    NSString *errorMessage = nil;
    switch (result) {
        case 0: errorMessage = @"tuning operation rejected"; break;
        case -1: errorMessage = @"tuning communication error"; break;
    }
    
    if (errorMessage) {
        [self abortWithErrorMessage:errorMessage];
        return NO;
    }
    
    return YES;
}

- (void)beginRecording
{
    // XXX set lock here
    if (![self tuneChannel]) return;
    if (![self openRecordingFile]) return;
    
    if (hdhomerun_device_stream_start(self.tunerDevice) <= 0) {
        [self abortWithErrorMessage:@"unable to start stream"];
        return;
    }
    
    self.shouldStream = YES;
    [NSThread detachNewThreadSelector:@selector(receiveStream)
                             toTarget:self
                           withObject:nil];
    
    self.status = @"recording";
    self.statusIconImage = [NSImage imageNamed:@"red"];
    
    [self.scheduler recordingStarted:self];
}

- (void)receiveStream
{
    NSLog(@"receiving stream");
    size_t bufferSize;
    BOOL programIdentified = NO;
    NSString *programNamePrefix = nil;
    NSString *programString = nil;
    self.streamReady = NO;
    
    if ([self.program.mode isEqualToString:@"digital"])
        programNamePrefix = [NSString stringWithFormat:@"%hu.%hu", self.program.psipMajor, self.program.psipMinor];
    
    while (self.shouldStream) {
        uint64_t loopStartTime = getcurrenttime();
        
        uint8_t *videoDataBuffer = hdhomerun_device_stream_recv(self.tunerDevice, VIDEO_DATA_BUFFER_SIZE_1S, &bufferSize);
        if (!videoDataBuffer) {
            msleep_approx(64);
            continue;
        }
        
        if (!programIdentified) {
            char *program;
            hdhomerun_device_get_tuner_program(self.tunerDevice, &program);
            
            programString = @(program);
            
            if (![programString isEqualToString:@"none"])
                programIdentified = YES;
        }
        
        if (!self.streamReady) {
            [self checkIfStreamIsReady:programString programNamePrefix:programNamePrefix];
            continue;
        }
        
        if (self.streamReady) {
            self.recordingSize += bufferSize;
            if (fwrite(videoDataBuffer, 1, bufferSize, self.filePointer) != bufferSize) {
                fprintf(stderr, "error writing output\n");
                break;
            }
        }
        
        int32_t delay = 64 - (int32_t)(getcurrenttime() - loopStartTime);
        if (delay <= 0) continue;
        msleep_approx(delay);
    }
    
    [self.scheduler performSelectorOnMainThread:@selector(recordingCompleted:) withObject:self waitUntilDone:NO];
    NSLog(@"receiving stream thread terminated");
}

- (void)checkIfStreamIsReady:(NSString *)programString programNamePrefix:(NSString *)programNamePrefix
{
    char *streamInfo;
    hdhomerun_device_get_tuner_streaminfo(self.tunerDevice, &streamInfo);
    
    NSString *streamInfoString = @(streamInfo);
    NSArray *streams = [streamInfoString componentsSeparatedByString:@"\n"];
    
    for (NSString *stream in streams) {
        // for digital cable (CableCARD), look for a stream that matches the program number, and wait until it is unencrypted
        if ([self.program.mode isEqualToString:@"digital_cable"]) {
            if ([stream hasPrefix:programString])
                if (![stream hasSuffix:@")"]) {
                    NSLog(@"unecrypted stream found!");
                    self.streamReady = YES;
                }
            
            if (self.streamReady) break;
        }
        
        // in digital (ATSC broadcast), we match the whole program name and then set a filter
        else if ([self.program.mode isEqualToString:@"digital"]) {
            NSArray *streamFields = [stream componentsSeparatedByString:@": "];
            if (streamFields.count < 2) continue;
            
            NSString *streamProgramNumberString = streamFields[0];
            NSString *streamName = streamFields[1];
            NSLog(@"program: %@ name: %@", streamProgramNumberString, streamName);
            
            if ([streamName hasPrefix:programNamePrefix] && (![stream hasSuffix:@"(no data)"])) {
                NSLog(@"matched desired program name %@", streamName);
                hdhomerun_device_set_tuner_program(self.tunerDevice, [streamProgramNumberString cStringUsingEncoding:NSASCIIStringEncoding]);
                self.streamReady = YES;
                break;
            }
        }
    }
}

- (void)stop
{
    self.shouldStream = NO;
    if (self.tunerDevice) hdhomerun_device_stream_stop(self.tunerDevice);
    
    if (self.recordingSize == 0) {
        [self abortWithErrorMessage:@"no video data received during recording"];
        [[NSFileManager defaultManager] removeItemAtURL:[NSURL fileURLWithPath:self.recordingFilePath]
                                                                         error:NULL];
        return;
    }
    
    [self markAsCompleted];
    [self cleanupRecordingResources];
}

- (void)cleanupRecordingResources
{
    [self cancelTimers];
    [self closeRecordingFile];
    
    if (self.tunerDevice) {
        hdhomerun_device_destroy(self.tunerDevice);
        self.tunerDevice = NULL;
    }
}

- (void)abortWithErrorMessage:(NSString *)errorMessage
{
    NSLog(@"aborting recording %@: %@", self.recordingFilePath, errorMessage);
    self.status = errorMessage;
    self.statusIconImage = [NSImage imageNamed:@"prohibited"];
    self.completed = YES;
    
    [self cleanupRecordingResources];
}

- (BOOL)currentlyRecording
{
    return self.shouldStream;
}

@end
