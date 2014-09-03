//
//  HBAppDelegate.h
//  HDHomeBase
//
//  Created by Joydip Basu on 4/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class HDHRDeviceManager;
@class HBScheduler;
@class HBRecordingsController;

@interface HBAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) IBOutlet HDHRDeviceManager *deviceManager;
@property (nonatomic, strong) IBOutlet HBScheduler *scheduler;
@property (nonatomic, strong) IBOutlet HBRecordingsController *recordingsController;


@end
