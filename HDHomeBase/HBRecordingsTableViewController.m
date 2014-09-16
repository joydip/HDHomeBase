//
//  HBRecordingsTableViewController.m
//  HDHomeBase
//
//  Created by Joydip Basu on 6/1/13.
//  Copyright (c) 2013 Joydip Basu. All rights reserved.
//

#import "HBRecordingsTableViewController.h"
#import "HBRecording.h"
#import "HBAppDelegate.h"
#import "HBScheduler.h"

@implementation HBRecordingsTableViewController

- (void)awakeFromNib
{
    self.recordings = self.scheduler.scheduledRecordings;
    [self.tableView setTarget:self];
    [self.tableView setDoubleAction:@selector(doubleClickAction:)];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.recordings.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    return (self.recordings)[row];
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    [self.recordings sortUsingDescriptors:[tableView sortDescriptors]];
    [tableView reloadData];
}

- (IBAction)refresh:(id)sender
{
    [self.recordings sortUsingDescriptors:self.tableView.sortDescriptors];
    [self.tableView reloadData];
}

- (IBAction)playRecordingAction:(id)sender
{
    NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
    NSArray *selectedRecordings = [self.recordings objectsAtIndexes:selectedRowsIndexSet];
    [self.scheduler playRecording:selectedRecordings[0]];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    NSInteger selectedRowIndex = [self.tableView selectedRow];
    HBRecording *selectedRecording = (selectedRowIndex != -1) ? self.recordings[selectedRowIndex] : nil;
    
    for (NSUInteger rowIndex = 0; rowIndex < self.recordings.count; rowIndex++) {
        NSTableRowView *rowView = [self.tableView rowViewAtRow:rowIndex makeIfNecessary:NO];

        if (selectedRecording.tooManyOverlappingRecordings) {
            if ([selectedRecording.overlappingRecordings containsObject:self.recordings[rowIndex]])
                rowView.backgroundColor = [NSColor colorWithDeviceRed:1.0f green:0.0f blue:0.0f alpha:0.25f];
        }
        
        else {
            rowView.backgroundColor = (rowIndex % 2) ?
            [NSColor controlAlternatingRowBackgroundColors][1] :
            [NSColor controlAlternatingRowBackgroundColors][0];
        }
    }
}

- (void)doubleClickAction:(id)sender
{
    if (self.tableView.numberOfSelectedRows > 0) [self playRecordingAction:self];
}

- (IBAction)deleteRecordingAction:(id)sender
{
    NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
    NSArray *selectedRecordings = [self.recordings objectsAtIndexes:selectedRowsIndexSet];
    for (HBRecording *recording in selectedRecordings) [self.scheduler deleteRecording:recording];
    [self.tableView reloadData];
}

- (IBAction)stopRecordingAction:(id)sender
{
    NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
    NSArray *selectedRecordings = [self.recordings objectsAtIndexes:selectedRowsIndexSet];
    for (HBRecording *recording in selectedRecordings) [self.scheduler stopRecording:recording];
}

- (IBAction)showFileAction:(id)sender
{
    NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
    NSArray *selectedRecordings = [self.recordings objectsAtIndexes:selectedRowsIndexSet];
    HBRecording *selectedRecording = selectedRecordings[0];
    [[NSWorkspace sharedWorkspace] selectFile:selectedRecording.recordingFilePath
                     inFileViewerRootedAtPath:@""];
}

- (BOOL)validateToolbarItem:(id)sender
{
    if (self.tableView.numberOfSelectedRows == 0) return NO;

    if ((sender == self.playRecordingToolbarItem) ||
        (sender == self.showFileToolbarItem))
        return [self.recordings[self.tableView.selectedRow] recordingFileExists];
    
    if (sender == self.stopRecordingToolbarItem) {
        __block BOOL currentlyRecording = NO;
        
        NSIndexSet *selectedRowsIndexSet = self.tableView.selectedRowIndexes;
        [self.recordings enumerateObjectsAtIndexes:selectedRowsIndexSet
                                           options:0
                                        usingBlock:^(id object, NSUInteger index, BOOL *stop) {
                                            HBRecording *recording = (HBRecording *)object;
                                            if (recording.currentlyRecording) {
                                                currentlyRecording = YES;
                                                *stop = YES;
                                            }
                                        }];
        return currentlyRecording;
    }
    
    return YES;
}

@end
