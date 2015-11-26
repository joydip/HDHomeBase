//
//  main.m
//  recordings_organizer
//
//  Created by Joydip Basu on 10/10/15.
//  Copyright (c) 2015 Joydip Basu. All rights reserved.
//

#import <Foundation/Foundation.h>

// find duplicate recordings
// merge folders

NSString *basenameForRecordingFile(NSString *filename) {
    NSRange subtitleMarkerRange = [filename rangeOfString:@" - "];
    
    if (subtitleMarkerRange.location == NSNotFound) {
        NSRange suffixRange = [filename rangeOfString:@" ("];
        if (suffixRange.location == NSNotFound) return nil;
        return [filename substringToIndex:suffixRange.location];
    }
    
    return [filename substringToIndex:subtitleMarkerRange.location];
}

BOOL createFolder(NSString *path) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSLog(@"creating folder '%@'", path);

    if ([fileManager fileExistsAtPath:path]) {
        NSLog(@"file/folder '%@' already exists, skipping", path);
        return NO;
    }
    
    NSError *createDirectoryError;
    BOOL success = [fileManager createDirectoryAtPath:path
                          withIntermediateDirectories:NO
                                           attributes:nil
                                                error:&createDirectoryError];
    if (!success) NSLog(@"%@", createDirectoryError);
    return success;
}

BOOL moveFileIntoFolder(NSString *filename, NSString *sourcePath, NSString *destPath) {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *fullSourcePath = [sourcePath stringByAppendingPathComponent:filename];
    NSString *fullDestPath = [destPath stringByAppendingPathComponent:filename];
    NSLog(@"moving '%@' into '%@'", fullSourcePath, fullDestPath);

    NSError *error;
    if (![fileManager moveItemAtPath:fullSourcePath toPath:fullDestPath error:&error]) {
        NSLog(@"%@", error);
        return NO;
    }
    
    return YES;
}

void organizeRecordingsInFolder(NSString *path) {
    NSLog(@"organizing recording in folder '%@'", path);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSError *error;
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:path error:&error];
    NSArray *sortedContents = [contents sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
    NSString *previousEntry;
    NSString *previousBasename;
    
    for (NSString *entry in sortedContents) {
        if (![entry hasSuffix:@".ts"]) continue;
        
        NSString *basename = basenameForRecordingFile(entry);
        if (!basename) {
            // NSLog(@"unable to get basename for file %@, skipping", entry);
            continue;
        }
        
        NSString *groupFolderPath = [path stringByAppendingPathComponent:basename];
        BOOL isDirectory;
        if ([fileManager fileExistsAtPath:groupFolderPath isDirectory:&isDirectory]) {
            if (isDirectory) {
                NSLog(@"folder '%@' exists, moving '%@' into it", groupFolderPath, entry);
                moveFileIntoFolder(entry, path, groupFolderPath);
                goto END;
            }

            NSLog(@"'%@' exists but is not a directory", groupFolderPath);
            goto END;
        }

        if ([basename isEqualToString:previousBasename]) {
            NSLog(@"files '%@' and '%@' found, will create new group folder '%@'", previousEntry, entry, groupFolderPath);
            createFolder(groupFolderPath);
            moveFileIntoFolder(previousEntry, path, groupFolderPath);
            moveFileIntoFolder(entry, path, groupFolderPath);
        }

    END:
        previousEntry = entry;
        previousBasename = basename;
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray *arguments = [[NSProcessInfo processInfo] arguments];
        NSString *path = [arguments objectAtIndex:1];        
        organizeRecordingsInFolder(path);
    }
    return 0;
}
