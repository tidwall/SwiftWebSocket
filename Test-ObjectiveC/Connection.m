//
//  Connection.m
//  SwiftWebSocket
//
//  Created by Ricardo Pereira on 17/12/15.
//  Copyright © 2015 ONcast, LLC. All rights reserved.
//

#import "Connection.h"
#import <SwiftWebSocket/SwiftWebSocket-Swift.h>

@interface Connection () <WebSocketDelegate>

@end

@implementation Connection {
    WebSocket *_webSocket;
}

- (instancetype)init {
    if (self = [super init]) {
        _webSocket = nil;
    }
    return self;
}

- (void)open {
    _webSocket = [[WebSocket alloc] init:@"ws://localhost:9000"];
    _webSocket.delegate = self;
    [_webSocket open];
    NSAssert(_webSocket.readyState == WebSocketReadyStateConnecting, @"WebSocket is not connecting");
}

- (void)webSocketOpen {
    NSLog(@"Open");
    [_webSocket sendWithText:@"test"];
    [_webSocket sendWithData:[@"test" dataUsingEncoding:NSUTF8StringEncoding]];
    NSAssert(_webSocket.readyState == WebSocketReadyStateOpen, @"WebSocket is not ready to communicate");
    [_webSocket close:0 reason:@""];
}

- (void)webSocketClose:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean {
    NSLog(@"Close: %@", reason);
}

- (void)webSocketMessageText:(NSString *)text {
    NSLog(@"Message: %@", text);
}

- (void)webSocketMessageData:(NSData *)data {
    NSLog(@"Message: %@", data);
}

- (void)webSocketPong {
    NSLog(@"Pong");
}

- (void)webSocketError:(NSError *)error {
    NSLog(@"Error: %@", error);
}

- (void)webSocketEnd:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean error:(NSError *)error {
    NSLog(@"End: %@", error);
}

@end
