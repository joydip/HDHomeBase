//
//  HBRecordingsController.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/1/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBRecordingsController.h"
#import "HBRecording.h"
#import "HBAppDelegate.h"
#import "HBScheduler.h"

@interface HBRecordingsController ()

@end

@implementation HBRecordingsController

- (void)awakeFromNib
{
    HBScheduler *scheduler = ((HBAppDelegate *)[NSApp delegate]).scheduler;
    self.scheduledRecordings = scheduler.scheduledRecordings;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.scheduledRecordings.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    return [self.scheduledRecordings objectAtIndex:row];
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    [self.scheduledRecordings sortUsingDescriptors:[tableView sortDescriptors]];
    [tableView reloadData];
}

- (IBAction)refresh:(id)sender
{
    [self.tableView reloadData];
}

- (IBAction)deleteSchedule:(id)sender
{
    NSLog(@"delete!");
}

- (IBAction)adjustPadding:(id)sender
{
    NSLog(@"adjust padding!");
}

- (BOOL)validateToolbarItem:(id)sender
{
    return NO;
}

@end
