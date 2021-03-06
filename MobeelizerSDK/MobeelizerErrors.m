// 
// MobeelizerErrors.m
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

#import "MobeelizerErrors+Internal.h"
#import "MobeelizerError.h"

#define GLOBAL_FIELD @""

@interface MobeelizerErrors ()

@property (nonatomic, strong) NSMutableDictionary *errorsMap;

- (NSMutableArray *)getErrorsArrayForField:(NSString *)field;

@end

@implementation MobeelizerErrors

@synthesize errorsMap=_errorsMap;

- (id)init {
    if(self = [super init]) {
        _errorsMap = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSMutableArray *)getErrorsArrayForField:(NSString *)theField {
    NSMutableArray *errors = [self.errorsMap valueForKey:theField];
    
    if(errors == nil) {
        errors = [NSMutableArray array];
        [self.errorsMap setValue:errors forKey:theField];
    }
    
    return errors;
}

- (void)addGlobalError:(MobeelizerError *)theError {
    [[self getErrorsArrayForField:GLOBAL_FIELD] addObject:theError];
}

- (void)addError:(MobeelizerError *)theError forField:(NSString *)theField {
    [[self getErrorsArrayForField:theField] addObject:theError];
}

- (BOOL)isValid {
    return [self.errorsMap count] == 0;
}

- (BOOL)isFieldValid:(NSString *)field {
    return [[self getErrorsArrayForField:field] count] == 0;
}

- (NSArray *)errors {
    return [self getErrorsArrayForField:GLOBAL_FIELD];
}

- (NSArray *)fieldErrors:(NSString *)field {
    return [self getErrorsArrayForField:field];
}

# ifdef DEBUG

- (NSString *)description {
    NSMutableString *string = [NSMutableString string];
    for(NSString *key in self.errorsMap.keyEnumerator) {
        for(MobeelizerError *error in [self.errorsMap objectForKey:key]) {
            if([key isEqualToString:@""]) {
                [string appendFormat:@"[%@ : %@]", key, [error message]];
            } else {
                [string appendString:[error message]];
            }
        }        
    }
    return string;
}

# endif

@end
