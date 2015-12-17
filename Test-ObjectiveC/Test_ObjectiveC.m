//
//  Test_ObjectiveC.m
//  Test-ObjectiveC
//
//  Created by Ricardo Pereira on 17/12/15.
//  Copyright © 2015 ONcast, LLC. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "Connection.h"

@interface Test_ObjectiveC : XCTestCase

@end

@implementation Test_ObjectiveC

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testObjectiveC {
    [[[Connection alloc] init] open];
}

@end
