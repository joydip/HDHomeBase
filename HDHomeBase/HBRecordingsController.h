//
//  HBRecordingsController.h
//  HDHomeBase
//
//  Created by Joydip Basu on 6/1/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface HBRecordingsController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong) NSMutableArray *scheduledRecordings;
@property (nonatomic, assign) IBOutlet NSTableView *tableView;

- (IBAction)refresh:(id)sender;
- (IBAction)deleteSchedule:(id)sender;
- (IBAction)adjustPadding:(id)sender;

@end
