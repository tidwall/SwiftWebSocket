#<img src="https://tidwall.github.com/SwiftWebSocket/logo.png" height="45" width="60">&nbsp;SwiftWebSocket

<a href="https://tidwall.github.io/SwiftWebSocket/results/"><img src="https://tidwall.github.io/SwiftWebSocket/build.png" alt="" width="93" height="20" border="0" /></a>
<a href="https://developer.apple.com/swift/"><img src="https://tidwall.github.io/SwiftWebSocket/swift2.png" alt="" width="65" height="20" border="0" /></a>


Conforming WebSocket ([RFC 6455](https://tools.ietf.org/html/rfc6455)) client library implemented in pure Swift.

[Test results for SwiftWebSocket](https://tidwall.github.io/SwiftWebSocket/results/). You can compare to the popular [Objective-C Library](http://square.github.io/SocketRocket/results/)

SwiftWebSocket currently passes all 521 of the Autobahn's fuzzing tests, including strict UTF-8, and message compression.

**Built for Swift 2.0** - For Swift 1.2 support use the 'swift/1.2' branch.

## Features

- Swift 2.0. No need for Objective-C Bridging.
- Reads compressed messages (`permessage-deflate`). [IETF Draft](https://tools.ietf.org/html/draft-ietf-hybi-permessage-compression-21)
- Strict UTF-8 processing. 
- The API is modeled after the [Javascript API](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket).
- TLS / WSS support.
- `binaryType` property to choose between `[UInt8]` or `NSData` messages.
- Zero asserts. All networking, stream, and protocol errors are routed through the `error` event.
- Send pings and receive pong events.
- High performance. 

##Example

```swift
func echoTest(){
    var messageNum = 0
    let ws = WebSocket("wss://echo.websocket.org")
    let send : ()->() = {
        let msg = "\(++messageNum): \(NSDate().description)"
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

##Installation (iOS and OS X)

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

###Manually

Copy the `SwiftWebSocket\WebSocket.swift` file into your project.  
You must also add the `libz.dylib` library. `Project -> Target -> Build Phases -> Link Binary With Libraries`

There is no need for `import SwiftWebSocket` when manually installing.

## Contact
Josh Baker [@tidwall](http://twitter.com/tidwall)

## License

The SwiftWebSocket source code is available under the MIT License.
