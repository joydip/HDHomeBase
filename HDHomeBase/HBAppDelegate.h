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

@property (strong) IBOutlet NSWindow *mainWindow;
@property (strong) IBOutlet NSWindow *deviceDiscoverySheet;
@property (strong) IBOutlet NSProgressIndicator *deviceDiscoveryIndicator;

@property (strong) IBOutlet HDHRDeviceManager *deviceManager;
@property (strong) IBOutlet HBScheduler *scheduler;
@property (strong) IBOutlet HBRecordingsController *recordingsController;

@end
