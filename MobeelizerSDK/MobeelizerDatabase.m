// 
// MobeelizerDatabase.m
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

#import "MobeelizerDatabase+Internal.h"
#import "MobeelizerErrors.h"
#import "MobeelizerError.h"
#import "MobeelizerCriteriaBuilder+Internal.h"
#import "MobeelizerModelDefinition+Query.h"
#import "MobeelizerModelDefinition+Validate.h"
#import "MobeelizerSqlite3Database.h"
#import "MobeelizerInternalDatabase.h"
#import "MobeelizerDefinitionManager.h"
#import "Mobeelizer+Internal.h"
#import "MobeelizerFieldDefinition.h"

#define SQL_DATABASE_NAME @"%@_%@_data"
#define SQL_UPDATE_MODIFIED @"UPDATE %@ SET _modified = %d WHERE _modified = %d"
#define SQL_DELETE_DELETED_AFTER_SYNC @"DELETE FROM %@ WHERE _modified = 2 AND _deleted = 1 AND _conflicted = 0"
#define SQL_DELETE_FROM_SYNC @"DELETE FROM %@ WHERE _guid = ?"
#define SQL_CLEAR_TABLE @"DELETE FROM %@"
#define SQL_SYNC_SELECT_TABLE @"SELECT * FROM %@ WHERE _modified = 2"

@interface MobeelizerDatabase ()

@property (nonatomic, strong) MobeelizerSqlite3Database *database;
@property (nonatomic, weak) Mobeelizer *mobeelizer;
@property (nonatomic, strong) NSMutableDictionary *modelsByName;
@property (nonatomic, strong) NSMutableDictionary *modelsByClazz;

- (MobeelizerModelDefinition *)modelForClass:(Class)clazz;

@end

@implementation MobeelizerDatabase

@synthesize database=_database, modelsByName=_modelsByName, modelsByClazz=_modelsByClazz, mobeelizer=_mobeelizer;

- (id)initWithMobeelizer:(Mobeelizer *)mobeelizer {
    if (self = [super init]) {   
        if(self.database != nil) {
            [self destroy];
        }
        
        _mobeelizer = mobeelizer;
                
        _database = [[MobeelizerSqlite3Database alloc] initWithName:[NSString stringWithFormat:SQL_DATABASE_NAME, self.mobeelizer.instanceGuid, self.mobeelizer.user]];
        
        BOOL initializationRequired = [self.mobeelizer.internalDatabase checkIfInitializationIsRequiredForInstance:self.mobeelizer.instance andInstanceGuid:self.mobeelizer.instanceGuid andUser:self.mobeelizer.user];
        
        _modelsByName = [NSMutableDictionary dictionary];
        _modelsByClazz = [NSMutableDictionary dictionary];
        
        NSArray *modelsArray = [self.mobeelizer.definitionManager modelsForRole:mobeelizer.role];
        
        if(initializationRequired) {
            [self.database execQuery:@"DROP TABLE IF EXISTS _files"];
            [self.database execQuery:@"CREATE TABLE _files (_guid TEXT(36) PRIMARY KEY, _path TEXT NOT NULL, _modified INTEGER(1) NOT NULL DEFAULT 0)"];
        }
        
        for(MobeelizerModelDefinition *model in modelsArray) {
            [self.modelsByName setValue:model forKey:model.name];
            [self.modelsByClazz setValue:model forKey:NSStringFromClass(model.clazz)];                
            
            if(initializationRequired) {
                [self.database execQuery:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", model.name]];
                [self.database execQuery:[model queryForCreate]];
            }
        }   
        
        if(initializationRequired) {
            [self.mobeelizer.internalDatabase setInitializationFinishedForInstance:self.mobeelizer.instance andInstanceGuid:self.mobeelizer.instanceGuid andUser:self.mobeelizer.user];
        }
        
        [self unlockModifiedFlag];
    }
    
    return self;
}

- (void)destroy {
    if(self.database != nil) {
        [self.database destroy];
        self.database = nil;
    }   
}

- (MobeelizerModelDefinition *)modelForClass:(Class)clazz {
    MobeelizerModelDefinition *model = [self.modelsByClazz valueForKey:NSStringFromClass(clazz)];
    
    if(model == nil) {
        MobeelizerException(@"Model not found", @"Cannot find model for class: %@", NSStringFromClass(clazz));
    }
    
    return model;
}

- (MobeelizerModelDefinition *)model:(NSString *)name {
    return [self.modelsByName valueForKey:name];
}

- (void)removeAll:(Class)clazz {
    [self.database execQuery:[[self modelForClass:clazz] queryForDeleteAll]];
}

- (void)remove:(Class)clazz withGuid:(NSString *)guid {
    [self.database execQuery:[[self modelForClass:clazz] queryForDelete] withParams:[NSArray arrayWithObject:guid]];
}

- (void)remove:(id)object {
    MobeelizerModelDefinition *model = [self modelForClass:[object class]];
    
    [self.database execQuery:[[self modelForClass:model.clazz] queryForDelete] withParams:[NSArray arrayWithObject:[object valueForKey:@"guid"]]];
    
    [model setAsDeleted:object];
}

- (BOOL)exists:(Class)clazz withGuid:(NSString *)guid {    
    MobeelizerModelDefinition *model = [self modelForClass:clazz];
    
    NSNumber *count = [self execQuery:[model queryForExists] withParams:[NSArray arrayWithObject:guid] withModel:model withSelector:@selector(execQueryForSingleResult:withParams:)];    

    return [count intValue] > 0;
}

- (NSUInteger)count:(Class)clazz {
    MobeelizerModelDefinition *model = [self modelForClass:clazz];
    
    NSNumber *count = [self execQuery:[model queryForCount] withParams:[NSArray array] withModel:model withSelector:@selector(execQueryForSingleResult:withParams:)];    

    return [count intValue];
}

- (MobeelizerErrors *)save:(id)object {    
    MobeelizerModelDefinition *model = [self modelForClass:[object class]];
        
    MobeelizerErrors *errors = [model validate:object];

    NSString *guid = [object valueForKey:@"guid"];
    
    BOOL exists = (guid != nil) && [self exists:[object class] withGuid:guid]; 
    
    if(![errors isValid]) {
        return errors;
    }
    
    if(!exists) {
        NSArray *params = [model paramsForInsert:object forGuid:nil forOwner:self.mobeelizer.user withModified:TRUE withDeleted:FALSE withConflicted:FALSE];
        [self.database execQuery:[model queryForInsert] withParams:params];
    } else {
        NSArray *params = [model paramsForSimpleUpdate:object];
        [self.database execQuery:[model queryForSimpleUpdate] withParams:params]; 
    }
    
    return errors;
}


- (id)get:(Class)clazz withGuid:(NSString *)guid {
    MobeelizerModelDefinition *model = [self modelForClass:clazz];
    
    return [self execQuery:[model queryForGet] withParams:[NSArray arrayWithObject:guid] withModel:model withSelector:@selector(execQueryForRow:withParams:)];
}

- (NSArray *)list:(Class)clazz {
    MobeelizerModelDefinition *model = [self modelForClass:clazz];
    
    return [self execQuery:[model queryForList] withParams:[NSArray array] withModel:model withSelector:@selector(execQueryForList:withParams:)];
}

- (MobeelizerCriteriaBuilder *)find:(Class)clazz {
    return [[MobeelizerCriteriaBuilder alloc] initWithDatabase:self andModel:[self modelForClass:clazz]];
}

- (void)lockModifiedFlag {
    for(NSString *modelName in [self.modelsByName keyEnumerator]) {
        [self.database execQuery:[NSString stringWithFormat:SQL_UPDATE_MODIFIED, modelName, 2, 1]];
    }

    [self.database execQuery:[NSString stringWithFormat:SQL_UPDATE_MODIFIED, @"_files", 2, 1]];
}

- (void)clearModifiedFlag {
    for(NSString *modelName in [self.modelsByName keyEnumerator]) {        
        [self.database execQuery:[NSString stringWithFormat:SQL_DELETE_DELETED_AFTER_SYNC, modelName] withParams:[NSArray array]];
        [self.database execQuery:[NSString stringWithFormat:SQL_UPDATE_MODIFIED, modelName, 0, 2]];
    }
    
    [self.database execQuery:[NSString stringWithFormat:SQL_UPDATE_MODIFIED, @"_files", 0, 2]];
}

- (void)unlockModifiedFlag {
    for(NSString *modelName in [self.modelsByName keyEnumerator]) {
        [self.database execQuery:[NSString stringWithFormat:SQL_UPDATE_MODIFIED, modelName, 1, 2]];
    }    
}

- (BOOL)updateEntitiesFromSync:(NSData *)data withAll:(BOOL)all {    
    MobeelizerSqlite3Database *localDatabase = [[MobeelizerSqlite3Database alloc] initWithName:[NSString stringWithFormat:SQL_DATABASE_NAME, self.mobeelizer.instanceGuid, self.mobeelizer.user]];
    
    BOOL isTransactionSuccessful = TRUE;
    
    @try {    
        NSArray *lines = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];

        [localDatabase beginTransaction];
        
        if (all) {
            for(NSString *modelName in [self.modelsByName keyEnumerator]) {
                [localDatabase execQuery:[NSString stringWithFormat:SQL_CLEAR_TABLE, modelName]];
            }
        }
        
        for(NSString *line in lines) {
            if([line length] == 0) {
                continue;
            }
            
            NSError* error = nil;
            
            NSDictionary* json = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions error:&error];
            
            if(error != nil) {
                MobeelizerLog(@"JSON parser has failed: %@ for data: [%@]", [error localizedDescription], line);
                isTransactionSuccessful = FALSE;
                break;
            }
            
            MobeelizerModelDefinition *model = [self.modelsByName valueForKey:[json valueForKey:@"model"]];
 
            BOOL deleted = [[[json valueForKey:@"fields"] valueForKey:@"s_deleted"] isEqualToString:@"true"];    
            BOOL conflicted = [[json valueForKey:@"conflictState"] hasPrefix:@"IN_CONFLICT"];
            
            if(deleted && !conflicted) {
                if([self exists:[model clazz] withGuid:[json valueForKey:@"guid"]]) {
                    [localDatabase execQuery:[NSString stringWithFormat:SQL_DELETE_FROM_SYNC, model.name] withParams:[NSArray arrayWithObject:[json valueForKey:@"guid"]]];        
                }
                continue;
            }
            
            id object = [model convertJsonToObject:json];
            
            if(object == nil) {
                isTransactionSuccessful = FALSE;
                break;
            }
            
            MobeelizerErrors *errors = [[MobeelizerErrors alloc] init]; // @TODO [model validate:object] - relation must exists problem;
         
            if(![errors isValid]) {
                isTransactionSuccessful = FALSE;
                break;
            }
            
            if([json valueForKey:@"fields"] == nil) {
                NSArray *params = [model paramsForUpdateWithoutFields:object withModified:FALSE withDeleted:deleted withConflicted:conflicted];        
                [localDatabase execQuery:[model queryForUpdateWithoutFields] withParams:params];                
            } else if(![self exists:[object class] withGuid:[json valueForKey:@"guid"]]) {
                NSArray *params = [model paramsForInsert:object forGuid:[json valueForKey:@"guid"] forOwner:[json valueForKey:@"owner"] withModified:FALSE withDeleted:deleted withConflicted:conflicted];        
                [localDatabase execQuery:[model queryForInsert] withParams:params];        
            } else {
                NSArray *params = [model paramsForUpdate:object withModified:FALSE withDeleted:deleted withConflicted:conflicted];        
                [localDatabase execQuery:[model queryForUpdate] withParams:params];        
            }        
        }
        
        if (isTransactionSuccessful) {
            [localDatabase commitTransaction];
        } else {
            [localDatabase rollbackTransaction];
        }
    } @finally {        
        [localDatabase destroy];
    }

    return isTransactionSuccessful;
}

- (NSData *)getEntitiesToSync {
    NSMutableData *data = [NSMutableData data];
    
    for(NSString *modelName in [self.modelsByName keyEnumerator]) {
        MobeelizerModelDefinition *model = [self.modelsByName objectForKey:modelName];
        
        NSArray *rows = [self.database execQueryForList:[NSString stringWithFormat:SQL_SYNC_SELECT_TABLE, modelName] withParams:[NSArray array]];
        
        for(NSDictionary *row in rows) {
            [data appendData:[[[model convertMapToJson:row] stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    
    return data;
}

- (id)execQuery:(NSString *)query withParams:(NSArray *)params withModel:(MobeelizerModelDefinition *)model withSelector:(SEL)selector {
    id results =  [self.database performSelector:selector withObject:query withObject:params];
    
    if(results == nil) {
        return nil;
    } else if([results isKindOfClass:[NSArray class]]) {
        NSMutableArray *array = [NSMutableArray array];
        
        for(NSDictionary *row in results) {
            [array addObject:[model convertMapToObject:row]];
        }
        
        return array;
    } else if([results isKindOfClass:[NSDictionary class]]) {
        return [model convertMapToObject:results];
    } else {
        return results;
    }
}

- (void)addFile:(NSString *)guid andPath:(NSString *)path {
    [self.database execQuery:@"INSERT INTO _files (_guid, _path, _modified) VALUES (?, ?, 1)" withParams:[NSArray arrayWithObjects:guid, path, nil]];
}

- (void)addFileFromSync:(NSString *)guid withPath:(NSString *)path {
    [self.database execQuery:@"INSERT INTO _files (_guid, _path, _modified) VALUES (?, ?, 0)" withParams:[NSArray arrayWithObjects:guid, path, nil]];
}

- (NSString *)getFilePath:(NSString *)guid {
    return [self.database execQueryForSingleResult:@"SELECT _path FROM _files WHERE _guid = ?" withParams:[NSArray arrayWithObject:guid]];
}

- (void)deleteFileFromSync:(NSString *)guid {
    [self.database execQuery:@"DELETE FROM _files WHERE _guid = ?" withParams:[NSArray arrayWithObject:guid]];
}

- (BOOL)isFileExists:(NSString *)guid {
    NSNumber *count = [self.database execQueryForSingleResult:@"SELECT count(*) FROM _files WHERE _guid = ?" withParams:[NSArray arrayWithObject:guid]];

    return [count intValue] > 0;
}

- (NSArray *)getFilesToSync {
    NSArray *rows = [self.database execQueryForList:@"SELECT _guid FROM _files WHERE _modified = 2" withParams:[NSArray array]];
    
    NSMutableArray *guids = [NSMutableArray array];
    
    for(NSDictionary *row in rows) {
        [guids addObject:[row objectForKey:@"_guid"]];
    }
    
    return guids;
}

@end
