//
//  HBAppDelegate.h
//  HDHomeBase
//
//  Created by Joydip Basu on 4/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class HBScheduler;
@class HBRecordingsController;

@interface HBAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, assign) IBOutlet HBScheduler *scheduler;
@property (nonatomic, assign) IBOutlet HBRecordingsController *recordingsController;

@end
