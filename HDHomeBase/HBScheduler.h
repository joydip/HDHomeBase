//
//  HBScheduler.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/16/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "HDHRDevice.h"
#import "HDHRDeviceManager.h"

@interface HBScheduler : NSObject

@property (nonatomic, strong) IBOutlet HDHRDeviceManager *deviceManager;
@property (nonatomic, strong) NSMutableArray *scheduledRecordings;

- (void)importTVPIFile:(NSString *)filename;

@end
