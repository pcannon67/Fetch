//
//  DataHandler.h
//  Fetch
//
//  Created by Josh on 9/8/13.
//  Copyright (c) 2013 Jukaela Enterprises. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Projects;

@interface ProjectHandler : NSObject

+(BOOL)importFromPath:(NSString *)path;
+(BOOL)importFromData:(NSData *)data;
+(NSDictionary *)exportProject:(Projects *)project toUrl:(NSURL *)url;

@end
