// 
// MobeelizerSyncManager.m
// 
// Copyright (C) 2012 Mobeelizer Ltd. All Rights Reserved.
//
// Mobeelizer SDK is free software; you can redistribute it and/or modify it 
// under the terms of the GNU Affero General Public License as published by 
// the Free Software Foundation; either version 3 of the License, or (at your
// option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or 
// FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
// for more details.
//
// You should have received a copy of the GNU Affero General Public License 
// along with this program; if not, write to the Free Software Foundation, Inc., 
// 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
// 

#import <UIKit/UIKit.h>
#import "MobeelizerSyncManager.h"
#import "Mobeelizer+Internal.h"
#import "MobeelizerDatabase+Internal.h"
#import "MobeelizerDataFileManager.h"

@interface MobeelizerSyncManager ()

@property (nonatomic, weak) Mobeelizer *mobeelizer;
@property (nonatomic, strong) MobeelizerDataFileManager *dataFileManager;
@property (nonatomic, strong) NSMutableArray *listeners;

- (void)updateSyncStatus:(MobeelizerSyncStatus)syncStatus;
- (BOOL)startSyncProcess;
- (BOOL)isRunning;

@end

@implementation MobeelizerSyncManager

@synthesize mobeelizer=_mobeelizer, syncStatus=_syncStatus, listeners=_listeners, dataFileManager=_dataFileManager;

- (id)initWithMobeelizer:(Mobeelizer *)mobeelizer {
    if(self = [super init]) {
        _mobeelizer = mobeelizer;
        _syncStatus = MobeelizerSyncStatusNone;
        _listeners = [NSMutableArray array];
        _dataFileManager = [[MobeelizerDataFileManager alloc] initWithMobeelizer:mobeelizer];
    }
    return self;
}

- (MobeelizerSyncStatus)sync:(BOOL)all {
    if(![self startSyncProcess]) {
        return MobeelizerSyncStatusNone;
    }
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSString *inputDataPath = nil;
    NSString *outputDataPath = nil;
    
    @try {                
        [self.mobeelizer.database lockModifiedFlag];
        
        NSString *ticket = nil;
        
        if (all) {
            MobeelizerLog(@"Send sync all request.");
            
            ticket = [self.mobeelizer.connectionManager requestSyncAll];
        } else {            
            outputDataPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"output%d.dat", (rand() % 74)]];
            
            BOOL prepareOutputFileSuccess = [self.dataFileManager prepareOutputFile:outputDataPath];

            if (!prepareOutputFileSuccess) {
                MobeelizerLog(@"Send file haven't been created.");
                return MobeelizerSyncStatusFinishedWithFailure;
            }
            
            [self updateSyncStatus:MobeelizerSyncStatusFileCreated];
            
            MobeelizerLog(@"Send sync diff request.");
            
            ticket = [self.mobeelizer.connectionManager requestSyncDiff:outputDataPath];
        }
 
        MobeelizerLog(@"Sync request completed: %@", ticket);
        
        [self updateSyncStatus:MobeelizerSyncStatusTaskCreated];
        
        BOOL syncRequestCompleteSuccess = [self.mobeelizer.connectionManager waitUntilSyncRequestComplete:ticket];
        
        if (!syncRequestCompleteSuccess) {
            return MobeelizerSyncStatusFinishedWithFailure;
        }
        
        MobeelizerLog(@"Sync process complete with success.");
    
        [self updateSyncStatus:MobeelizerSyncStatusTaskPerformed];

        inputDataPath = [self.mobeelizer.connectionManager getSyncData:ticket];
        
        [self updateSyncStatus:MobeelizerSyncStatusFileReceived];
    
        BOOL processInputFileSuccess = [self.dataFileManager processInputFile:inputDataPath andSyncAll:all];

        if (!processInputFileSuccess) {
            return MobeelizerSyncStatusFinishedWithFailure;
        }
            
        [self.mobeelizer.connectionManager confirmTask:ticket];

        [self.mobeelizer.database clearModifiedFlag];

        [self.mobeelizer.internalDatabase setInitialSyncAsNotRequiredForInstance:self.mobeelizer.instance andUser:self.mobeelizer.user];
    
        [self updateSyncStatus:MobeelizerSyncStatusFinishedWithSuccess];

        return MobeelizerSyncStatusFinishedWithSuccess;
    } @catch (NSException *exception) {
        @throw exception;
    } @finally {        
        NSError *error;
        
        if(inputDataPath != nil && [fileManager removeItemAtPath:inputDataPath error:&error] != YES) {
            MobeelizerLog(@"Unable to delete file: %@ - %@", inputDataPath, [error localizedDescription]);
        }
        
        if(outputDataPath != nil && [fileManager removeItemAtPath:outputDataPath error:&error] != YES) {
            MobeelizerLog(@"Unable to delete file: %@ - %@", outputDataPath, [error localizedDescription]);
        }
        
        [self.mobeelizer.database unlockModifiedFlag];
        
        if ([self isRunning]) {
            MobeelizerLog(@"Sync process complete with failure.");
            [self updateSyncStatus:MobeelizerSyncStatusFinishedWithFailure];
        }
    }    
}

- (void)registerSyncStatusListener:(id<MobeelizerSyncListener>)listener {
    [self.listeners addObject:listener];
}

- (BOOL)isRunning {
    return self.syncStatus != MobeelizerSyncStatusNone && self.syncStatus != MobeelizerSyncStatusFinishedWithSuccess && self.syncStatus != MobeelizerSyncStatusFinishedWithFailure; 
}

-(BOOL)startSyncProcess {
    @synchronized(self) {
        if([self isRunning]) {
            return FALSE;
        }
        
        [self updateSyncStatus:MobeelizerSyncStatusStarted];
        
        return TRUE;
    }
}

- (void)updateSyncStatus:(MobeelizerSyncStatus)syncStatus {
    if(self.mobeelizer.multitaskingSupported) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.syncStatus = syncStatus;
            
            for(id<MobeelizerSyncListener> listener in self.listeners) {
                [listener syncStatusHasBeenChangedTo:syncStatus];
            }
        });
    } else {
        self.syncStatus = syncStatus;
        
        for(id<MobeelizerSyncListener> listener in self.listeners) {
            [listener syncStatusHasBeenChangedTo:syncStatus];
        }
    }
}

@end
