// 
// MobeelizerDefinitionManager.h
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

#import <Foundation/Foundation.h>

@class Mobeelizer;

@interface MobeelizerDefinitionManager : NSObject<NSXMLParserDelegate>

@property (nonatomic, strong) NSString *vendor;
@property (nonatomic, strong) NSString *application;
@property (nonatomic, strong) NSString *conflictMode;
@property (nonatomic, strong) NSString *versionDigest;
@property (nonatomic, strong) NSMutableArray *groups;
@property (nonatomic, strong) NSMutableArray *devices;
@property (nonatomic, strong) NSMutableArray *roles;
@property (nonatomic, strong) NSMutableArray *models;

- (id)initWithAsset:(NSString *)definitionAsset andModelPrefix:(NSString *)modelPrefix;
- (NSArray *)modelsForRole:(NSString *)role;

@end
