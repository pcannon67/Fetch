//
//  NodeObject.h
//  Fetch
//
//  Created by Josh on 9/15/13.
//  Copyright (c) 2013 Jukaela Enterprises. All rights reserved.
//

@import Foundation;

@interface NodeObject : NSObject

/// Title of the node
@property (strong, nonatomic) NSString *nodeTitle;

/// Value of the node
@property (strong, nonatomic) NSString *nodeValue;

/// Children of the node
@property (strong, nonatomic) NSArray *children;

/// Is the node a leaf?
@property (nonatomic) BOOL isLeaf;

/// Is the node part of an array of nodes?
@property (nonatomic) BOOL isArray;

/// If the node has children, what is the object count?
@property (nonatomic) NSInteger objectCount;

@end
