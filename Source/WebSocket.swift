/*
* SwiftWebSocket (websocket.swift)
*
* Copyright (C) 2015 ONcast, LLC. All Rights Reserved.
* Created by Josh Baker (joshbaker77@gmail.com)
*
* This software may be modified and distributed under the terms
* of the MIT license.  See the LICENSE file for details.
*
*/

import Foundation

private enum ErrCode : Int, CustomStringConvertible {
    case Protocol = 1002, Payload = 1007, Undefined = -100, Codepoint = -101, Library = -102, Socket = -103
    var description : String {
        switch self {
        case Protocol: return "Protocol error"
        case Payload: return "Invalid payload data"
        case Codepoint: return "Invalid codepoint"
        case Library: return "Library error"
        case Undefined: return "Undefined error"
        case Socket: return "Broken socket"
        }
    }
}

private func makeError(error : String, _ code: ErrCode) -> ErrorType {
    return NSError(domain: "com.github.tidwall.WebSocketConn", code: code.rawValue, userInfo: [NSLocalizedDescriptionKey:"\(error)"])
}
private func makeError(error : ErrorType, _ code: ErrCode) -> ErrorType {
    let err = error as NSError
    return NSError(domain: err.domain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey:"\(err.localizedDescription)"])
}
private func makeError(error : String) -> ErrorType {
    return makeError(error, ErrCode.Library)
}

private let oneHundredYears : NSTimeInterval = 60*60*24*365*100

private let errUTF8 = makeError("utf8")
private let errTimeout = makeError("timeout")
private let errClosed = makeError("closed")
private let errStream = makeError("stream error")
private let errEOF = makeError("eof")
private let errAddress = makeError("invalid address")
private let errNegative = makeError("length cannot be negative")

private class BoxedBytes {
    var ptr : UnsafeMutablePointer<UInt8>
    var cap : Int
    var len : Int
    init(){
        len = 0
        cap = 1024 * 16
        ptr = UnsafeMutablePointer<UInt8>(malloc(cap))
    }
    deinit{
        free(ptr)
    }
    var count : Int {
        get {
            return len
        }
        set {
            if newValue > cap {
                while cap < newValue {
                    cap *= 2
                }
                ptr = UnsafeMutablePointer<UInt8>(realloc(ptr, cap))
            }
            len = newValue
        }
    }
    func append(bytes: UnsafePointer<UInt8>, length: Int){
        let prevLen = len
        count = len+length
        memcpy(ptr+prevLen, bytes, length)
    }
    var array : [UInt8] {
        get {
            var array = [UInt8](count: count, repeatedValue: 0)
            memcpy(&array, ptr, count)
            return array
        }
        set {
            count = 0
            append(newValue, length: newValue.count)
        }
    }
    var nsdata : NSData {
        get {
            return NSData(bytes: ptr, length: count)
        }
        set {
            count = 0
            append(UnsafePointer<UInt8>(newValue.bytes), length: newValue.length)
        }
    }
    var buffer : UnsafeBufferPointer<UInt8> {
        get {
            return UnsafeBufferPointer<UInt8>(start: ptr, count: count)
        }
        set {
            count = 0
            append(newValue.baseAddress, length: newValue.count)
        }
    }
}

private enum OpCode : UInt8, CustomStringConvertible {
    case Continue = 0x0, Text = 0x1, Binary = 0x2, Close = 0x8, Ping = 0x9, Pong = 0xA
    var isControl : Bool {
        switch self {
        case .Close, .Ping, .Pong:
            return true
        default:
            return false
        }
    }
    var description : String {
        switch self {
        case Continue: return "Continue"
        case Text: return "Text"
        case Binary: return "Binary"
        case Close: return "Close"
        case Ping: return "Ping"
        case Pong: return "Pong"
        }
    }
}


/// The WebSocketEvents struct is used by the events property and manages the events for the WebSocket connection.
public struct WebSocketEvents {
    /// An event to be called when the WebSocket connection's readyState changes to .Open; this indicates that the connection is ready to send and receive data.
    public var open : ()->() = {}
    /// An event to be called when the WebSocket connection's readyState changes to .Closed.
    public var close : (code : Int, reason : String, wasClean : Bool)->() = {(code, reason, wasClean) in}
    /// An event to be called when an error occurs.
    public var error : (error : ErrorType)->() = {(error) in}
    /// An event to be called when a message is received from the server.
    public var message : (data : Any)->() = {(data) in}
    /// An event to be called when a pong is received from the server.
    public var pong : (data : Any)->() = {(data) in}
    /// An event to be called when the WebSocket process has ended; this event is guarenteed to be called once and can be used as an alternative to the "close" or "error" events.
    public var end : (code : Int, reason : String, wasClean : Bool, error : ErrorType?)->() = {(code, reason, wasClean, error) in}
}

/// The WebSocketBinaryType enum is used by the binaryType property and indicates the type of binary data being transmitted by the WebSocket connection.
public enum WebSocketBinaryType : CustomStringConvertible {
    /// The WebSocket should transmit [UInt8] objects.
    case UInt8Array
    /// The WebSocket should transmit NSData objects.
    case NSData
    /// The WebSocket should transmit UnsafeBufferPointer<UInt8> objects. This buffer is only valid during the scope of the message event. Use at your own risk.
    case UInt8UnsafeBufferPointer
    public var description : String {
        switch self {
        case UInt8Array: return "UInt8Array"
        case NSData: return "NSData"
        case UInt8UnsafeBufferPointer: return "UInt8UnsafeBufferPointer"
        }
    }
}

/// The WebSocketReadyState enum is used by the readyState property to describe the status of the WebSocket connection.
public enum WebSocketReadyState : Int, CustomStringConvertible {
    /// The connection is not yet open.
    case Connecting = 0
    /// The connection is open and ready to communicate.
    case Open = 1
    /// The connection is in the process of closing.
    case Closing = 2
    /// The connection is closed or couldn't be opened.
    case Closed = 3
    private var isClosed : Bool {
        switch self {
        case .Closing, .Closed:
            return true
        default:
            return false
        }
    }
    /// Returns a string that represents the ReadyState value.
    public var description : String {
        switch self {
        case Connecting: return "Connecting"
        case Open: return "Open"
        case Closing: return "Closing"
        case Closed: return "Closed"
        }
    }
}

private let defaultMaxWindowBits = 15
/// The WebSocketCompression struct is used by the compression property and manages the compression options for the WebSocket connection.
public struct WebSocketCompression {
    /// Used to accept compressed messages from the server. Default is true.
    public var on = false
    /// request no context takeover.
    public var noContextTakeover = false
    /// request max window bits.
    public var maxWindowBits = defaultMaxWindowBits
}


/// The WebSocketService options are used by the services property and manages the underlying socket services.
public struct WebSocketService :  OptionSetType {
    public typealias RawValue = UInt
    var value: UInt = 0
    init(_ value: UInt) { self.value = value }
    public init(rawValue value: UInt) { self.value = value }
    public init(nilLiteral: ()) { self.value = 0 }
    public static var allZeros: WebSocketService { return self.init(0) }
    static func fromMask(raw: UInt) -> WebSocketService { return self.init(raw) }
    public var rawValue: UInt { return self.value }
    
    /// No services.
    static var None: WebSocketService { return self.init(TCPConnService.None.rawValue) }
    /// Allow socket to handle VoIP.
    static var VoIP: WebSocketService { return self.init(TCPConnService.VoIP.rawValue) }
    /// Allow socket to handle video.
    static var Video: WebSocketService { return self.init(TCPConnService.Video.rawValue) }
    /// Allow socket to run in background.
    static var Background: WebSocketService { return self.init(TCPConnService.Background.rawValue) }
    /// Allow socket to handle voice.
    static var Voice: WebSocketService { return self.init(TCPConnService.Voice.rawValue) }
}

public class WebSocket {
    private var mutex = pthread_mutex_t()
    private var cond = pthread_cond_t()
    private let request : NSURLRequest!
    private let subProtocols : [String]!
    private var frames : [Frame] = []
    private var ccode : Int = 0
    private var creason : String = ""
    private var cclose : Bool = false
    
    private var _subProtocol = ""
    private var _compression = WebSocketCompression()
    private var _services = WebSocketService.None
    private var _event = WebSocketEvents()
    private var _binaryType = WebSocketBinaryType.UInt8Array
    private var _readyState = WebSocketReadyState.Connecting
    private var _networkTimeout = NSTimeInterval(-1)
    
    /// The URL as resolved by the constructor. This is always an absolute URL. Read only.
    public var url : String {
        return request.URL!.description
    }
    /// A string indicating the name of the sub-protocol the server selected; this will be one of the strings specified in the protocols parameter when creating the WebSocket object.
    public var subProtocol : String {
        get { return privateSubProtocol }
    }
    private var privateSubProtocol : String {
        get { lock(); defer { unlock() }; return _subProtocol }
        set { lock(); defer { unlock() }; _subProtocol = newValue }
    }
    /// The compression options of the WebSocket.
    public var compression : WebSocketCompression {
        get { lock(); defer { unlock() }; return _compression }
        set { lock(); defer { unlock() }; _compression = newValue }
    }
    /// The services of the WebSocket.
    public var services : WebSocketService {
        get { lock(); defer { unlock() }; return _services }
        set { lock(); defer { unlock() }; _services = newValue }
    }
    /// The events of the WebSocket.
    public var event : WebSocketEvents {
        get { lock(); defer { unlock() }; return _event }
        set { lock(); defer { unlock() }; _event = newValue }
    }
    /// A WebSocketBinaryType value indicating the type of binary data being transmitted by the connection. Default is .UInt8Array.
    public var binaryType : WebSocketBinaryType {
        get { lock(); defer { unlock() }; return _binaryType }
        set { lock(); defer { unlock() }; _binaryType = newValue }
    }
    /// The current state of the connection; this is one of the WebSocketReadyState constants. Read only.
    public var readyState : WebSocketReadyState {
        get { return privateReadyState }
    }
    private var privateReadyState : WebSocketReadyState {
        get { lock(); defer { unlock() }; return _readyState }
        set { lock(); defer { unlock() }; _readyState = newValue }
    }

    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    public convenience init(_ url: String){
        self.init(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: [])
    }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a list of protocols.
    public convenience init(_ url: String, subProtocols : [String]){
        self.init(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: subProtocols)
    }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a protocol.
    public convenience init(_ url: String, subProtocol : String){
        self.init(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: [subProtocol])
    }
    /// Create a WebSocket connection from an NSURLRequest; Also include a list of protocols.
    public init(request: NSURLRequest, subProtocols : [String] = []){
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&cond, nil)
        self.request = request
        self.subProtocols = subProtocols
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue()){
            dispatch_async(dispatch_queue_create(nil, nil)) {
                self.main()
            }
        }
    }
    deinit{
        pthread_cond_init(&cond, nil)
        pthread_mutex_init(&mutex, nil)
    }
    @inline(__always) private func lock(){
        pthread_mutex_lock(&mutex)
    }
    @inline(__always) private func unlock(){
        pthread_mutex_unlock(&mutex)
    }
    @inline(__always) private func signal(){
        pthread_cond_broadcast(&cond)
    }
    private func wait(timeout : NSTimeInterval) -> WaitResult {
        let timeInMs = Int(timeout * 1000)
        var tv = timeval()
        var ts = timespec()
        gettimeofday(&tv, nil)
        ts.tv_sec = time(nil) + timeInMs / 1000
        ts.tv_nsec = Int(tv.tv_usec * 1000 + 1000 * 1000 * (timeInMs % 1000))
        ts.tv_sec += ts.tv_nsec / (1000 * 1000 * 1000)
        ts.tv_nsec %= (1000 * 1000 * 1000)
        if (pthread_cond_timedwait(&cond, &mutex, &ts) == 0) {
            return .Signaled
        } else {
            return .TimedOut
        }
    }
    private enum InternalEvent {
        case Opened, Closed, Error, Text, Binary, End, Pong
    }
    private func fireEvent(event : InternalEvent, frame : Frame? = nil, error : ErrorType? = nil, code : Int = 0, reason : String = "", wasClean : Bool = false){
        lock()
        let binaryType = _binaryType
        let events = _event
        unlock()
        dispatch_sync(dispatch_get_main_queue()) {
            switch event {
            case .Opened:
                events.open()
            case .Closed:
                events.close(code: code, reason: reason, wasClean: wasClean)
            case .End:
                events.end(code: code, reason: reason, wasClean: wasClean, error: error)
            case .Error:
                events.error(error: error!)
            case .Text:
                events.message(data: frame!.utf8.text)
            case .Binary, .Pong:
                if event == .Binary {
                    switch binaryType{
                    case .UInt8Array: events.message(data: frame!.payload.array)
                    case .NSData: events.message(data: frame!.payload.nsdata)
                    case .UInt8UnsafeBufferPointer: events.message(data: frame!.payload.buffer)
                    }
                } else {
                    switch binaryType{
                    case .UInt8Array: events.pong(data: frame!.payload.array)
                    case .NSData: events.pong(data: frame!.payload.nsdata)
                    case .UInt8UnsafeBufferPointer: events.pong(data: frame!.payload.buffer)
                    }
                }
            }
        }
    }
    private func main(){
        var finalError : ErrorType?
        var finalErrorIsClosed = false
        var (closeCode, closeReason, closeClean) = (0, "", false)
        defer {
            if finalErrorIsClosed {
                finalError = nil
            }
            lock()
            let (_closeCode, _closeReason, _closeClean) = (closeCode, closeReason, closeClean)
            unlock()
            fireEvent(.End, error: finalError, code: _closeCode, reason: _closeReason, wasClean: _closeClean)
            lock()
            signal()
            unlock()
        }
        var wso : WebSocketConn?
        defer {
            if let ws = wso {
                lock()
                let cclose = self.cclose
                if !cclose {
                    var err : NSError?
                    if finalError != nil {
                        err = finalError as? NSError
                    }
                    let pva : ErrCode = .Protocol
                    if err != nil && err!.code == pva.rawValue  {
                        (closeCode, closeReason) = (1002, "Protocol error")
                    } else if err != nil && err!.code == ErrCode.Payload.rawValue {
                        (closeCode, closeReason) = (1007, "Invalid frame payload data")
                    } else {
                        if closeClean == false {
                            (closeCode, closeReason) = (1006, "Abnormal Closure")
                        }
                    }
                }
                let (_closeCode, _closeReason, _closeClean) = (closeCode, closeReason, closeClean)
                unlock()
                ws.close(_closeCode, reason: _closeReason)
                privateReadyState = WebSocketReadyState.Closed
                fireEvent(.Closed, code: _closeCode, reason: _closeReason, wasClean: _closeClean)
            }
        }
        do {
            let ws = try WebSocketConn(self.request, services: TCPConnService(self.services.rawValue), protocols: self.subProtocols, compression: self.compression)
            wso = ws
            privateSubProtocol = ws.subProtocol
            privateReadyState = .Open
            fireEvent(.Opened)
            var pongFrames : [Frame] = []
            dispatch_async(dispatch_queue_create(nil, nil)) {
                var cclose = false
                defer {
                    if cclose {
                        self.lock()
                        (closeCode, closeReason, closeClean) = (self.ccode, self.creason, true)
                        let (_closeCode, _closeReason) = (closeCode, closeReason)
                        self.unlock()
                        ws.close(_closeCode, reason: _closeReason)
                    } else {
                        ws.close()
                    }
                }
                do {
                    for ;; {
                        var wsopened = true
                        var frame : Frame?
                        self.lock()
                        for ;; {
                            if !ws.opened {
                                wsopened = false
                                break
                            }
                            if self.cclose {
                                cclose = true
                                break
                            }
                            if pongFrames.count > 0 {
                                frame = pongFrames.removeAtIndex(0)
                                break
                            }
                            if self.frames.count > 0 {
                                frame = self.frames.removeAtIndex(0)
                                break
                            }
                            self.wait(0.25)
                        }
                        self.unlock()
                        if cclose || !wsopened {
                            break
                        }
                        if frame != nil{
                            do {
                                ws.writeDeadline = NSDate().dateByAddingTimeInterval(1)
                                try ws.writeFrame(frame!)
                            } catch {
                                let error = error as NSError
                                if error.code != -102 || error.localizedDescription != "timeout" {
                                    throw error
                                }
                            }
                            frame = nil
                        }
                    }
                } catch {
                    // error left behind ?
                }
            }
            defer {
                privateReadyState = .Closing
            }
            for ;; {
                ws.readDeadline = NSDate().dateByAddingTimeInterval(oneHundredYears)
                let f = try ws.readFrame()
                switch f.code {
                case .Close:
                    lock()
                    (closeCode, closeReason, closeClean) = (Int(f.statusCode), f.utf8.text, true)
                    unlock()
                    return
                case .Ping:
                    f.code = .Pong
                    lock()
                    pongFrames += [f]
                    signal()
                    unlock()
                case .Pong:
                    fireEvent(.Pong, frame: f)
                case .Text:
                    fireEvent(.Text, frame: f)
                case .Binary:
                    fireEvent(.Binary, frame: f)
                default:
                    break
                }
            }
        } catch {
            let nserror = error as NSError
            if nserror.code == 1002 {
                NSThread.sleepForTimeInterval(0.05)
            }
            if nserror.localizedDescription != "eof" {
                finalError = error
                finalErrorIsClosed = nserror.localizedDescription == "closed"
                if !finalErrorIsClosed {
                    fireEvent(.Error, error: error)
                }
            }
        }
    }
    /**
    Closes the WebSocket connection or connection attempt, if any. If the connection is already closed or in the state of closing, this method does nothing.
    
    :param: code An integer indicating the status code explaining why the connection is being closed. If this parameter is not specified, a default value of 1000 (indicating a normal closure) is assumed.
    :param: reason A human-readable string explaining why the connection is closing. This string must be no longer than 123 bytes of UTF-8 text (not characters).
    */
    public func close(code : Int = 1000, reason : String = "Normal Closure") {
        lock()
        defer { unlock() }
        if _readyState.isClosed {
            return
        }
        _readyState = .Closing
        (ccode, creason, cclose) = (code, reason, true)
        signal()
    }
    private func sendFrame(f : Frame) {
        lock()
        defer { unlock() }
        if _readyState.isClosed {
            return
        }
        frames += [f]
        signal()
    }
    private func sendClose(statusCode : UInt16, reason : String) {
        let f = Frame()
        f.code = .Close
        f.statusCode = statusCode
        f.utf8.text = reason
        sendFrame(f)
    }
    /**
    Transmits message to the server over the WebSocket connection.
    
    :param: message The data to be sent to the server.
    */
    public func send(message : Any) {
        let f = Frame()
        if let message = message as? String {
            f.code = .Text
            f.utf8.text = message
        } else if let message = message as? [UInt8] {
            f.code = .Binary
            f.payload.array = message
        } else if let message = message as? UnsafeBufferPointer<UInt8> {
            f.code = .Binary
            f.payload.append(message.baseAddress, length: message.count)
        } else if let message = message as? NSData {
            f.code = .Binary
            f.payload.nsdata = message
        } else {
            f.code = .Text
            f.utf8.text = "\(message)"
        }
        sendFrame(f)
    }
    /**
    Transmits a ping to the server over the WebSocket connection.
    */
    public func ping() {
        let f = Frame()
        f.code = .Ping
        sendFrame(f)
    }
    /**
    Transmits a ping to the server over the WebSocket connection.
    
    :param: optional message The data to be sent to the server.
    */
    public func ping(message : Any){
        let f = Frame()
        f.code = .Ping
        if let message = message as? String {
            f.payload.array = UTF8.bytes(message)
        } else if let message = message as? [UInt8] {
            f.payload.array = message
        } else if let message = message as? UnsafeBufferPointer<UInt8> {
            f.payload.append(message.baseAddress, length: message.count)
        } else if let message = message as? NSData {
            f.payload.nsdata = message
        } else {
            f.utf8.text = "\(message)"
        }
        sendFrame(f)
    }
}

private class Delegate : NSObject, NSStreamDelegate {
    var c : TCPConn!
    @objc func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent){
        c.signal()
    }
}

private enum TCPConnSecurity {
    case None
    case NegoticatedSSL
}

private struct TCPConnService : OptionSetType {
    typealias RawValue = UInt
    var value: UInt = 0
    init(_ value: UInt) { self.value = value }
    init(rawValue value: UInt) { self.value = value }
    init(nilLiteral: ()) { self.value = 0 }
    static var allZeros: TCPConnService { return self.init(0) }
    static func fromMask(raw: UInt) -> TCPConnService { return self.init(raw) }
    var rawValue: UInt { return self.value }
    static var None: TCPConnService { return self.init(0) }
    static var VoIP: TCPConnService { return self.init(1 << 0) }
    static var Video: TCPConnService { return self.init(1 << 1) }
    static var Background: TCPConnService { return self.init (1 << 2) }
    static var Voice: TCPConnService { return self.init(1 << 3) }
}

private enum WaitResult {
    case Signaled
    case TimedOut
}


private class TCPConn {
    var mutex = pthread_mutex_t()
    var cond = pthread_cond_t()
    var rd : NSInputStream!
    var wr : NSOutputStream!
    var closed = false
    var delegate : Delegate
    deinit {
        pthread_cond_destroy(&cond)
        pthread_mutex_destroy(&mutex)
    }
    init(_ address : String, security : TCPConnSecurity = .None, services : TCPConnService = .None) throws {
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&cond, nil)
        delegate = Delegate()
        delegate.c = self
        let addr = address.componentsSeparatedByString(":")
        if addr.count != 2 || Int(addr[1]) == nil {
            throw errAddress
        }
        var (rdo, wro) : (NSInputStream?, NSOutputStream?)
        NSStream.getStreamsToHostWithName(addr[0], port: Int(addr[1])!, inputStream: &rdo, outputStream: &wro)
        (rd, wr) = (rdo!, wro!)
        let securityLevel : String
        switch security {
        case .None:
            securityLevel = NSStreamSocketSecurityLevelNone
        case .NegoticatedSSL:
            securityLevel = NSStreamSocketSecurityLevelNegotiatedSSL
        }
        rd.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)
        wr.setProperty(securityLevel, forKey: NSStreamSocketSecurityLevelKey)
        if services.contains(.VoIP) {
            rd.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
            wr.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
        }
        if services.contains(.Video) {
            rd.setProperty(NSStreamNetworkServiceTypeVideo, forKey: NSStreamNetworkServiceType)
            wr.setProperty(NSStreamNetworkServiceTypeVideo, forKey: NSStreamNetworkServiceType)
        }
        if services.contains(.Background) {
            rd.setProperty(NSStreamNetworkServiceTypeBackground, forKey: NSStreamNetworkServiceType)
            wr.setProperty(NSStreamNetworkServiceTypeBackground, forKey: NSStreamNetworkServiceType)
        }
        if services.contains(.Voice) {
            rd.setProperty(NSStreamNetworkServiceTypeVoice, forKey: NSStreamNetworkServiceType)
            wr.setProperty(NSStreamNetworkServiceTypeVoice, forKey: NSStreamNetworkServiceType)
        }
        rd.delegate = delegate
        wr.delegate = delegate
        rd.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        wr.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        rd.open()
        wr.open()
        var rwerror : NSError?
        pthread_mutex_lock(&mutex)
        for ;; {
            rwerror = rd.streamError
            if rwerror == nil {
                rwerror = wr.streamError
            }
            if rd.streamStatus == .Open && wr.streamStatus == .Open || rwerror != nil {
                break
            }
            wait(0.25)
        }
        pthread_mutex_unlock(&mutex)
        if rwerror != nil {
            throw rwerror!
        }
    }
    var _writeDeadline : NSDate = NSDate().dateByAddingTimeInterval(oneHundredYears)
    var writeDeadline : NSDate {
        get {
            pthread_mutex_lock(&mutex)
            let deadline = _writeDeadline
            pthread_mutex_unlock(&mutex)
            return deadline
        }
        set {
            pthread_mutex_lock(&mutex)
            _writeDeadline = newValue
            pthread_mutex_unlock(&mutex)
        }
    }
    var _readDeadline : NSDate = NSDate().dateByAddingTimeInterval(oneHundredYears)
    var readDeadline : NSDate {
        get {
            pthread_mutex_lock(&mutex)
            let deadline = _readDeadline
            pthread_mutex_unlock(&mutex)
            return deadline
        }
        set {
            pthread_mutex_lock(&mutex)
            _readDeadline = newValue
            pthread_mutex_unlock(&mutex)
        }
    }
    func wait(timeout : NSTimeInterval) -> WaitResult {
        let timeInMs = Int(timeout * 1000)
        var tv = timeval()
        var ts = timespec()
        gettimeofday(&tv, nil)
        ts.tv_sec = time(nil) + timeInMs / 1000
        ts.tv_nsec = Int(tv.tv_usec * 1000 + 1000 * 1000 * (timeInMs % 1000))
        ts.tv_sec += ts.tv_nsec / (1000 * 1000 * 1000)
        ts.tv_nsec %= (1000 * 1000 * 1000)
        if (pthread_cond_timedwait(&cond, &mutex, &ts) == 0) {
            return .Signaled
        } else {
            return .TimedOut
        }
    }
    func lock() {
        pthread_mutex_lock(&mutex)
    }
    func unlock() {
        pthread_mutex_unlock(&mutex)
    }
    func write(buffer : UnsafePointer<UInt8>, length : Int) throws -> Int {
        if length < 0 {
            throw errNegative
        }
        var total = 0
        for ;; {
            lock()
            for ;; {
                if closed {
                    unlock()
                    throw errClosed
                }
                if NSDate().compare(_writeDeadline) != .OrderedAscending {
                    unlock()
                    throw errTimeout
                }
                if let serror = errorForStatus(wr) {
                    unlock()
                    throw serror
                }
                if wr.hasSpaceAvailable {
                    break
                }
                wait(0.25)
            }
            let n = wr.write(buffer+total, maxLength: length-total)
            unlock()
            if n < 0 {
                throw errStream
            }
            total += n
            if total > length {
                throw errStream
            } else if total == length {
                break
            }
        }
        return total
    }
    func errorForStatus(stream : NSStream) -> ErrorType? {
        switch stream.streamStatus {
        case .NotOpen, .Closed:
            return errClosed
        case .Error:
            if let error = stream.streamError {
                return error
            }
            return errStream
        case .AtEnd:
            return errEOF
        default:
            return nil
        }
    }
    func read(buffer : UnsafeMutablePointer<UInt8>, length : Int) throws -> Int {
        if length < 0 {
            throw errNegative
        }
        for var i = 0; i < 2; i++ {
            lock()
            for ;; {
                if closed {
                    unlock()
                    throw errClosed
                }
                if NSDate().compare(_readDeadline) != .OrderedAscending {
                    unlock()
                    throw errTimeout
                }
                if let serror = errorForStatus(rd) {
                    unlock()
                    throw serror
                }
                if rd.hasBytesAvailable {
                    break
                }
                wait(0.25)
            }
            if i == 1 {
                unlock()
                return 0
            }
            let n = rd.read(buffer, maxLength: length)
            unlock()
            if n < 0 {
                throw errStream
            } else if n > 0 {
                return n
            }
        }
        return 0
    }
    func signal(){
        pthread_mutex_lock(&mutex)
        pthread_cond_broadcast(&cond)
        pthread_mutex_unlock(&mutex)
    }
    func close() {
        lock()
        defer {
            unlock()
        }
        if closed {
            return
        }
        closed = true
        rd.delegate = nil
        wr.delegate = nil
        rd.removeFromRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        wr.removeFromRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        rd.close()
        wr.close()
        delegate.c = nil
        pthread_cond_broadcast(&cond)
    }
    var opened : Bool {
        lock()
        defer { unlock() }
        return !closed
    }
}



private class Frame {
    var inflate = false
    var code = OpCode.Continue
    var utf8 = UTF8()
    var payload = BoxedBytes()
    var statusCode = UInt16(0)
    var finished = true
}

private struct z_stream {
    var next_in : UnsafePointer<UInt8> = nil
    var avail_in : CUnsignedInt = 0
    var total_in : CUnsignedLong = 0
    
    var next_out : UnsafeMutablePointer<UInt8> = nil
    var avail_out : CUnsignedInt = 0
    var total_out : CUnsignedLong = 0
    
    var msg : UnsafePointer<CChar> = nil
    var state : COpaquePointer = nil
    
    var zalloc : COpaquePointer = nil
    var zfree : COpaquePointer = nil
    var opaque : COpaquePointer = nil
    
    var data_type : CInt = 0
    var adler : CUnsignedLong = 0
    var reserved : CUnsignedLong = 0
}

@asmname("zlibVersion") private func zlibVersion() -> COpaquePointer
@asmname("deflateInit2_") private func deflateInit2(strm : UnsafeMutablePointer<Void>, level : CInt, method : CInt, windowBits : CInt, memLevel : CInt, strategy : CInt, version : COpaquePointer, stream_size : CInt) -> CInt
@asmname("deflateInit_") private func deflateInit(strm : UnsafeMutablePointer<Void>, level : CInt, version : COpaquePointer, stream_size : CInt) -> CInt
@asmname("deflateEnd") private func deflateEnd(strm : UnsafeMutablePointer<Void>) -> CInt
@asmname("deflate") private func deflate(strm : UnsafeMutablePointer<Void>, flush : CInt) -> CInt
@asmname("inflateInit2_") private func inflateInit2(strm : UnsafeMutablePointer<Void>, windowBits : CInt, version : COpaquePointer, stream_size : CInt) -> CInt
@asmname("inflateInit_") private func inflateInit(strm : UnsafeMutablePointer<Void>, version : COpaquePointer, stream_size : CInt) -> CInt
@asmname("inflate") private func inflateG(strm : UnsafeMutablePointer<Void>, flush : CInt) -> CInt
@asmname("inflateEnd") private func inflateEndG(strm : UnsafeMutablePointer<Void>) -> CInt

private func zerror(res : CInt) -> ErrorType? {
    var err = ""
    switch res {
    case 0: return nil
    case 1: err = "stream end"
    case 2: err = "need dict"
    case -1: err = "errno"
    case -2: err = "stream error"
    case -3: err = "data error"
    case -4: err = "mem error"
    case -5: err = "buf error"
    case -6: err = "version error"
    default: err = "undefined error"
    }
    return makeError("\(err): \(res)")
}

private class Inflater {
    var windowBits = 0
    var strm = z_stream()
    var tInput = [[UInt8]]()
    var inflateEnd : [UInt8] = [0x00, 0x00, 0xFF, 0xFF]
    var bufferSize = 1024
    var buffer = UnsafeMutablePointer<UInt8>(malloc(1024))
    init?(windowBits : Int){
        if buffer == nil {
            return nil
        }
        self.windowBits = windowBits
        let ret = inflateInit2(&strm, windowBits: -CInt(windowBits), version: zlibVersion(), stream_size: CInt(sizeof(z_stream)))
        if ret != 0 {
            return nil
        }
    }
    deinit{
        inflateEndG(&strm)
        free(buffer)
    }
    func inflate(bufin : UnsafePointer<UInt8>, length : Int, final : Bool) throws -> (p : UnsafeMutablePointer<UInt8>, n : Int){
        var buf = buffer
        var bufsiz = bufferSize
        var buflen = 0
        for var i = 0; i < 2; i++ {
            if i == 0 {
                strm.avail_in = CUnsignedInt(length)
                strm.next_in = UnsafePointer<UInt8>(bufin)
            } else {
                if !final {
                    break
                }
                strm.avail_in = CUnsignedInt(inflateEnd.count)
                strm.next_in = UnsafePointer<UInt8>(inflateEnd)
            }
            for ;; {
                strm.avail_out = CUnsignedInt(bufsiz)
                strm.next_out = buf
                inflateG(&strm, flush: 0)
                let have = bufsiz - Int(strm.avail_out)
                bufsiz -= have
                buflen += have
                if strm.avail_out != 0{
                    break
                }
                if bufsiz == 0 {
                    bufferSize *= 2
                    let nbuf = UnsafeMutablePointer<UInt8>(realloc(buffer, bufferSize))
                    if nbuf == nil {
                        throw makeError("out of memory")
                    }
                    buffer = nbuf
                    buf = buffer+Int(buflen)
                    bufsiz = bufferSize - buflen
                }
            }
        }
        return (buffer, buflen)
    }
}

private class Deflater {
    var windowBits = 0
    var memLevel = 0
    var strm = z_stream()
    var bufferSize = 1024
    var buffer = UnsafeMutablePointer<UInt8>(malloc(1024))
    init?(windowBits : Int, memLevel : Int){
        if buffer == nil {
            return nil
        }
        self.windowBits = windowBits
        self.memLevel = memLevel
        let ret = deflateInit2(&strm, level: 6, method: 8, windowBits: -CInt(windowBits), memLevel: CInt(memLevel), strategy: 0, version: zlibVersion(), stream_size: CInt(sizeof(z_stream)))
        if ret != 0 {
            return nil
        }
    }
    deinit{
        deflateEnd(&strm)
        free(buffer)
    }
    func deflate(bufin : UnsafePointer<UInt8>, length : Int, final : Bool) -> (p : UnsafeMutablePointer<UInt8>, n : Int, err : NSError?){
        return (nil, 0, nil)
    }
}

private class UTF8 {
    var text : String = ""
    var count : UInt32 = 0          // number of bytes
    var procd : UInt32 = 0          // number of bytes processed
    var codepoint : UInt32 = 0      // the actual codepoint
    var bcount = 0
    init() { text = "" }
    func append(byte : UInt8) throws {
        if count == 0 {
            if byte <= 0x7F {
                text.append(UnicodeScalar(byte))
                return
            }
            if byte == 0xC0 || byte == 0xC1 {
                throw makeError("invalid codepoint: invalid byte")
            }
            if byte >> 5 & 0x7 == 0x6 {
                count = 2
            } else if byte >> 4 & 0xF == 0xE {
                count = 3
            } else if byte >> 3 & 0x1F == 0x1E {
                count = 4
            } else {
                throw makeError("invalid codepoint: frames")
            }
            procd = 1
            codepoint = (UInt32(byte) & (0xFF >> count)) << ((count-1) * 6)
            return
        }
        if byte >> 6 & 0x3 != 0x2 {
            throw makeError("invalid codepoint: signature")
        }
        codepoint += UInt32(byte & 0x3F) << ((count-procd-1) * 6)
        if codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
            throw makeError("invalid codepoint: out of bounds")
        }
        procd++
        if procd == count {
            if codepoint <= 0x7FF && count > 2 {
                throw makeError("invalid codepoint: overlong")
            }
            if codepoint <= 0xFFFF && count > 3 {
                throw makeError("invalid codepoint: overlong")
            }
            procd = 0
            count = 0
            text.append(UnicodeScalar(codepoint))
        }
        return
    }
    func append(bytes : UnsafePointer<UInt8>, length : Int) throws {
        if length == 0 {
            return
        }
        if count == 0 {
            var ascii = true
            for var i = 0; i < length; i++ {
                if bytes[i] > 0x7F {
                    ascii = false
                    break
                }
            }
            if ascii {
                text += NSString(bytes: bytes, length: length, encoding: NSASCIIStringEncoding) as! String
                bcount += length
                return
            }
        }
        for var i = 0; i < length; i++ {
            try append(bytes[i])
        }
        bcount += length
    }
    var completed : Bool {
        return count == 0
    }
    static func bytes(string : String) -> [UInt8]{
        let data = string.dataUsingEncoding(NSUTF8StringEncoding)!
        return [UInt8](UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(data.bytes), count: data.length))
    }
    static func string(bytes : [UInt8]) -> String{
        if let str = NSString(bytes: bytes, length: bytes.count, encoding: NSUTF8StringEncoding) {
            return str as String
        }
        return ""
    }
}

private class WebSocketConn {
    var c : TCPConn?
    var inflater : Inflater?
    var deflater : Deflater?
    var subProtocol = ""
    var buffer = [UInt8](count: 1024*16, repeatedValue: 0)
    init(_ request : NSURLRequest, protocols : [String] = [], services : TCPConnService = TCPConnService(0), compression : WebSocketCompression = WebSocketCompression()) throws {
        if request.URL == nil {
            let _ = try TCPConn("")
        }
        let req = request.mutableCopy() as! NSMutableURLRequest
        req.setValue("websocket", forHTTPHeaderField: "Upgrade")
        req.setValue("Upgrade", forHTTPHeaderField: "Connection")
        req.setValue("SwiftWebSocket", forHTTPHeaderField: "User-Agent")
        req.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        if req.URL!.port == nil || req.URL!.port!.integerValue == 80 || req.URL!.port!.integerValue == 443  {
            req.setValue(req.URL!.host!, forHTTPHeaderField: "Host")
        } else {
            req.setValue("\(req.URL!.host!):\(req.URL!.port!.integerValue)", forHTTPHeaderField: "Host")
        }
        req.setValue(req.URL!.absoluteString, forHTTPHeaderField: "Origin")
        if protocols.count > 0 {
            req.setValue(";".join(protocols), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        if req.URL!.scheme != "wss" && req.URL!.scheme != "ws" {
            let _ = try TCPConn("")
        }
        if compression.on {
            var val = "permessage-deflate"
            if compression.noContextTakeover {
                val += "; client_no_context_takeover; server_no_context_takeover"
            }
            val += "; client_max_window_bits"
            if compression.maxWindowBits != 0 {
                val += "; server_max_window_bits=\(compression.maxWindowBits)"
            }
            req.setValue(val, forHTTPHeaderField: "Sec-WebSocket-Extensions")
        }
        
        var security = TCPConnSecurity.None
        let port : Int
        if req.URL!.port != nil {
            port = req.URL!.port!.integerValue
        } else if req.URL!.scheme == "wss" {
            port = 443
            security = .NegoticatedSSL
        } else {
            port = 80
            security = .None
        }
        var path = CFURLCopyPath(req.URL!) as String
        if path == "" {
            path = "/"
        }
        if let q = req.URL!.query {
            if q != "" {
                path += "?" + q
            }
        }
        var reqs = "GET \(path) HTTP/1.1\r\n"
        for key in req.allHTTPHeaderFields!.keys.array {
            if let val = req.valueForHTTPHeaderField(key) {
                reqs += "\(key): \(val)\r\n"
            }
        }
        var keyb = [UInt32](count: 4, repeatedValue: 0)
        for var i = 0; i < 4; i++ {
            keyb[i] = arc4random()
        }
        let rkey = NSData(bytes: keyb, length: 16).base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
        reqs += "Sec-WebSocket-Key: \(rkey)\r\n"
        reqs += "\r\n"
        var header = [UInt8]()
        for b in reqs.utf8 {
            header += [b]
        }
        
        c = try TCPConn("\(req.URL!.host!):\(port)", security: security, services: services)
        try c!.write(header, length: header.count)
        var needsCompression = false
        var serverMaxWindowBits = 15
        let clientMaxWindowBits = 15
        var key = ""
        var b = UInt8(0)
        for var i = 0;; i++ {
            var lineb : [UInt8] = []
            for ;; {
                try readByte(&b)
                if b == 0xA {
                    break
                }
                lineb += [b]
            }
            let lineo = String(bytes: lineb, encoding: NSUTF8StringEncoding)
            if lineo == nil {
                throw errUTF8
            }
            let trim : (String)->(String) = { (text) in return text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())}
            let eqval : (String,String)->(String) = { (line, del) in return trim(line.componentsSeparatedByString(del)[1]) }
            let line = trim(lineo!)
            if i == 0  {
                if !line.hasPrefix("HTTP/1.1 101"){
                    throw makeError("invalid response (\(line))")
                }
            } else if line != "" {
                var value = ""
                if line.hasPrefix("\t") || line.hasPrefix(" ") {
                    value = trim(line)
                } else {
                    key = ""
                    if let r = line.rangeOfString(":") {
                        key = trim(line.substringToIndex(r.startIndex))
                        value = trim(line.substringFromIndex(r.endIndex))
                    }
                }
                switch key {
                case "Sec-WebSocket-SubProtocol":
                    subProtocol = value
                case "Sec-WebSocket-Extensions":
                    let parts = value.componentsSeparatedByString(";")
                    for p in parts {
                        let part = trim(p)
                        if part == "permessage-deflate" {
                            needsCompression = true
                        } else if part.hasPrefix("server_max_window_bits="){
                            if let i = Int(eqval(line, "=")) {
                                serverMaxWindowBits = i
                            }
                        }
                    }
                default:
                    break
                }
            }
            if line == "" {
                break
            }
        }
        if needsCompression {
            if serverMaxWindowBits < 8 || serverMaxWindowBits > 15 {
                throw makeError("invalid server_max_window_bits")
            }
            if serverMaxWindowBits < 8 || serverMaxWindowBits > 15 {
                throw makeError("invalid client_max_window_bits")
            }
            inflater = Inflater(windowBits: serverMaxWindowBits)
            if inflater == nil {
                throw makeError("inflater init")
            }
            deflater = Deflater(windowBits: clientMaxWindowBits, memLevel: 8)
            if deflater == nil {
                throw makeError("deflater init")
            }
        }
    }
    convenience init(_ url : String) throws {
        let nsurl = NSURL(string: url)
        if nsurl == nil {
            try self.init(NSURLRequest())
        } else {
            try self.init(NSURLRequest(URL: nsurl!))
        }
    }
    
    func close(code : Int, reason : String) {
        let f = Frame()
        (f.code, f.statusCode, f.utf8.text) = (.Close, UInt16(code), reason)
        do {
            try writeFrame(f)
        } catch {
            
        }
        close()
    }
    
    func close() {
        c!.close()
    }
    
    var opened : Bool {
        return c!.opened
    }
    
    @inline(__always) func readByte(inout b : UInt8) throws {
        for ;; {
            let n = try c!.read(&b, length: 1)
            if n == 1  {
                break
            }
        }
    }

    var savedFrame : Frame?
    func readFrame() throws -> Frame {

        var (f, fin): (Frame, Bool) = (Frame(), false)
        if savedFrame != nil {
            (f, fin) = (savedFrame!, false)
            savedFrame = nil
        } else {
            f = try readFrameFragment(nil)
            fin = f.finished
        }
        if f.code == .Continue{
            throw makeError("leader frame cannot be a continue frame", .Protocol)
        }
        while !fin {
            let cf = try readFrameFragment(f)
            fin = cf.finished
            if cf.code != .Continue {
                if !cf.code.isControl {
                    throw makeError("only ping frames can be interlaced with fragments", .Protocol)
                }
                savedFrame = f
                return cf
            }
        }
        if !f.utf8.completed {
            throw makeError("incomplete utf8", .Payload)
        }
        return f
    }

    var reusedBoxedBytes = BoxedBytes()
    func readFrameFragment(var leader : Frame?) throws -> Frame {
        var b = UInt8(0)
        do {
            try readByte(&b)
        } catch {
            throw makeError(error, .Protocol)
        }
        var inflate = false
        let fin = b >> 7 & 0x1 == 0x1
        let rsv1 = b >> 6 & 0x1 == 0x1
        let rsv2 = b >> 5 & 0x1 == 0x1
        let rsv3 = b >> 4 & 0x1 == 0x1
        if inflater != nil && (rsv1 || (leader != nil && leader!.inflate)) {
            inflate = true
        } else if rsv1 || rsv2 || rsv3 {
            throw makeError("invalid extension", .Protocol)
        }
        var code = OpCode.Binary
        if let c = OpCode(rawValue: (b & 0xF)){
            code = c
        } else {
            throw makeError("invalid opcode", .Protocol)
        }
        if !fin && code.isControl {
            throw makeError("unfinished control frame", .Protocol)
        }
        do {
            try readByte(&b)
        } catch {
            throw makeError(error, .Protocol)
        }
        if b >> 7 & 0x1 == 0x1 {
            throw makeError("server sent masked frame", .Protocol)
        }
        var len64 = Int64(b & 0x7F)
        var bcount = 0
        if b & 0x7F == 126 {
            bcount = 2
        } else if len64 == 127 {
            bcount = 8
        }
        if bcount != 0 {
            if code.isControl {
                throw makeError("invalid payload size for control frame", .Protocol)
            }
            len64 = 0
            for var i = bcount-1; i >= 0; i-- {
                do {
                    try readByte(&b)
                } catch {
                    throw makeError(error, .Protocol)
                }
                len64 += Int64(b) << Int64(i*8)
            }
        }
        var len = Int(len64)
        if code == .Continue {
            if code.isControl {
                throw makeError("control frame cannot have the 'continue' opcode", .Protocol)
            }
            if leader == nil {
                throw makeError("continue frame is missing it's leader", .Protocol)
            }
        }
        if code.isControl {
            if leader != nil {
                leader = nil
            }
            if inflate {
                throw makeError("control frame cannot be compressed", .Protocol)
            }
        }
        var utf8 : UTF8
        var payload : BoxedBytes
        var statusCode = UInt16(0)
        var leaderCode : OpCode
        if leader != nil {
            leaderCode = leader!.code
            utf8 = leader!.utf8
            payload = leader!.payload
        } else {
            leaderCode = code
            utf8 = UTF8()
            payload = reusedBoxedBytes
            payload.count = 0
        }
        if leaderCode == .Close {
            if len == 1 {
                throw makeError("invalid payload size for close frame", .Protocol)
            }
            if len >= 2 {
                var (b1, b2) = (UInt8(0), UInt8(0))
                do {
                    try readByte(&b1)
                    try readByte(&b2)
                } catch {
                    throw makeError(error, .Payload)
                }
                statusCode = (UInt16(b1) << 8) + UInt16(b2)
                len -= 2
                if statusCode < 1000 || statusCode > 4999  || (statusCode >= 1004 && statusCode <= 1006) || (statusCode >= 1012 && statusCode <= 2999) {
                    throw makeError("invalid status code for close frame", .Protocol)
                }
            }
        }
        
        if leaderCode == .Text || leaderCode == .Close {
            var take = Int(len)
            repeat {
                var n : Int = 0
                if take > 0 {
                    var c = take
                    if c > buffer.count {
                        c = buffer.count
                    }
                    do {
                        n = try self.c!.read(&buffer, length: c)
                    } catch {
                        throw makeError(error, .Payload)
                    }
                }
                do {
                    if inflate {
                        let (bytes, bytesLen) : (UnsafeMutablePointer<UInt8>, Int)
                        do {
                            (bytes, bytesLen) = try inflater!.inflate(&buffer, length: n, final: (take - n == 0) && fin)
                        } catch {
                            throw makeError(error, .Payload)
                        }
                        if bytesLen > 0 {
                            try utf8.append(bytes, length: bytesLen)
                        }
                    } else {
                        try utf8.append(&buffer, length: n)
                    }
                } catch {
                    throw makeError(error, .Payload)
                }
                take -= n
            } while take > 0
        } else {
            var start = payload.count
            if !inflate {
                payload.count += len
            }
            var take = Int(len)
            repeat {
                var n : Int = 0
                if inflate {
                    if take > 0 {
                        var c = take
                        if c > buffer.count {
                            c = buffer.count
                        }
                        do {
                            n = try self.c!.read(&buffer, length: c)
                        } catch {
                            throw makeError(error, .Payload)
                        }
                    }
                    let (bytes, bytesLen) : (UnsafeMutablePointer<UInt8>, Int)
                    do {
                        (bytes, bytesLen) = try inflater!.inflate(&buffer, length: n, final: (take - n == 0) && fin)
                    } catch {
                        throw makeError(error, .Payload)
                    }
                    if bytesLen > 0 {
                        payload.append(bytes, length: bytesLen)
                    }
                } else if take > 0 {
                    do {
                        n = try self.c!.read(payload.ptr+start, length: take)
                    } catch {
                        throw makeError(error, .Payload)
                    }
                    start += n
                }
                take -= n
            } while take > 0
        }
        let f = Frame()
        (f.code, f.payload, f.utf8, f.statusCode, f.inflate, f.finished) = (code, payload, utf8, statusCode, inflate, fin)
        return f
    }
    var head = [UInt8](count: 0xFF, repeatedValue: 0)
    func writeFrame(f : Frame) throws {
        if !f.finished{
            throw makeError("cannot send unfinished frames", .Library)
        }
        var hlen = 0
        let b : UInt8 = 0x80
        var deflate = false
        if deflater != nil {
            if f.code == .Binary || f.code == .Text {
                deflate = true
                // b |= 0x40
            }
        }
        head[hlen++] = b | f.code.rawValue
        var payloadBytes : [UInt8]
        var payloadLen = 0
        if f.utf8.text != "" {
            payloadBytes = UTF8.bytes(f.utf8.text)
        } else {
            payloadBytes = f.payload.array
        }
        payloadLen += payloadBytes.count
        if deflate {
            
        }
        var usingStatusCode = false
        if f.statusCode != 0 && payloadLen != 0 {
            payloadLen += 2
            usingStatusCode = true
        }
        if payloadLen < 126 {
            head[hlen++] = 0x80 | UInt8(payloadLen)
        } else if payloadLen <= 0xFFFF {
            head[hlen++] = 0x80 | 126
            for var i = 1; i >= 0; i-- {
                head[hlen++] = UInt8((UInt16(payloadLen) >> UInt16(i*8)) & 0xFF)
            }
        } else {
            head[hlen++] = UInt8((0x1 << 7) + 127)
            for var i = 7; i >= 0; i-- {
                head[hlen++] = UInt8((UInt64(payloadLen) >> UInt64(i*8)) & 0xFF)
            }
        }
        let r = arc4random()
        var maskBytes : [UInt8] = [UInt8(r >> 0 & 0xFF), UInt8(r >> 8 & 0xFF), UInt8(r >> 16 & 0xFF), UInt8(r >> 24 & 0xFF)]
        for var i = 0; i < 4; i++ {
            head[hlen++] = maskBytes[i]
        }
        if payloadLen > 0 {
            if usingStatusCode {
                var sc = [UInt8(f.statusCode >> 8 & 0xFF), UInt8(f.statusCode >> 0 & 0xFF)]
                for var i = 0; i < 2; i++ {
                    sc[i] ^= maskBytes[i % 4]
                }
                head[hlen++] = sc[0]
                head[hlen++] = sc[1]
                for var i = 2; i < payloadLen; i++ {
                    payloadBytes[i-2] ^= maskBytes[i % 4]
                }
            } else {
                for var i = 0; i < payloadLen; i++ {
                    payloadBytes[i] ^= maskBytes[i % 4]
                }
            }
        }
        var written = 0
        while written < hlen {
            let n = try self.c!.write((&head)+written, length: hlen-written)
            if n == -1 {
                break
            }
            written += n
        }
        written = 0
        while written < payloadBytes.count {
            let n = try self.c!.write((&payloadBytes)+written, length: payloadBytes.count-written)
            if n == -1 {
                break
            }
            written += n
        }
    }
    var readDeadline : NSDate {
        get {
            return c!.readDeadline
        }
        set {
            c!.readDeadline = newValue
        }
    }
    var writeDeadline : NSDate {
        get {
            return c!.writeDeadline
        }
        set {
            c!.writeDeadline = newValue
        }
    }
}
