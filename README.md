# <img src="/tools/res/logo.png" height="45" width="60">&nbsp;SwiftWebSocket

[![API Docs](https://img.shields.io/badge/api-docs-blue.svg?style=flat-square)](http://tidwall.com/SwiftWebSocket/docs/)
[![Swift/4.0](https://img.shields.io/badge/swift-4.0-brightgreen.svg?style=flat-square)](https://developer.apple.com/swift/)
[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg?style=flat-square)](http://tidwall.com/SwiftWebSocket/results/)

Conforming WebSocket ([RFC 6455](https://tools.ietf.org/html/rfc6455)) client library for iOS and Mac OSX.

SwiftWebSocket passes all 521 of the Autobahn's fuzzing tests, including strict UTF-8, and message compression.

## Features

- High performance.
- 100% conforms to [Autobahn Tests](http://autobahn.ws/testsuite/#test-suite-coverage). Including base, limits, compression, etc. [Test results](https://tidwall.github.io/SwiftWebSocket/results/).
- TLS / WSS support. Self-signed certificate option.
- The API is modeled after the [Javascript API](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket).
- Reads compressed messages (`permessage-deflate`). [RFC 7692](https://tools.ietf.org/html/rfc7692)
- Send pings and receive pong events.
- Strict UTF-8 processing. 
- `binaryType` property to choose between `[UInt8]` or `NSData` messages.
- Zero asserts. All networking, stream, and protocol errors are routed through the `error` event.
- iOS / Objective-C support.

## Example

```swift
func echoTest(){
    var messageNum = 0
    let ws = WebSocket("wss://echo.websocket.org")
    let send : ()->() = {
        messageNum += 1
        let msg = "\(messageNum): \(NSDate().description)"
        print("send: \(msg)")
        ws.send(msg)
    }
    ws.event.open = {
        print("opened")
        send()
    }
    ws.event.close = { code, reason, clean in
        print("close")
    }
    ws.event.error = { error in
        print("error \(error)")
    }
    ws.event.message = { message in
        if let text = message as? String {
            print("recv: \(text)")
            if messageNum == 10 {
                ws.close()
            } else {
                send()
            }
        }
    }
}
```

## Custom Headers
```swift
var request = URLRequest(url: URL(string:"ws://url")!)
request.addValue("AUTH_TOKEN", forHTTPHeaderField: "Authorization")
request.addValue("Value", forHTTPHeaderField: "X-Another-Header")
let ws = WebSocket(request: request)
```

## Reuse and Delaying WebSocket Connections
v2.3.0+ makes available an optional `open` method. This will allow for a `WebSocket` object to be instantiated without an immediate connection to the server. It can also be used to reconnect to a server following the `close` event.

For example,

```swift
let ws = WebSocket()
ws.event.close = { _,_,_ in
    ws.open()                 // reopen the socket to the previous url
    ws.open("ws://otherurl")  // or, reopen the socket to a new url
}
ws.open("ws://url") // call with url
```

## Compression

The `compression` flag may be used to request compressed messages from the server. If the server does not support or accept the request, then connection will continue as normal, but with uncompressed messages.

```swift
let ws = WebSocket("ws://url")
ws.compression.on = true
```

## Self-signed SSL Certificate

```swift
let ws = WebSocket("ws://url")
ws.allowSelfSignedSSL = true
```

## Network Services (VoIP, Video, Background, Voice)

```swift
// Allow socket to handle VoIP in the background.
ws.services = [.VoIP, .Background] 
```
## Installation (iOS and OS X)

### [Carthage]

[Carthage]: https://github.com/Carthage/Carthage

Add the following to your Cartfile:

```
github "tidwall/SwiftWebSocket"
```

Then run `carthage update`.

Follow the current instructions in [Carthage's README][carthage-installation]
for up to date installation instructions.

[carthage-installation]: https://github.com/Carthage/Carthage#adding-frameworks-to-an-application

The `import SwiftWebSocket` directive is required in order to access SwiftWebSocket features.

### [CocoaPods]

[CocoaPods]: http://cocoapods.org

Add the following to your [Podfile](http://guides.cocoapods.org/using/the-podfile.html):

```ruby
use_frameworks!
pod 'SwiftWebSocket'
```

Then run `pod install` with CocoaPods 0.36 or newer.

The `import SwiftWebSocket` directive is required in order to access SwiftWebSocket features.

### Manually

Copy the `SwiftWebSocket/WebSocket.swift` file into your project.  
You must also add the `libz.dylib` library. `Project -> Target -> Build Phases -> Link Binary With Libraries`

There is no need for `import SwiftWebSocket` when manually installing.



## Contact
Josh Baker [@tidwall](http://twitter.com/tidwall)

## License

SwiftWebSocket source code is available under the MIT License.
