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

/// Delegate methods that are common to all forms of WebSocket. These are all optional. For pure Swift projects, it's recommended to use the WebSocket.Event object instead.
@objc public protocol WebSocketDelegate {
    /// An event to be called when the WebSocket connection's readyState changes to .Open; this indicates that the connection is ready to send and receive data.
    optional func webSocketDidOpen(webSocket: WebSocket)
    /// An event to be called when the WebSocket connection's readyState changes to .Closed.
    optional func webSocket(webSocket: WebSocket, didCloseWithCode code: Int, reason: String, wasClean : Bool)
    /// An event to be called when a message is received from the server.
    optional func webSocket(webSocket: WebSocket, didReceiveMessage message : AnyObject)
    /// An event to be called when a pong is received from the server.
    optional func webSocket(webSocket: WebSocket, didReceivePong message : AnyObject)
    /// An event to be called when an error occurs.
    optional func webSocket(webSocket: WebSocket, didFailWithError error : NSError)
    /// An event to be called when the WebSocket process has ended; this event is guarenteed to be called once and can be used as an alternative to the "close" or "error" events.
    optional func webSocket(webSocket: WebSocket, didEndWithCode code: Int, reason: String, wasClean : Bool, error : NSError?)
}

/// A WebSocket object provides support for creating and managing a WebSocket connection to a server, as well as for sending and receiving data on the connection.
@objc public class WebSocket {
    /// The WebSocket.ReadyState enum is used by the readyState property to describe the status of the WebSocket connection.
    public enum ReadyState : Int, Printable {
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
    /// The WebSocket.BinaryType enum is used by the binaryType property and indicates the type of binary data being transmitted by the WebSocket connection.
    public enum BinaryType : Printable {
        /// The WebSocket should transmit [UInt8] objects.
        case UInt8Array
        /// The WebSocket should transmit NSData objects.
        case NSData
        /// Returns a string that represents the ReadyState value.
        public var description : String {
            switch self {
            case UInt8Array: return "UInt8Array"
            case NSData: return "NSData"
            }
        }
    }
    /// The WebSocket.Events class is used by the events property and manages the events for the WebSocket connection.
    public class Events {
        /// Strict event synchronization with background connection. Forces the connection to wait until an event has returned before processing the next frame.
        public var synced = false
        /// An event to be called when the WebSocket connection's readyState changes to .Open; this indicates that the connection is ready to send and receive data.
        public var open : ()->() = {}
        /// An event to be called when the WebSocket connection's readyState changes to .Closed.
        public var close : (code : Int, reason : String, wasClean : Bool)->() = {(code, reason, wasClean) in}
        /// An event to be called when an error occurs.
        public var error : (error : NSError)->() = {(error) in}
        /// An event to be called when a message is received from the server.
        public var message : (data : Any)->() = {(data) in}
        /// An event to be called when a pong is received from the server.
        public var pong : (data : Any)->() = {(data) in}
        /// An event to be called when the WebSocket process has ended; this event is guarenteed to be called once and can be used as an alternative to the "close" or "error" events.
        public var end : (code : Int, reason : String, wasClean : Bool, error : NSError?)->() = {(code, reason, wasClean, error) in}
    }
    
    private static let defaultMaxWindowBits = 15
    /// The WebSocket.Compression struct is used by the compression property and manages the compression options for the WebSocket connection.
    public struct Compression {
        // Used to accept compressed messages from the server. Default is true.
        public var on = false
        // request no context takeover.
        public var noContextTakeover = false
        // request max window bits.
        public var maxWindowBits = WebSocket.defaultMaxWindowBits
    }
    
    private let request : NSURLRequest!
    private let subProtocols : [String]!
    private var mutex = pthread_mutex_t()
    private var cond = pthread_cond_t()
    private var frames = [Frame]()
    private var closeCode = 0
    private var closeReason = ""
    private var closeClient = false
    /// The compression options of the WebSocket.
    public var compression = Compression()
    /// The delegate of the WebSocket.
    public var delegate : WebSocketDelegate?
    /// The events of the WebSocket.
    public var event = Events()
    /// A Boolean value that determines whether the WebSocket uses background VOIP service.
    public var voipEnabled = false
    
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    public convenience init(url: String){
        self.init(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: [])
    }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a list of protocols.
    public convenience init(url: String, subProtocols : [String]){
        self.init(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: subProtocols)
    }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a protocol.
    public convenience init(url: String, subProtocol : String){
        self.init(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: [subProtocol])
    }
    /// Create a WebSocket connection from an NSURLRequest; Also include a list of protocols.
    public init(request: NSURLRequest, subProtocols : [String] = []){
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&cond, nil)
        self.request = request
        self.subProtocols = subProtocols
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue()){
            let compression_ = self.compression
            let events_ = self.event
            let delegate_ = self.delegate
            let voipEnabled_ = self.voipEnabled
            dispatch_async(dispatch_queue_create(nil, nil), {
                var defers : [()->()] = []
                self.main(&defers, compression: compression_, events: events_, delegate: delegate_, voipEnabled: voipEnabled_)
                for var i = defers.count-1; i >= 0; i-- {
                    defers[i]()
                }
            })
        }
    }
    deinit{
        pthread_cond_destroy(&cond)
        pthread_mutex_init(&mutex, nil)
    }
    
    /// The URL as resolved by the constructor. This is always an absolute URL. Read only.
    public var url : String {
        return request.URL!.description
    }
    private var _subProtocol = ""
    /// A string indicating the name of the sub-protocol the server selected; this will be one of the strings specified in the protocols parameter when creating the WebSocket object.
    public var subProtocol : String {
        pthread_mutex_lock(&mutex)
        var ret = _subProtocol
        pthread_mutex_unlock(&mutex)
        return ret
    }
    private var _readyState = ReadyState.Connecting
    /// The current state of the connection; this is one of the WebSocket.ReadyState constants. Read only.
    public var readyState : ReadyState {
        pthread_mutex_lock(&mutex)
        var ret = _readyState
        pthread_mutex_unlock(&mutex)
        return ret
    }
    private var _binaryType = BinaryType.UInt8Array
    /// A WebSocket.BinaryType value indicating the type of binary data being transmitted by the connection. Default is .UInt8Array.
    public var binaryType : BinaryType {
        get {
            pthread_mutex_lock(&mutex)
            var ret = _binaryType
            pthread_mutex_unlock(&mutex)
            return ret
        }
        set {
            pthread_mutex_lock(&mutex)
            _binaryType = newValue
            pthread_mutex_unlock(&mutex)
        }
    }
    private enum Event {
        case Opened, Closed, Error, Text, Binary, End, Pong
    }
    private func fireEvent(events : Events, delegate : WebSocketDelegate?, event : Event, arg1 : AnyObject? = nil, arg2 : AnyObject? = nil, arg3 : AnyObject? = nil, arg4 : AnyObject? = nil){
        let block : ()->() = {
            let binaryType = self.binaryType
            switch event {
            case .End:
                events.end(code: arg1 as! Int, reason: arg2 as! String, wasClean: arg3 as! Bool, error: arg4 as? NSError)
                delegate?.webSocket?(self, didEndWithCode: arg1 as! Int, reason: arg2 as! String, wasClean: arg3 as! Bool, error: arg4 as? NSError)
            case .Opened:
                events.open()
                delegate?.webSocketDidOpen?(self)
            case .Closed:
                events.close(code: arg1 as! Int, reason: arg2 as! String, wasClean: arg3 as! Bool)
                delegate?.webSocket?(self, didCloseWithCode: arg1 as! Int, reason: arg2 as! String, wasClean: arg3 as! Bool)
            case .Error:
                events.error(error: arg1 as! NSError)
                delegate?.webSocket?(self, didFailWithError: arg1 as! NSError)
            case .Text:
                events.message(data: (arg1 as! Frame).utf8.text)
                delegate?.webSocket?(self, didReceiveMessage: (arg1 as! Frame).utf8.text)
            case .Binary, .Pong:
                var bytes = (arg1 as! Frame).payload.bytes
                var nsdata : NSData?
                if binaryType == .NSData || delegate != nil {
                    nsdata = NSData(bytes: &bytes, length: bytes.count)
                }
                if event == .Binary {
                    if binaryType == .NSData {
                        events.message(data: nsdata!)
                    } else {
                        events.message(data: bytes)
                    }
                    if delegate != nil {
                        delegate?.webSocket?(self, didReceiveMessage: nsdata!)
                    }
                } else {
                    if binaryType == .NSData {
                        events.pong(data: nsdata!)
                    } else {
                        events.pong(data: bytes)
                    }
                    if delegate != nil {
                        delegate?.webSocket?(self, didReceivePong: nsdata!)
                    }
                }
            }
        }
        if events.synced {
            dispatch_sync(dispatch_get_main_queue(), block)
        } else {
            dispatch_async(dispatch_get_main_queue(), block)
        }
    }
    private func main(inout defers : [()->()], compression : Compression, events : Events, delegate : WebSocketDelegate?, voipEnabled: Bool) {
        var fireMutex = pthread_mutex_t()
        var (err, werr, rerr) : (NSError?, NSError?, NSError?)
        var closeClean = false
        var unrolled = false
        var lockunroll = false
        var eventsAllowed = true
        pthread_mutex_init(&fireMutex, nil)
        defers += [{
            pthread_mutex_lock(&self.mutex)
            var unrolled_ = unrolled
            pthread_mutex_unlock(&self.mutex)
            if !unrolled_ {
                if err != nil {
                    pthread_mutex_lock(&fireMutex)
                    if eventsAllowed {
                        self.fireEvent(events, delegate: delegate, event: .Error, arg1: err)
                    }
                    pthread_mutex_unlock(&fireMutex)
                }
                pthread_mutex_lock(&fireMutex)
                if eventsAllowed {
                    self.fireEvent(events, delegate: delegate, event: .End, arg1: self.closeCode, arg2: self.closeReason, arg3: closeClean, arg4: err)
                }
                pthread_mutex_unlock(&fireMutex)
            }
            pthread_mutex_destroy(&fireMutex)
        }]
        let s = Stream(request: request, subProtocols: subProtocols, voipEnabled: voipEnabled, compression: compression)
        err = s.open()
        if err != nil {
            return
        }
        pthread_mutex_lock(&mutex)
        _subProtocol = s.subProtocol
        _readyState = .Open
        pthread_mutex_unlock(&mutex)
        pthread_mutex_lock(&fireMutex)
        if eventsAllowed {
            self.fireEvent(events, delegate: delegate, event: .Opened)
        }
        pthread_mutex_unlock(&fireMutex)
        defers += [{
            pthread_mutex_lock(&self.mutex)
            self._readyState = .Closed
            var (closeCode, closeReason, unrolled_) = (self.closeCode, self.closeReason, unrolled)
            pthread_mutex_unlock(&self.mutex)
            if !unrolled_ {
                pthread_mutex_lock(&fireMutex)
                if eventsAllowed {
                    self.fireEvent(events, delegate: delegate, event: .Closed, arg1: closeCode, arg2: closeReason, arg3: closeClean)
                }
                pthread_mutex_unlock(&fireMutex)
            }
        }]
        defers += [{
            pthread_mutex_lock(&self.mutex)
            lockunroll = true
            var unrolled_ = unrolled
            self._readyState = .Closing
            rerr = err
            if rerr == nil {
                rerr = WebSocket.ErrSocket
            }
            pthread_cond_broadcast(&self.cond)
            while werr == nil {
                pthread_cond_wait(&self.cond, &self.mutex)
            }
            if rerr != nil && rerr! == WebSocket.ErrSocket {
                err = rerr
            }
            if !self.closeClient {
                if err != nil && err!.code == WebSocket.ErrCode.Protocol.rawValue {
                    (self.closeCode, self.closeReason) = (1002, "Protocol error")
                } else if err != nil && err!.code == ErrCode.Payload.rawValue {
                    (self.closeCode, self.closeReason) = (1007, "Invalid frame payload data")
                } else {
                    if closeClean == false {
                        (self.closeCode, self.closeReason) = (1006, "Abnormal Closure")
                    }
                }
            }
            if !unrolled_ {
                err = s.close(code: UInt16(self.closeCode), reason: self.closeReason)
            }
            pthread_mutex_unlock(&self.mutex)
            if err != nil{
                return
            }
        }]
        var pongFrames = [Frame]()
        dispatch_async(dispatch_queue_create(nil, nil), {
            var err : NSError?
            outer: for ;; {
                pthread_mutex_lock(&self.mutex)
                for ;; {
                    if rerr != nil || self._readyState.isClosed {
                        var unrolled_ = false
                        var closeReason = self.closeReason
                        var closeCode = self.closeCode
                        var closeClean = false
                        if self.closeClient && !lockunroll{
                            while pongFrames.count != 0 {
                                s.writeFrame(pongFrames.removeAtIndex(0))
                            }
                            while self.frames.count != 0 {
                                s.writeFrame(self.frames.removeAtIndex(0))
                            }
                            s.close(code: UInt16(closeCode), reason: closeReason)
                            unrolled = true
                            unrolled_ = true
                        }
                        pthread_mutex_unlock(&self.mutex)
                        if unrolled_ {
                            pthread_mutex_lock(&fireMutex)
                            if eventsAllowed {
                                self.fireEvent(events, delegate: delegate, event: .Closed, arg1: closeCode, arg2: closeReason, arg3: closeClean)
                                self.fireEvent(events, delegate: delegate, event: .End, arg1: closeCode, arg2: closeReason, arg3: closeClean)
                            }
                            eventsAllowed = false
                            pthread_mutex_unlock(&fireMutex)
                        }
                        break outer
                    } else if pongFrames.count != 0 || self.frames.count != 0 {
                        break
                    }
                    pthread_cond_wait(&self.cond, &self.mutex)
                }
                var f : Frame
                if pongFrames.count != 0 {
                    f = pongFrames.removeAtIndex(0)
                } else {
                    f = self.frames.removeAtIndex(0)
                }
                pthread_mutex_unlock(&self.mutex)
                err = s.writeFrame(f)
                if err != nil {
                    break
                }
            }
            pthread_mutex_lock(&self.mutex)
            if err != nil{
                werr = err
                if !unrolled && !lockunroll {
                    unrolled = true
                    self._readyState = .Closed
                    pthread_mutex_unlock(&self.mutex)
                    pthread_mutex_lock(&fireMutex)
                    if eventsAllowed {
                        self.fireEvent(events, delegate: delegate, event: .Closed, arg1: 0, arg2: "", arg3: false)
                        self.fireEvent(events, delegate: delegate, event: .Error, arg1: werr)
                        self.fireEvent(events, delegate: delegate, event: .End, arg1: 0, arg2: "", arg3: false, arg4: werr)
                    }
                    eventsAllowed = false
                    pthread_mutex_unlock(&fireMutex)
                    pthread_mutex_lock(&self.mutex)
                }
                
            } else {
                werr = WebSocket.ErrSocket
            }
            pthread_cond_broadcast(&self.cond)
            pthread_mutex_unlock(&self.mutex)
        })
        
        
        var f : Frame?
        for ;; {
            pthread_mutex_lock(&self.mutex)
            if werr != nil || _readyState.isClosed || unrolled {
                pthread_mutex_unlock(&self.mutex)
                break
            }
            pthread_mutex_unlock(&self.mutex)
            (f, err) = s.readFrame()
            if err != nil {
                return
            }
            pthread_mutex_lock(&self.mutex)
            if werr != nil || _readyState.isClosed || unrolled {
                pthread_mutex_unlock(&self.mutex)
                break
            }
            pthread_mutex_unlock(&self.mutex)
            switch f!.code {
            case .Close:
                pthread_mutex_lock(&self.mutex)
                (closeCode, closeReason, closeClean) = (Int(f!.statusCode), f!.utf8.text, true)
                pthread_mutex_unlock(&self.mutex)
                return
            case .Ping:
                f?.code = .Pong
                pthread_mutex_lock(&self.mutex)
                pongFrames += [f!]
                pthread_cond_broadcast(&self.cond)
                pthread_mutex_unlock(&self.mutex)
            case .Pong:
                pthread_mutex_lock(&fireMutex)
                if eventsAllowed {
                    fireEvent(events, delegate: delegate, event: .Pong, arg1: f)
                }
                pthread_mutex_unlock(&fireMutex)
            case .Text:
                pthread_mutex_lock(&fireMutex)
                if eventsAllowed {
                    fireEvent(events, delegate: delegate, event: .Text, arg1: f)
                }
                pthread_mutex_unlock(&fireMutex)
            case .Binary:
                pthread_mutex_lock(&fireMutex)
                if eventsAllowed {
                    fireEvent(events, delegate: delegate, event: .Binary, arg1: f)
                }
                pthread_mutex_unlock(&fireMutex)
            default:
                break
            }
        }
    }
    /**
    Closes the WebSocket connection or connection attempt, if any. If the connection is already closed or in the state of closing, this method does nothing.
    
    :param: code An integer indicating the status code explaining why the connection is being closed. If this parameter is not specified, a default value of 1000 (indicating a normal closure) is assumed.
    :param: reason A human-readable string explaining why the connection is closing. This string must be no longer than 123 bytes of UTF-8 text (not characters).
    */
    public func close(code : Int = 1000, reason : String = "Normal Closure") -> NSError? {
        pthread_mutex_lock(&mutex)
        if _readyState.isClosed {
            pthread_mutex_unlock(&mutex)
            return WebSocket.ErrClosed
        }
        (closeCode, closeReason, closeClient, _readyState) = (code, reason, true, .Closing)
        pthread_cond_broadcast(&cond)
        pthread_mutex_unlock(&mutex)
        return nil
    }
    private func sendFrame(f : Frame) -> NSError? {
        pthread_mutex_lock(&mutex)
        if _readyState.isClosed {
            pthread_mutex_unlock(&mutex)
            return WebSocket.ErrClosed
        }
        frames += [f]
        pthread_cond_broadcast(&cond)
        pthread_mutex_unlock(&mutex)
        return nil
    }
    private func sendClose(statusCode : UInt16, reason : String) -> NSError? {
        var f = Frame()
        f.code = .Close
        f.statusCode = statusCode
        f.utf8.text = reason
        return sendFrame(f)
    }
    /**
    Transmits data to the server over the WebSocket connection.
    
    :param: message The data to be sent to the server. Must be NSData, [UInt8], or String
    */
    public func send(message : Any) -> NSError? {
        var f = Frame()
        if message is String {
            f.code = .Text
            f.utf8.text = message as! String
        } else if message is [UInt8] {
            f.code = .Binary
            f.payload.bytes = message as! [UInt8]
        } else if message is NSData {
            f.code = .Binary
            var data = message as! NSData
            f.payload.bytes = [UInt8](count: data.length, repeatedValue: 0)
            memcpy(&f.payload.bytes, data.bytes, data.length)
        } else {
            return WebSocket.makeError("Invalid message type. Expecting String, [UInt8], or NSData.")
        }
        return sendFrame(f)
    }
    /**
    Transmits a ping to the server over the WebSocket connection.
    
    :param: optional message The data to be sent to the server. Must be NSData, [UInt8]
    */
    public func ping(message : AnyObject? = nil) -> NSError? {
        var f = Frame()
        f.code = .Ping
        if message != nil {
            if message is [UInt8] {
                f.payload.bytes = message as! [UInt8]
            } else if message is NSData {
                var data = message as! NSData
                f.payload.bytes = [UInt8](count: data.length, repeatedValue: 0)
                memcpy(&f.payload.bytes, data.bytes, data.length)
            } else {
                return WebSocket.makeError("Invalid message type. Expecting [UInt8], or NSData.")
            }
        }
        return sendFrame(f)
    }
}

private extension WebSocket {
    struct z_stream {
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
    
    @asmname("zlibVersion") static func zlibVersion() -> COpaquePointer
    @asmname("deflateInit2_") static func deflateInit2(strm : UnsafeMutablePointer<Void>, level : CInt, method : CInt, windowBits : CInt, memLevel : CInt, strategy : CInt, version : COpaquePointer, stream_size : CInt) -> CInt
    @asmname("deflateInit_") static func deflateInit(strm : UnsafeMutablePointer<Void>, level : CInt, version : COpaquePointer, stream_size : CInt) -> CInt
    @asmname("deflateEnd") static func deflateEnd(strm : UnsafeMutablePointer<Void>) -> CInt
    @asmname("deflate") static func deflate(strm : UnsafeMutablePointer<Void>, flush : CInt) -> CInt
    @asmname("inflateInit2_") static func inflateInit2(strm : UnsafeMutablePointer<Void>, windowBits : CInt, version : COpaquePointer, stream_size : CInt) -> CInt
    @asmname("inflateInit_") static func inflateInit(strm : UnsafeMutablePointer<Void>, version : COpaquePointer, stream_size : CInt) -> CInt
    @asmname("inflate") static func inflate(strm : UnsafeMutablePointer<Void>, flush : CInt) -> CInt
    @asmname("inflateEnd") static func inflateEnd(strm : UnsafeMutablePointer<Void>) -> CInt
    
    static func zerror(res : CInt) -> NSError? {
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
        return makeError(err, code: Int(15000+res))
    }
    enum OpCode : UInt8, Printable {
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
    enum ErrCode : Int, Printable {
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
    static func makeError(error : String, code : Int = -1) -> NSError {
        return NSError(domain: "com.github.tidwall.SwiftWebSocket", code: code, userInfo: [NSLocalizedDescriptionKey:error])
    }
    static func makeError(error : String, code: ErrCode) -> NSError? {
        return NSError(domain: "com.github.tidwall.SwiftWebSocket", code: code.rawValue, userInfo: [NSLocalizedDescriptionKey:"\(error) (\(code))"])
    }
    
    static let ErrClosed = WebSocket.makeError("closed socket")
    static let ErrSocket = WebSocket.makeError("broken socket")
    class BoxedBytes {
        var bytes = [UInt8]()
    }
    class Frame {
        var inflate = false
        var code = OpCode.Continue
        var utf8 = UTF8()
        var payload = BoxedBytes()
        var statusCode = UInt16(0)
        var finished = true
    }
    class UTF8 {
        var text : String = ""
        var count : UInt32 = 0          // number of bytes
        var procd : UInt32 = 0          // number of bytes processed
        var codepoint : UInt32 = 0      // the actual codepoint
        var bcount = 0
        init() { text = "" }
        func append(byte : UInt8) -> NSError? {
            if count == 0 {
                if byte <= 0x7F {
                    text.append(UnicodeScalar(byte))
                    return nil
                }
                if byte == 0xC0 || byte == 0xC1 {
                    return WebSocket.makeError("invalid codepoint: invalid byte")
                }
                if byte >> 5 & 0x7 == 0x6 {
                    count = 2
                } else if byte >> 4 & 0xF == 0xE {
                    count = 3
                } else if byte >> 3 & 0x1F == 0x1E {
                    count = 4
                } else {
                    return WebSocket.makeError("invalid codepoint: frames")
                }
                procd = 1
                codepoint = (UInt32(byte) & (0xFF >> count)) << ((count-1) * 6)
                return nil
            }
            if byte >> 6 & 0x3 != 0x2 {
                return WebSocket.makeError("invalid codepoint: signature")
            }
            codepoint += UInt32(byte & 0x3F) << ((count-procd-1) * 6)
            if codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
                return WebSocket.makeError("invalid codepoint: out of bounds")
            }
            procd++
            if procd == count {
                if codepoint <= 0x7FF && count > 2 {
                    return WebSocket.makeError("invalid codepoint: overlong")
                }
                if codepoint <= 0xFFFF && count > 3 {
                    return WebSocket.makeError("invalid codepoint: overlong")
                }
                procd = 0
                count = 0
                text.append(UnicodeScalar(codepoint))
            }
            return nil
        }
        func append(bytes : UnsafePointer<UInt8>, length : Int) -> NSError? {
            if length == 0 {
                return nil
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
                    return nil
                }
            }
            for var i = 0; i < length; i++ {
                var err = append(bytes[i])
                if err != nil{
                    return err
                }
            }
            bcount += length
            return nil
        }
        var completed : Bool {
            return count == 0
        }
        static func bytes(string : String) -> [UInt8]{
            var data = string.dataUsingEncoding(NSUTF8StringEncoding)!
            return [UInt8](UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(data.bytes), count: data.length))
        }
        static func string(bytes : [UInt8]) -> String{
            if let str = NSString(bytes: bytes, length: bytes.count, encoding: NSUTF8StringEncoding) {
                return str as String
            }
            return ""
        }
    }
    
    
    
    
    
    
    
    
    
    
    class Stream {
        class Deflater {
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
                var ret = WebSocket.deflateInit2(&strm, level: 6, method: 8, windowBits: -CInt(windowBits), memLevel: CInt(memLevel), strategy: 0, version: WebSocket.zlibVersion(), stream_size: CInt(sizeof(z_stream)))
                if ret != 0 {
                    return nil
                }
            }
            deinit{
                WebSocket.deflateEnd(&strm)
                free(buffer)
            }
            func deflate(bufin : UnsafePointer<UInt8>, length : Int, final : Bool) -> (p : UnsafeMutablePointer<UInt8>, n : Int, err : NSError?){
                return (nil, 0, nil)
            }
            
        }
        class Inflater {
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
                var ret = WebSocket.inflateInit2(&strm, windowBits: -CInt(windowBits), version: WebSocket.zlibVersion(), stream_size: CInt(sizeof(z_stream)))
                if ret != 0 {
                    return nil
                }
            }
            deinit{
                WebSocket.inflateEnd(&strm)
                free(buffer)
            }
            func inflate(bufin : UnsafePointer<UInt8>, length : Int, final : Bool) -> (p : UnsafeMutablePointer<UInt8>, n : Int, err : NSError?){
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
                        var ret = WebSocket.inflate(&strm, flush: 0)
                        var have = bufsiz - Int(strm.avail_out)
                        bufsiz -= have
                        buflen += have
                        if strm.avail_out != 0{
                            break
                        }
                        if bufsiz == 0 {
                            bufferSize *= 2
                            var nbuf = UnsafeMutablePointer<UInt8>(realloc(buffer, bufferSize))
                            if nbuf == nil {
                                return (nil, 0, WebSocket.makeError("out of memory"))
                            }
                            buffer = nbuf
                            buf = buffer+Int(buflen)
                            bufsiz = bufferSize - buflen
                        }
                    }
                }
                return (buffer, buflen, nil)
            }
        }
        class ConnDelegate : NSObject, NSStreamDelegate {
            var stream : Stream!
            @objc private func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
                stream.signal()
            }
        }
        var req : NSMutableURLRequest
        var compression : Compression
        var rd : NSInputStream!
        var wr : NSOutputStream!
        var opened = false
        var inflater : Inflater?
        var deflater : Deflater?
        var delegate = ConnDelegate()
        var mutex = pthread_mutex_t()
        var cond = pthread_cond_t()
        var buffer = [UInt8](count: 1024*16, repeatedValue: 0)
        var subProtocol = ""
        init(request : NSURLRequest, subProtocols : [String], voipEnabled : Bool, compression : Compression){
            pthread_mutex_init(&mutex, nil)
            pthread_cond_init(&cond, nil)
            self.compression = compression
            req = request.mutableCopy() as! NSMutableURLRequest
            req.setValue("websocket", forHTTPHeaderField: "Upgrade")
            req.setValue("Upgrade", forHTTPHeaderField: "Connection")
            req.setValue("SwiftWebSocket", forHTTPHeaderField: "User-Agent")
            req.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
            if req.URL!.port == nil || req.URL!.port!.integerValue == 80 || req.URL!.port!.integerValue == 443  {
                req.setValue(req.URL!.host!, forHTTPHeaderField: "Host")
            } else {
                req.setValue("\(req.URL!.host!):\(req.URL!.port!.integerValue)", forHTTPHeaderField: "Host")
            }
            req.setValue(req.URL!.absoluteString!, forHTTPHeaderField: "Origin")
            if subProtocols.count > 0 {
                req.setValue(";".join(subProtocols), forHTTPHeaderField: "Sec-WebSocket-Protocol")
            }
            var port : Int
            if req.URL!.port != nil {
                port = req.URL!.port!.integerValue
            } else if req.URL!.scheme! == "wss" || req.URL!.scheme! == "https" {
                port = 443
            } else {
                port = 80
            }
            var (rdo, wro) : (NSInputStream?, NSOutputStream?)
            NSStream.getStreamsToHostWithName(self.req.URL!.host!, port: port, inputStream: &rdo, outputStream: &wro)

            (rd, wr) = (rdo!, wro!)
            
            if req.URL!.scheme! == "wss" || req.URL!.scheme! == "https"  {
                rd.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
                wr.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
            }
            if voipEnabled {
                rd.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
                wr.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
            }
            delegate.stream = self
            rd.delegate = delegate
            wr.delegate = delegate
            rd.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
            wr.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        }
        deinit{
            pthread_cond_destroy(&cond)
            pthread_mutex_init(&mutex, nil)
        }
        func signal(){
            pthread_mutex_lock(&mutex)
            pthread_cond_broadcast(&cond)
            pthread_mutex_unlock(&mutex)
        }
        func open() -> NSError? {
            if opened {
                return WebSocket.makeError("already opened")
            }
            opened = true
            rd.open()
            wr.open()
            var path = CFURLCopyPath(self.req.URL!) as! String
            if path == "" {
                path = "/"
            }
            if let q = self.req.URL!.query {
                if q != "" {
                    path += "?" + q
                }
            }
            var reqs = "GET \(path) HTTP/1.1\r\n"
            for key in req.allHTTPHeaderFields!.keys.array {
                if let val = req.valueForHTTPHeaderField(key.description) {
                    reqs += "\(key): \(val)\r\n"
                }
            }
            
            var keyb = [UInt32](count: 4, repeatedValue: 0)
            for var i = 0; i < 4; i++ {
                keyb[i] = arc4random()
            }
            let rkey = NSData(bytes: keyb, length: 16).base64EncodedStringWithOptions(NSDataBase64EncodingOptions(0))
            reqs += "Sec-WebSocket-Key: \(rkey)\r\n"
            
            if compression.on {
                var val = "permessage-deflate"
                if self.compression.noContextTakeover {
                    val += "; client_no_context_takeover; server_no_context_takeover"
                }
                val += "; client_max_window_bits"
                if self.compression.maxWindowBits != 0 {
                    val += "; server_max_window_bits=\(self.compression.maxWindowBits)"
                }
                reqs += "Sec-WebSocket-Extensions: \(val)\r\n"
            }
            reqs += "\r\n"
            var header = [UInt8]()
            for b in reqs.utf8 {
                header += [b]
            }
            var have = header.count
            var sent = 0
            var n = 0
            var err : NSError?
            while have > 0 {
                (n, err) = write(&header+sent, maxLength: have)
                if err != nil {
                    return err
                }
                have -= n
            }

            var needsCompression = false
            var serverMaxWindowBits = WebSocket.defaultMaxWindowBits
            var clientMaxWindowBits = WebSocket.defaultMaxWindowBits
            var key = ""
            var b = UInt8(0)
            for var i = 0;; i++ {
                var lineb : [UInt8] = []
                for ;; {
                    let err = readByte(&b)
                    if err != nil {
                        return err
                    }
                    if b == 0xA {
                        break
                    }
                    lineb += [b]
                }
                var lineo = String(bytes: lineb, encoding: NSUTF8StringEncoding)
                if lineo == nil {
                    return WebSocket.makeError("utf8")
                }
                var trim : (String)->(String) = { (text) in return text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())}
                var eqval : (String,String)->(String) = { (line, del) in return trim(line.componentsSeparatedByString(del)[1]) }
                var line = trim(lineo!)
                if i == 0  {
                    if !line.hasPrefix("HTTP/1.1 101"){
                        return WebSocket.makeError("invalid response (\(line))")
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
                        var parts = value.componentsSeparatedByString(";")
                        for p in parts {
                            var part = trim(p)
                            if part == "permessage-deflate" {
                                needsCompression = true
                            } else if part.hasPrefix("server_max_window_bits="){
                                if let i = eqval(line, "=").toInt() {
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
                    return WebSocket.makeError("invalid server_max_window_bits")
                }
                if serverMaxWindowBits < 8 || serverMaxWindowBits > 15 {
                    return WebSocket.makeError("invalid client_max_window_bits")
                }
                inflater = Inflater(windowBits: serverMaxWindowBits)
                if inflater == nil {
                    return WebSocket.makeError("inflater init")
                }
                deflater = Deflater(windowBits: clientMaxWindowBits, memLevel: 8)
                if deflater == nil {
                    return WebSocket.makeError("deflater init")
                }
            }
            return nil
        }
        func close(code: UInt16 = 1001, reason: String = "Going Away") -> NSError? {
            pthread_mutex_lock(&mutex)
            if !opened {
                pthread_mutex_unlock(&mutex)
                return WebSocket.ErrClosed
            }
            var f = Frame()
            (f.code, f.statusCode, f.utf8.text) = (.Close, code, reason)
            pthread_mutex_unlock(&mutex)
            writeFrame(f)
            pthread_mutex_lock(&mutex)
            opened = false
            wr.close()
            rd.close()
            wr.removeFromRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
            rd.removeFromRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
            wr.delegate = nil
            rd.delegate = nil
            delegate.stream = nil
            pthread_cond_broadcast(&cond)
            pthread_mutex_unlock(&mutex)
            return nil
        }
        @inline(__always) func readByte(inout b : UInt8) -> NSError? {
            for ;; {
                let (n, err) = read(&b, maxLength: 1)
                if err != nil {
                    return err
                }
                if n == 1 {
                    return nil
                }
            }
        }
        func readFrameFragment(var leader : Frame?) -> (f : Frame?, err : NSError?){
            var b = UInt8(0)
            var err : NSError?
            
            err = readByte(&b)
            if err != nil{
                return (nil, err)
            }
            if err != nil{
                return (nil, WebSocket.makeError(err!.localizedDescription, code: .Protocol))
            }
            var inflate = false
            var fin = b >> 7 & 0x1 == 0x1
            var rsv1 = b >> 6 & 0x1 == 0x1
            var rsv2 = b >> 5 & 0x1 == 0x1
            var rsv3 = b >> 4 & 0x1 == 0x1
            if inflater != nil && (rsv1 || (leader != nil && leader!.inflate)) {
                inflate = true
            } else if rsv1 || rsv2 || rsv3 {
                return (nil, WebSocket.makeError("invalid extension", code: .Protocol))
            }
            var code = OpCode.Binary
            if let c = OpCode(rawValue: (b & 0xF)){
                code = c
            } else {
                return (nil, WebSocket.makeError("invalid opcode", code: .Protocol))
            }
            if !fin && code.isControl {
                return (nil, WebSocket.makeError("unfinished control frame", code: .Protocol))
            }
            err = readByte(&b)
            if err != nil{
                return (nil, WebSocket.makeError(err!.localizedDescription, code: .Protocol))
            }
            if b >> 7 & 0x1 == 0x1 {
                return (nil, WebSocket.makeError("server sent masked frame", code: .Protocol))
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
                    return (nil, WebSocket.makeError("invalid payload size for control frame", code: .Protocol))
                }
                len64 = 0
                for var i = bcount-1; i >= 0; i-- {
                    err = readByte(&b)
                    if err != nil{
                        return (nil, WebSocket.makeError(err!.localizedDescription, code: .Protocol))
                    }
                    len64 += Int64(b) << Int64(i*8)
                }
            }
            var len = Int(len64)
            if code == .Continue {
                if code.isControl {
                    return (nil, WebSocket.makeError("control frame cannot have the 'continue' opcode", code: .Protocol))
                }
                if leader == nil {
                    return (nil, WebSocket.makeError("continue frame is missing it's leader", code: .Protocol))
                }
            }
            if code.isControl {
                if leader != nil {
                    leader = nil
                }
                if inflate {
                    return (nil, WebSocket.makeError("control frame cannot be compressed", code: .Protocol))
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
                payload = BoxedBytes()
            }
            if leaderCode == .Close {
                if len == 1 {
                    return (nil, WebSocket.makeError("invalid payload size for close frame", code: .Protocol))
                }
                if len >= 2 {
                    var (b1, b2) = (UInt8(0), UInt8(0))
                    err = readByte(&b1)
                    if err != nil {
                        return (nil, WebSocket.makeError(err!.localizedDescription, code: .Payload))
                    }
                    err = readByte(&b2)
                    if err != nil {
                        return (nil, WebSocket.makeError(err!.localizedDescription, code: .Payload))
                    }
                    statusCode = (UInt16(b1) << 8) + UInt16(b2)
                    len -= 2
                    if statusCode < 1000 || statusCode > 4999  || (statusCode >= 1004 && statusCode <= 1006) || (statusCode >= 1012 && statusCode <= 2999) {
                        return (nil, WebSocket.makeError("invalid status code for close frame", code: .Protocol))
                    }
                }
            }
            
            if leaderCode == .Text || leaderCode == .Close {
                var take = Int(len)
                do {
                    var err : NSError?
                    var n : Int = 0
                    if take > 0 {
                        var c = take
                        if c > buffer.count {
                            c = buffer.count
                        }
                        (n, err) = read(&buffer, maxLength: c)
                        if let err = err {
                            return (nil, WebSocket.makeError(err.localizedDescription, code: .Payload))
                        }
                    }
                    if inflate {
                        var (bytes, bytesLen, nerr) = inflater!.inflate(&buffer, length: n, final: (take - n == 0) && fin)
                        if nerr != nil {
                            return (nil, WebSocket.makeError(nerr!.localizedDescription, code: .Payload))
                        }
                        if bytesLen > 0 {
                            err = utf8.append(bytes, length: bytesLen)
                        }
                    } else {
                        err = utf8.append(&buffer, length: n)
                    }
                    if err != nil{
                        return (nil, WebSocket.makeError(err!.localizedDescription, code: .Payload))
                    }
                    take -= n
                } while take > 0
            } else {
                var start = payload.bytes.count
                if !inflate {
                    payload.bytes += [UInt8](count: len, repeatedValue: 0)
                }
                var take = Int(len)
                do {
                    var err : NSError?
                    var n : Int = 0
                    if inflate {
                        if take > 0 {
                            var c = take
                            if c > buffer.count {
                                c = buffer.count
                            }
                            (n, err) = read(&buffer, maxLength: c)
                            if let err = err {
                                return (nil, WebSocket.makeError(err.localizedDescription, code: .Payload))
                            }
                        }
                        var (bytes, bytesLen, nerr) = inflater!.inflate(&buffer, length: n, final: (take - n == 0) && fin)
                        if nerr != nil {
                            return (nil, WebSocket.makeError(nerr!.localizedDescription, code: .Payload))
                        }
                        if bytesLen > 0 {
                            payload.bytes += [UInt8](count: bytesLen, repeatedValue: 0)
                            memcpy((&payload.bytes)+payload.bytes.count-bytesLen, bytes, bytesLen)
                        }
                    } else if take > 0 {
                        (n, err) = read(&payload.bytes+start, maxLength: take)
                        if let err = err {
                            return (nil, WebSocket.makeError(err.localizedDescription, code: .Payload))
                        }
                        start += n
                    }
                    take -= n
                } while take > 0
            }
            var f = Frame()
            (f.code, f.payload, f.utf8, f.statusCode, f.inflate, f.finished) = (code, payload, utf8, statusCode, inflate, fin)
            return (f, nil)
        }
        @inline(__always) func read(buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> (Int, NSError?) {
            var error : NSError?
            var result = 0
            pthread_mutex_lock(&mutex)
            for ;; {
                if !opened {
                    error = WebSocket.makeError("closed")
                    break
                }
                if rd.hasBytesAvailable {
                    result = rd.read(buffer, maxLength: len)
                    break
                }
                if rd.streamError != nil {
                    error = rd.streamError
                    break
                }
                pthread_cond_wait(&cond, &mutex)
            }
            pthread_mutex_unlock(&mutex)
            return (result, error)
        }
        
        @inline(__always) func write(buffer: UnsafePointer<UInt8>, maxLength len: Int) -> (Int, NSError?) {
            var error : NSError?
            var result = 0
            pthread_mutex_lock(&mutex)
            for ;; {
                if !opened {
                    error = WebSocket.makeError("closed")
                    break
                }
                if wr.hasSpaceAvailable {
                    result = wr.write(buffer, maxLength: len)
                    break
                }
                if wr.streamError != nil {
                    error = wr.streamError
                    break
                }
                pthread_cond_wait(&cond, &mutex)
            }
            pthread_mutex_unlock(&mutex)
            return (result, error)

        }
        
        var savedFrame : Frame?
        func readFrame() -> (f : Frame?, err : NSError?){
            var (f : Frame?, fin : Bool, err : NSError?) = (nil, false, nil)
            if savedFrame != nil {
                (f, fin, err) = (savedFrame, false, nil)
                savedFrame = nil
            } else {
                (f, err) = readFrameFragment(nil)
                if err != nil{
                    return (nil, err)
                }
                fin = f!.finished
            }
            if f!.code == .Continue{
                return (nil, WebSocket.makeError("leader frame cannot be a continue frame", code: .Protocol))
            }
            while !fin {
                var cf : Frame?
                (cf, err) = readFrameFragment(f)
                if err != nil{
                    return (nil, err)
                }
                fin = cf!.finished
                if cf!.code != .Continue {
                    if !cf!.code.isControl {
                        return (nil, WebSocket.makeError("only ping frames can be interlaced with fragments", code: .Protocol))
                    }
                    savedFrame = f
                    return (cf, nil)
                }
            }
            if !f!.utf8.completed {
                return (nil, WebSocket.makeError("incomplete utf8", code: .Payload))
            }
            return (f, nil)
        }
        var head = [UInt8](count: 0xFF, repeatedValue: 0)
        func writeFrame(f : Frame) -> NSError?{
            if !f.finished{
                return WebSocket.makeError("cannot send unfinished frames", code: .Library)
            }
            var hlen = 0
            var b : UInt8 = 0x80
            var deflate = false
            if deflater != nil {
                if f.code == .Binary || f.code == .Text {
                    deflate = true
                    // b |= 0x40
                }
            }
            head[hlen++] = b | f.code.rawValue
            
            
            var payloadBytes : [UInt8]?
            var payloadLen = 0
            if f.utf8.text != "" {
                payloadBytes = UTF8.bytes(f.utf8.text)
            } else {
                payloadBytes = f.payload.bytes
            }
            payloadLen += payloadBytes!.count
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
            var r = arc4random()
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
                        payloadBytes![i-2] ^= maskBytes[i % 4]
                    }
                } else {
                    for var i = 0; i < payloadLen; i++ {
                        payloadBytes![i] ^= maskBytes[i % 4]
                    }
                }
            }
            var written = 0
            while written < hlen {
                let (n, err) = write((&head)+written, maxLength: hlen-written)
                if err != nil{
                     return err
                }
                written += n
            }
            written = 0
            if payloadBytes != nil {
                while written < payloadBytes!.count {
                    let (n, err) = write((&payloadBytes!)+written, maxLength: payloadBytes!.count-written)
                    if err != nil {
                        return err
                    }
                    written += n
                }
            } else {
                while written < f.payload.bytes.count {
                    let (n, err) = write((&f.payload.bytes)+written, maxLength: f.payload.bytes.count-written)
                    if err != nil {
                        return err
                    }
                    written += n
                }
            }
            return nil
        }
        func writeClose(code : UInt16, reason : String) -> NSError?{
            var f = Frame()
            (f.code, f.statusCode, f.utf8.text) = (.Close, code, reason)
            return writeFrame(f)
        }
    }
}