/*
* SwiftWebSocket (websocket.swift)
*
* Copyright (C) Josh Baker. All Rights Reserved.
* Contact: @tidwall, joshbaker77@gmail.com
*
* This software may be modified and distributed under the terms
* of the MIT license.  See the LICENSE file for details.
*
*/

import Foundation

private let windowBufferSize = 0x2000

private class Payload {
    var ptr : UnsafeMutablePointer<UInt8>
    var cap : Int
    var len : Int
    init(){
        len = 0
        cap = windowBufferSize
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
@objc public enum WebSocketReadyState : Int, CustomStringConvertible {
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
    public static var None: WebSocketService { return self.init(0) }
    /// Allow socket to handle VoIP.
    public static var VoIP: WebSocketService { return self.init(1 << 0) }
    /// Allow socket to handle video.
    public static var Video: WebSocketService { return self.init(1 << 1) }
    /// Allow socket to run in background.
    public static var Background: WebSocketService { return self.init(1 << 2) }
    /// Allow socket to handle voice.
    public static var Voice: WebSocketService { return self.init(1 << 3) }
}

private let atEndDetails = "streamStatus.atEnd"
private let timeoutDetails = "The operation couldn’t be completed. Operation timed out"
private let timeoutDuration : CFTimeInterval = 30

public enum WebSocketError : ErrorType, CustomStringConvertible {
    case Memory
    case NeedMoreInput
    case InvalidHeader
    case InvalidAddress
    case Network(String)
    case LibraryError(String)
    case PayloadError(String)
    case ProtocolError(String)
    case InvalidResponse(String)
    case InvalidCompressionOptions(String)
    public var description : String {
        switch self {
        case .Memory: return "Memory"
        case .NeedMoreInput: return "NeedMoreInput"
        case .InvalidAddress: return "InvalidAddress"
        case .InvalidHeader: return "InvalidHeader"
        case let .InvalidResponse(details): return "InvalidResponse(\(details))"
        case let .InvalidCompressionOptions(details): return "InvalidCompressionOptions(\(details))"
        case let .LibraryError(details): return "LibraryError(\(details))"
        case let .ProtocolError(details): return "ProtocolError(\(details))"
        case let .PayloadError(details): return "PayloadError(\(details))"
        case let .Network(details): return "Network(\(details))"
        }
    }
    public var details : String {
        switch self {
        case .InvalidResponse(let details): return details
        case .InvalidCompressionOptions(let details): return details
        case .LibraryError(let details): return details
        case .ProtocolError(let details): return details
        case .PayloadError(let details): return details
        case .Network(let details): return details
        default: return ""
        }
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
                throw WebSocketError.PayloadError("invalid codepoint: invalid byte")
            }
            if byte >> 5 & 0x7 == 0x6 {
                count = 2
            } else if byte >> 4 & 0xF == 0xE {
                count = 3
            } else if byte >> 3 & 0x1F == 0x1E {
                count = 4
            } else {
                throw WebSocketError.PayloadError("invalid codepoint: frames")
            }
            procd = 1
            codepoint = (UInt32(byte) & (0xFF >> count)) << ((count-1) * 6)
            return
        }
        if byte >> 6 & 0x3 != 0x2 {
            throw WebSocketError.PayloadError("invalid codepoint: signature")
        }
        codepoint += UInt32(byte & 0x3F) << ((count-procd-1) * 6)
        if codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
            throw WebSocketError.PayloadError("invalid codepoint: out of bounds")
        }
        procd += 1
        if procd == count {
            if codepoint <= 0x7FF && count > 2 {
                throw WebSocketError.PayloadError("invalid codepoint: overlong")
            }
            if codepoint <= 0xFFFF && count > 3 {
                throw WebSocketError.PayloadError("invalid codepoint: overlong")
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
            for i in 0 ..< length {
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
        for i in 0 ..< length {
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

private class Frame {
    var inflate = false
    var code = OpCode.Continue
    var utf8 = UTF8()
    var payload = Payload()
    var statusCode = UInt16(0)
    var finished = true
    static func makeClose(statusCode: UInt16, reason: String) -> Frame {
        let f = Frame()
        f.code = .Close
        f.statusCode = statusCode
        f.utf8.text = reason
        return f
    }
    func copy() -> Frame {
        let f = Frame()
        f.code = code
        f.utf8.text = utf8.text
        f.payload.buffer = payload.buffer
        f.statusCode = statusCode
        f.finished = finished
        f.inflate = inflate
        return f
    }
}

private class Delegate : NSObject, NSStreamDelegate {
    @objc func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent){
        manager.signal()
    }
}


@_silgen_name("zlibVersion") private func zlibVersion() -> COpaquePointer
@_silgen_name("deflateInit2_") private func deflateInit2(strm : UnsafeMutablePointer<Void>, level : CInt, method : CInt, windowBits : CInt, memLevel : CInt, strategy : CInt, version : COpaquePointer, stream_size : CInt) -> CInt
@_silgen_name("deflateInit_") private func deflateInit(strm : UnsafeMutablePointer<Void>, level : CInt, version : COpaquePointer, stream_size : CInt) -> CInt
@_silgen_name("deflateEnd") private func deflateEnd(strm : UnsafeMutablePointer<Void>) -> CInt
@_silgen_name("deflate") private func deflate(strm : UnsafeMutablePointer<Void>, flush : CInt) -> CInt
@_silgen_name("inflateInit2_") private func inflateInit2(strm : UnsafeMutablePointer<Void>, windowBits : CInt, version : COpaquePointer, stream_size : CInt) -> CInt
@_silgen_name("inflateInit_") private func inflateInit(strm : UnsafeMutablePointer<Void>, version : COpaquePointer, stream_size : CInt) -> CInt
@_silgen_name("inflate") private func inflateG(strm : UnsafeMutablePointer<Void>, flush : CInt) -> CInt
@_silgen_name("inflateEnd") private func inflateEndG(strm : UnsafeMutablePointer<Void>) -> CInt

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
    return WebSocketError.PayloadError("zlib: \(err): \(res)")
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

private class Inflater {
    var windowBits = 0
    var strm = z_stream()
    var tInput = [[UInt8]]()
    var inflateEnd : [UInt8] = [0x00, 0x00, 0xFF, 0xFF]
    var bufferSize = windowBufferSize
    var buffer = UnsafeMutablePointer<UInt8>(malloc(windowBufferSize))
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
        for i in 0 ..< 2{
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
            while true {
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
                        throw WebSocketError.PayloadError("memory")
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
    var bufferSize = windowBufferSize
    var buffer = UnsafeMutablePointer<UInt8>(malloc(windowBufferSize))
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

/// WebSocketDelegate is an Objective-C alternative to WebSocketEvents and is used to delegate the events for the WebSocket connection.
@objc public protocol WebSocketDelegate {
    /// A function to be called when the WebSocket connection's readyState changes to .Open; this indicates that the connection is ready to send and receive data.
    func webSocketOpen()
    /// A function to be called when the WebSocket connection's readyState changes to .Closed.
    func webSocketClose(code: Int, reason: String, wasClean: Bool)
    /// A function to be called when an error occurs.
    func webSocketError(error: NSError)
    /// A function to be called when a message (string) is received from the server.
    optional func webSocketMessageText(text: String)
    /// A function to be called when a message (binary) is received from the server.
    optional func webSocketMessageData(data: NSData)
    /// A function to be called when a pong is received from the server.
    optional func webSocketPong()
    /// A function to be called when the WebSocket process has ended; this event is guarenteed to be called once and can be used as an alternative to the "close" or "error" events.
    optional func webSocketEnd(code: Int, reason: String, wasClean: Bool, error: NSError?)
}

/// WebSocket objects are bidirectional network streams that communicate over HTTP. RFC 6455.
private class InnerWebSocket: Hashable {
    var id : Int
    var mutex = pthread_mutex_t()
    let request : NSURLRequest!
    let subProtocols : [String]!
    var frames : [Frame] = []
    var delegate : Delegate
    var inflater : Inflater!
    var deflater : Deflater!
    var outputBytes : UnsafeMutablePointer<UInt8>
    var outputBytesSize : Int = 0
    var outputBytesStart : Int = 0
    var outputBytesLength : Int = 0
    var inputBytes : UnsafeMutablePointer<UInt8>
    var inputBytesSize : Int = 0
    var inputBytesStart : Int = 0
    var inputBytesLength : Int = 0
    var createdAt = CFAbsoluteTimeGetCurrent()
    var connectionTimeout = false
    var eclose : ()->() = {}
    var _eventQueue : dispatch_queue_t? = dispatch_get_main_queue()
    var _subProtocol = ""
    var _compression = WebSocketCompression()
    var _allowSelfSignedSSL = false
    var _services = WebSocketService.None
    var _event = WebSocketEvents()
    var _eventDelegate: WebSocketDelegate?
    var _binaryType = WebSocketBinaryType.UInt8Array
    var _readyState = WebSocketReadyState.Connecting
    var _networkTimeout = NSTimeInterval(-1)


    var url : String {
        return request.URL!.description
    }
    var subProtocol : String {
        get { return privateSubProtocol }
    }
    var privateSubProtocol : String {
        get { lock(); defer { unlock() }; return _subProtocol }
        set { lock(); defer { unlock() }; _subProtocol = newValue }
    }
    var compression : WebSocketCompression {
        get { lock(); defer { unlock() }; return _compression }
        set { lock(); defer { unlock() }; _compression = newValue }
    }
    var allowSelfSignedSSL : Bool {
        get { lock(); defer { unlock() }; return _allowSelfSignedSSL }
        set { lock(); defer { unlock() }; _allowSelfSignedSSL = newValue }
    }
    var services : WebSocketService {
        get { lock(); defer { unlock() }; return _services }
        set { lock(); defer { unlock() }; _services = newValue }
    }
    var event : WebSocketEvents {
        get { lock(); defer { unlock() }; return _event }
        set { lock(); defer { unlock() }; _event = newValue }
    }
    var eventDelegate : WebSocketDelegate? {
        get { lock(); defer { unlock() }; return _eventDelegate }
        set { lock(); defer { unlock() }; _eventDelegate = newValue }
    }
    var eventQueue : dispatch_queue_t? {
        get { lock(); defer { unlock() }; return _eventQueue; }
        set { lock(); defer { unlock() }; _eventQueue = newValue }
    }
    var binaryType : WebSocketBinaryType {
        get { lock(); defer { unlock() }; return _binaryType }
        set { lock(); defer { unlock() }; _binaryType = newValue }
    }
    var readyState : WebSocketReadyState {
        get { return privateReadyState }
    }
    var privateReadyState : WebSocketReadyState {
        get { lock(); defer { unlock() }; return _readyState }
        set { lock(); defer { unlock() }; _readyState = newValue }
    }

    func copyOpen(request: NSURLRequest, subProtocols : [String] = []) -> InnerWebSocket{
        let ws = InnerWebSocket(request: request, subProtocols: subProtocols, stub: false)
        ws.eclose = eclose
        ws.compression = compression
        ws.allowSelfSignedSSL = allowSelfSignedSSL
        ws.services = services
        ws.event = event
        ws.eventQueue = eventQueue
        ws.binaryType = binaryType
        return ws
    }

    var hashValue: Int { return id }

    init(request: NSURLRequest, subProtocols : [String] = [], stub : Bool = false){
        pthread_mutex_init(&mutex, nil)
        self.id = manager.nextId()
        self.request = request
        self.subProtocols = subProtocols
        self.outputBytes = UnsafeMutablePointer<UInt8>.alloc(windowBufferSize)
        self.outputBytesSize = windowBufferSize
        self.inputBytes = UnsafeMutablePointer<UInt8>.alloc(windowBufferSize)
        self.inputBytesSize = windowBufferSize
        self.delegate = Delegate()
        if stub{
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), manager.queue){
                self
            }
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), manager.queue){
                manager.add(self)
            }
        }
    }
    deinit{
        if outputBytes != nil {
            free(outputBytes)
        }
        if inputBytes != nil {
            free(inputBytes)
        }
        pthread_mutex_init(&mutex, nil)
    }
    @inline(__always) private func lock(){
        pthread_mutex_lock(&mutex)
    }
    @inline(__always) private func unlock(){
        pthread_mutex_unlock(&mutex)
    }

    private var dirty : Bool {
        lock()
        defer { unlock() }
        if exit {
            return false
        }
        if connectionTimeout {
            return true
        }
        if stage != .ReadResponse && stage != .HandleFrames {
            return true
        }
        if rd.streamStatus == .Opening && wr.streamStatus == .Opening {
            return false;
        }
        if rd.streamStatus != .Open || wr.streamStatus != .Open {
            return true
        }
        if rd.streamError != nil || wr.streamError != nil {
            return true
        }
        if rd.hasBytesAvailable || frames.count > 0 || inputBytesLength > 0 {
            return true
        }
        if outputBytesLength > 0 && wr.hasSpaceAvailable{
            return true
        }
        return false
    }
    enum Stage : Int {
        case OpenConn
        case ReadResponse
        case HandleFrames
        case CloseConn
        case End
    }
    var stage = Stage.OpenConn
    var rd : NSInputStream!
    var wr : NSOutputStream!
    var atEnd = false
    var closeCode = UInt16(0)
    var closeReason = ""
    var closeClean = false
    var closeFinal = false
    var finalError : ErrorType?
    var exit = false
    var more = true
    func step(){
        if exit {
            return
        }
        do {
            try stepBuffers(more)
            try stepStreamErrors()
            more = false
            switch stage {
            case .OpenConn:
                try openConn()
                stage = .ReadResponse
            case .ReadResponse:
                try readResponse()
                privateReadyState = .Open
                fire {
                    self.event.open()
                    self.eventDelegate?.webSocketOpen()
                }
                stage = .HandleFrames
            case .HandleFrames:
                try stepOutputFrames()
                if closeFinal {
                    privateReadyState = .Closing
                    stage = .CloseConn
                    return
                }
                let frame = try readFrame()
                switch frame.code {
                case .Text:
                    fire {
                        self.event.message(data: frame.utf8.text)
                        self.eventDelegate?.webSocketMessageText?(frame.utf8.text)
                    }
                case .Binary:
                    fire {
                        switch self.binaryType {
                        case .UInt8Array:
                            self.event.message(data: frame.payload.array)
                        case .NSData:
                            self.event.message(data: frame.payload.nsdata)
                            // The WebSocketDelegate is necessary to add Objective-C compability and it is only possible to send binary data with NSData.
                            self.eventDelegate?.webSocketMessageData?(frame.payload.nsdata)
                        case .UInt8UnsafeBufferPointer:
                            self.event.message(data: frame.payload.buffer)
                        }
                    }
                case .Ping:
                    let nframe = frame.copy()
                    nframe.code = .Pong
                    lock()
                    frames += [nframe]
                    unlock()
                case .Pong:
                    fire {
                        switch self.binaryType {
                        case .UInt8Array:
                            self.event.pong(data: frame.payload.array)
                        case .NSData:
                            self.event.pong(data: frame.payload.nsdata)
                        case .UInt8UnsafeBufferPointer:
                            self.event.pong(data: frame.payload.buffer)
                        }
                        self.eventDelegate?.webSocketPong?()
                    }
                case .Close:
                    lock()
                    frames += [frame]
                    unlock()
                default:
                    break
                }
            case .CloseConn:
                if let error = finalError {
                    self.event.error(error: error)
                    self.eventDelegate?.webSocketError(error as NSError)
                }
                privateReadyState = .Closed
                if rd != nil {
                    closeConn()
                    fire {
                        self.eclose()
                        self.event.close(code: Int(self.closeCode), reason: self.closeReason, wasClean: self.closeFinal)
                        self.eventDelegate?.webSocketClose(Int(self.closeCode), reason: self.closeReason, wasClean: self.closeFinal)
                    }
                }
                stage = .End
            case .End:
                fire {
                    self.event.end(code: Int(self.closeCode), reason: self.closeReason, wasClean: self.closeClean, error: self.finalError)
                    self.eventDelegate?.webSocketEnd?(Int(self.closeCode), reason: self.closeReason, wasClean: self.closeClean, error: self.finalError as? NSError)
                }
                exit = true
                manager.remove(self)
            }
        } catch WebSocketError.NeedMoreInput {
            more = true
        } catch {
            if finalError != nil {
                return
            }
            finalError = error
            if stage == .OpenConn || stage == .ReadResponse {
                stage = .CloseConn
            } else {
                var frame : Frame?
                if let error = error as? WebSocketError{
                    switch error {
                    case .Network(let details):
                        if details == atEndDetails{
                            stage = .CloseConn
                            frame = Frame.makeClose(1006, reason: "Abnormal Closure")
                            atEnd = true
                            finalError = nil
                        }
                    case .ProtocolError:
                        frame = Frame.makeClose(1002, reason: "Protocol error")
                    case .PayloadError:
                        frame = Frame.makeClose(1007, reason: "Payload error")
                    default:
                        break
                    }
                }
                if frame == nil {
                    frame = Frame.makeClose(1006, reason: "Abnormal Closure")
                }
                if let frame = frame {
                    if frame.statusCode == 1007 {
                        self.lock()
                        self.frames = [frame]
                        self.unlock()
                        manager.signal()
                    } else {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), manager.queue){
                            self.lock()
                            self.frames += [frame]
                            self.unlock()
                            manager.signal()
                        }
                    }
                }
            }
        }
    }
    func stepBuffers(more: Bool) throws {
        if rd != nil {
            if stage != .CloseConn && rd.streamStatus == NSStreamStatus.AtEnd  {
                if atEnd {
                    return;
                }
                throw WebSocketError.Network(atEndDetails)
            }
            if more {
                while rd.hasBytesAvailable {
                    var size = inputBytesSize
                    while size-(inputBytesStart+inputBytesLength) < windowBufferSize {
                        size *= 2
                    }
                    if size > inputBytesSize {
                        let ptr = UnsafeMutablePointer<UInt8>(realloc(inputBytes, size))
                        if ptr == nil {
                            throw WebSocketError.Memory
                        }
                        inputBytes = ptr
                        inputBytesSize = size
                    }
                    let n = rd.read(inputBytes+inputBytesStart+inputBytesLength, maxLength: inputBytesSize-inputBytesStart-inputBytesLength)
                    if n > 0 {
                        inputBytesLength += n
                    }
                }
            }
        }
        if wr != nil && wr.hasSpaceAvailable && outputBytesLength > 0 {
            let n = wr.write(outputBytes+outputBytesStart, maxLength: outputBytesLength)
            if n > 0 {
                outputBytesLength -= n
                if outputBytesLength == 0 {
                    outputBytesStart = 0
                } else {
                    outputBytesStart += n
                }
            }
        }
    }
    func stepStreamErrors() throws {
        if finalError == nil {
            if connectionTimeout {
                throw WebSocketError.Network(timeoutDetails)
            }
            if let error = rd?.streamError {
                throw WebSocketError.Network(error.localizedDescription)
            }
            if let error = wr?.streamError {
                throw WebSocketError.Network(error.localizedDescription)
            }
        }
    }
    func stepOutputFrames() throws {
        lock()
        defer {
            frames = []
            unlock()
        }
        if !closeFinal {
            for frame in frames {
                try writeFrame(frame)
                if frame.code == .Close {
                    closeCode = frame.statusCode
                    closeReason = frame.utf8.text
                    closeFinal = true
                    return
                }
            }
        }
    }
    @inline(__always) func fire(block: ()->()){
        if let queue = eventQueue {
            dispatch_sync(queue) {
                block()
            }
        } else {
            block()
        }
    }

    var readStateSaved = false
    var readStateFrame : Frame?
    var readStateFinished = false
    var leaderFrame : Frame?
    func readFrame() throws -> Frame {
        var frame : Frame
        var finished : Bool
        if !readStateSaved {
            if leaderFrame != nil {
                frame = leaderFrame!
                finished = false
                leaderFrame = nil
            } else {
                frame = try readFrameFragment(nil)
                finished = frame.finished
            }
            if frame.code == .Continue{
                throw WebSocketError.ProtocolError("leader frame cannot be a continue frame")
            }
            if !finished {
                readStateSaved = true
                readStateFrame = frame
                readStateFinished = finished
                throw WebSocketError.NeedMoreInput
            }
        } else {
            frame = readStateFrame!
            finished = readStateFinished
            if !finished {
                let cf = try readFrameFragment(frame)
                finished = cf.finished
                if cf.code != .Continue {
                    if !cf.code.isControl {
                        throw WebSocketError.ProtocolError("only ping frames can be interlaced with fragments")
                    }
                    leaderFrame = frame
                    return cf
                }
                if !finished {
                    readStateSaved = true
                    readStateFrame = frame
                    readStateFinished = finished
                    throw WebSocketError.NeedMoreInput
                }
            }
        }
        if !frame.utf8.completed {
            throw WebSocketError.PayloadError("incomplete utf8")
        }
        readStateSaved = false
        readStateFrame = nil
        readStateFinished = false
        return frame
    }

    func closeConn() {
        rd.removeFromRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        wr.removeFromRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        rd.delegate = nil
        wr.delegate = nil
        rd.close()
        wr.close()
    }

    func openConn() throws {
        let req = request.mutableCopy() as! NSMutableURLRequest
        req.setValue("websocket", forHTTPHeaderField: "Upgrade")
        req.setValue("Upgrade", forHTTPHeaderField: "Connection")
        if req.valueForHTTPHeaderField("User-Agent") == nil {
                req.setValue("SwiftWebSocket", forHTTPHeaderField: "User-Agent")
        }
        req.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")

        if req.URL == nil || req.URL!.host == nil{
            throw WebSocketError.InvalidAddress
        }
        if req.URL!.port == nil || req.URL!.port!.integerValue == 80 || req.URL!.port!.integerValue == 443  {
            req.setValue(req.URL!.host!, forHTTPHeaderField: "Host")
        } else {
            req.setValue("\(req.URL!.host!):\(req.URL!.port!.integerValue)", forHTTPHeaderField: "Host")
        }
        req.setValue(req.URL!.absoluteString, forHTTPHeaderField: "Origin")
        if subProtocols.count > 0 {
            req.setValue(subProtocols.joinWithSeparator(";"), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        if req.URL!.scheme != "wss" && req.URL!.scheme != "ws" {
            throw WebSocketError.InvalidAddress
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
		
		let security: TCPConnSecurity
		let port : Int
		if req.URL!.scheme == "wss" {
			port = req.URL!.port?.integerValue ?? 443
			security = .NegoticatedSSL
		} else {
			port = req.URL!.port?.integerValue ?? 80
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
        for key in req.allHTTPHeaderFields!.keys {
            if let val = req.valueForHTTPHeaderField(key) {
                reqs += "\(key): \(val)\r\n"
            }
        }
        var keyb = [UInt32](count: 4, repeatedValue: 0)
        for i in 0 ..< 4 {
            keyb[i] = arc4random()
        }
        let rkey = NSData(bytes: keyb, length: 16).base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
        reqs += "Sec-WebSocket-Key: \(rkey)\r\n"
        reqs += "\r\n"
        var header = [UInt8]()
        for b in reqs.utf8 {
            header += [b]
        }
        let addr = ["\(req.URL!.host!)", "\(port)"]
        if addr.count != 2 || Int(addr[1]) == nil {
            throw WebSocketError.InvalidAddress
        }

        var (rdo, wro) : (NSInputStream?, NSOutputStream?)
        var readStream:  Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, addr[0], UInt32(Int(addr[1])!), &readStream, &writeStream);
        rdo = readStream!.takeRetainedValue()
        wro = writeStream!.takeRetainedValue()
        (rd, wr) = (rdo!, wro!)
        rd.setProperty(security.level, forKey: NSStreamSocketSecurityLevelKey)
		wr.setProperty(security.level, forKey: NSStreamSocketSecurityLevelKey)
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
        if allowSelfSignedSSL {
            let prop: Dictionary<NSObject,NSObject> = [kCFStreamSSLPeerName: kCFNull, kCFStreamSSLValidatesCertificateChain: NSNumber(bool: false)]
            rd.setProperty(prop, forKey: kCFStreamPropertySSLSettings as String)
            wr.setProperty(prop, forKey: kCFStreamPropertySSLSettings as String)
        }
        rd.delegate = delegate
        wr.delegate = delegate
        rd.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        wr.scheduleInRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
        rd.open()
        wr.open()
        try write(header, length: header.count)
    }

    func write(bytes: UnsafePointer<UInt8>, length: Int) throws {
        if outputBytesStart+outputBytesLength+length > outputBytesSize {
            var size = outputBytesSize
            while outputBytesStart+outputBytesLength+length > size {
                size *= 2
            }
            let ptr = UnsafeMutablePointer<UInt8>(realloc(outputBytes, size))
            if ptr == nil {
                throw WebSocketError.Memory
            }
            outputBytes = ptr
            outputBytesSize = size
        }
        memcpy(outputBytes+outputBytesStart+outputBytesLength, bytes, length)
        outputBytesLength += length
    }

    func readResponse() throws {
        let end : [UInt8] = [ 0x0D, 0x0A, 0x0D, 0x0A ]
        let ptr = UnsafeMutablePointer<UInt8>(memmem(inputBytes+inputBytesStart, inputBytesLength, end, 4))
        if ptr == nil {
            throw WebSocketError.NeedMoreInput
        }
        let buffer = inputBytes+inputBytesStart
        let bufferCount = ptr-(inputBytes+inputBytesStart)
        let string = NSString(bytesNoCopy: buffer, length: bufferCount, encoding: NSUTF8StringEncoding, freeWhenDone: false) as? String
        if string == nil {
            throw WebSocketError.InvalidHeader
        }
        let header = string!
        var needsCompression = false
        var serverMaxWindowBits = 15
        let clientMaxWindowBits = 15
        var key = ""
        let trim : (String)->(String) = { (text) in return text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())}
        let eqval : (String,String)->(String) = { (line, del) in return trim(line.componentsSeparatedByString(del)[1]) }
        let lines = header.componentsSeparatedByString("\r\n")
        for i in 0 ..< lines.count {
            let line = trim(lines[i])
            if i == 0  {
                if !line.hasPrefix("HTTP/1.1 101"){
                    throw WebSocketError.InvalidResponse(line)
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
                
                switch key.lowercaseString {
                case "sec-websocket-subprotocol":
                    privateSubProtocol = value
                case "sec-websocket-extensions":
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
        }
        if needsCompression {
            if serverMaxWindowBits < 8 || serverMaxWindowBits > 15 {
                throw WebSocketError.InvalidCompressionOptions("server_max_window_bits")
            }
            if serverMaxWindowBits < 8 || serverMaxWindowBits > 15 {
                throw WebSocketError.InvalidCompressionOptions("client_max_window_bits")
            }
            inflater = Inflater(windowBits: serverMaxWindowBits)
            if inflater == nil {
                throw WebSocketError.InvalidCompressionOptions("inflater init")
            }
            deflater = Deflater(windowBits: clientMaxWindowBits, memLevel: 8)
            if deflater == nil {
                throw WebSocketError.InvalidCompressionOptions("deflater init")
            }
        }
        inputBytesLength -= bufferCount+4
        if inputBytesLength == 0 {
            inputBytesStart = 0
        } else {
            inputBytesStart += bufferCount+4
        }
    }

    class ByteReader {
        var start : UnsafePointer<UInt8>
        var end : UnsafePointer<UInt8>
        var bytes : UnsafePointer<UInt8>
        init(bytes: UnsafePointer<UInt8>, length: Int){
            self.bytes = bytes
            start = bytes
            end = bytes+length
        }
        func readByte() throws -> UInt8 {
            if bytes >= end {
                throw WebSocketError.NeedMoreInput
            }
            let b = bytes.memory
            bytes += 1
            return b
        }
        var length : Int {
            return end - bytes
        }
        var position : Int {
            get {
                return bytes - start
            }
            set {
                bytes = start + newValue
            }
        }
    }

    var fragStateSaved = false
    var fragStatePosition = 0
    var fragStateInflate = false
    var fragStateLen = 0
    var fragStateFin = false
    var fragStateCode = OpCode.Continue
    var fragStateLeaderCode = OpCode.Continue
    var fragStateUTF8 = UTF8()
    var fragStatePayload = Payload()
    var fragStateStatusCode = UInt16(0)
    var fragStateHeaderLen = 0
    var buffer = [UInt8](count: windowBufferSize, repeatedValue: 0)
    var reusedPayload = Payload()
    func readFrameFragment(leader : Frame?) throws -> Frame {
        var inflate : Bool
        var len : Int
        var fin = false
        var code : OpCode
        var leaderCode : OpCode
        var utf8 : UTF8
        var payload : Payload
        var statusCode : UInt16
        var headerLen : Int
        var leader = leader

        let reader = ByteReader(bytes: inputBytes+inputBytesStart, length: inputBytesLength)
        if fragStateSaved {
            // load state
            reader.position += fragStatePosition
            inflate = fragStateInflate
            len = fragStateLen
            fin = fragStateFin
            code = fragStateCode
            leaderCode = fragStateLeaderCode
            utf8 = fragStateUTF8
            payload = fragStatePayload
            statusCode = fragStateStatusCode
            headerLen = fragStateHeaderLen
            fragStateSaved = false
        } else {
            var b = try reader.readByte()
            fin = b >> 7 & 0x1 == 0x1
            let rsv1 = b >> 6 & 0x1 == 0x1
            let rsv2 = b >> 5 & 0x1 == 0x1
            let rsv3 = b >> 4 & 0x1 == 0x1
            if inflater != nil && (rsv1 || (leader != nil && leader!.inflate)) {
                inflate = true
            } else if rsv1 || rsv2 || rsv3 {
                throw WebSocketError.ProtocolError("invalid extension")
            } else {
                inflate = false
            }
            code = OpCode.Binary
            if let c = OpCode(rawValue: (b & 0xF)){
                code = c
            } else {
                throw WebSocketError.ProtocolError("invalid opcode")
            }
            if !fin && code.isControl {
                throw WebSocketError.ProtocolError("unfinished control frame")
            }
            b = try reader.readByte()
            if b >> 7 & 0x1 == 0x1 {
                throw WebSocketError.ProtocolError("server sent masked frame")
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
                    throw WebSocketError.ProtocolError("invalid payload size for control frame")
                }
                len64 = 0
                var i = bcount-1
                while i >= 0 {
                    b = try reader.readByte()
                    len64 += Int64(b) << Int64(i*8)
                    i -= 1
                }
            }
            len = Int(len64)
            if code == .Continue {
                if code.isControl {
                    throw WebSocketError.ProtocolError("control frame cannot have the 'continue' opcode")
                }
                if leader == nil {
                    throw WebSocketError.ProtocolError("continue frame is missing it's leader")
                }
            }
            if code.isControl {
                if leader != nil {
                    leader = nil
                }
                if inflate {
                    throw WebSocketError.ProtocolError("control frame cannot be compressed")
                }
            }
            statusCode = 0
            if leader != nil {
                leaderCode = leader!.code
                utf8 = leader!.utf8
                payload = leader!.payload
            } else {
                leaderCode = code
                utf8 = UTF8()
                payload = reusedPayload
                payload.count = 0
            }
            if leaderCode == .Close {
                if len == 1 {
                    throw WebSocketError.ProtocolError("invalid payload size for close frame")
                }
                if len >= 2 {
                    let b1 = try reader.readByte()
                    let b2 = try reader.readByte()
                    statusCode = (UInt16(b1) << 8) + UInt16(b2)
                    len -= 2
                    if statusCode < 1000 || statusCode > 4999  || (statusCode >= 1004 && statusCode <= 1006) || (statusCode >= 1012 && statusCode <= 2999) {
                        throw WebSocketError.ProtocolError("invalid status code for close frame")
                    }
                }
            }
            headerLen = reader.position
        }

        let rlen : Int
        let rfin : Bool
        let chopped : Bool
        if reader.length+reader.position-headerLen < len {
            rlen = reader.length
            rfin = false
            chopped = true
        } else {
            rlen = len-reader.position+headerLen
            rfin = fin
            chopped = false
        }
        let bytes : UnsafeMutablePointer<UInt8>
        let bytesLen : Int
        if inflate {
            (bytes, bytesLen) = try inflater!.inflate(reader.bytes, length: rlen, final: rfin)
        } else {
            (bytes, bytesLen) = (UnsafeMutablePointer<UInt8>(reader.bytes), rlen)
        }
        reader.bytes += rlen

        if leaderCode == .Text || leaderCode == .Close {
            try utf8.append(bytes, length: bytesLen)
        } else {
            payload.append(bytes, length: bytesLen)
        }

        if chopped {
            // save state
            fragStateHeaderLen = headerLen
            fragStateStatusCode = statusCode
            fragStatePayload = payload
            fragStateUTF8 = utf8
            fragStateLeaderCode = leaderCode
            fragStateCode = code
            fragStateFin = fin
            fragStateLen = len
            fragStateInflate = inflate
            fragStatePosition = reader.position
            fragStateSaved = true
            throw WebSocketError.NeedMoreInput
        }

        inputBytesLength -= reader.position
        if inputBytesLength == 0 {
            inputBytesStart = 0
        } else {
            inputBytesStart += reader.position
        }

        let f = Frame()
        (f.code, f.payload, f.utf8, f.statusCode, f.inflate, f.finished) = (code, payload, utf8, statusCode, inflate, fin)
        return f
    }

    var head = [UInt8](count: 0xFF, repeatedValue: 0)
    func writeFrame(f : Frame) throws {
        if !f.finished{
            throw WebSocketError.LibraryError("cannot send unfinished frames")
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
        head[hlen] = b | f.code.rawValue
        hlen += 1
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
            head[hlen] = 0x80 | UInt8(payloadLen)
            hlen += 1
        } else if payloadLen <= 0xFFFF {
            head[hlen] = 0x80 | 126
            hlen += 1
            var i = 1
            while i >= 0 {
                head[hlen] = UInt8((UInt16(payloadLen) >> UInt16(i*8)) & 0xFF)
                hlen += 1
                i -= 1
            }
        } else {
            head[hlen] = UInt8((0x1 << 7) + 127)
            hlen += 1
            var i = 7
            while i >= 0 {
                head[hlen] = UInt8((UInt64(payloadLen) >> UInt64(i*8)) & 0xFF)
                hlen += 1
                i -= 1
            }
        }
        let r = arc4random()
        var maskBytes : [UInt8] = [UInt8(r >> 0 & 0xFF), UInt8(r >> 8 & 0xFF), UInt8(r >> 16 & 0xFF), UInt8(r >> 24 & 0xFF)]
        for i in 0 ..< 4 {
            head[hlen] = maskBytes[i]
            hlen += 1
        }
        if payloadLen > 0 {
            if usingStatusCode {
                var sc = [UInt8(f.statusCode >> 8 & 0xFF), UInt8(f.statusCode >> 0 & 0xFF)]
                for i in 0 ..< 2 {
                    sc[i] ^= maskBytes[i % 4]
                }
                head[hlen] = sc[0]
                hlen += 1
                head[hlen] = sc[1]
                hlen += 1
                for i in 2 ..< payloadLen {
                    payloadBytes[i-2] ^= maskBytes[i % 4]
                }
            } else {
                for i in 0 ..< payloadLen {
                    payloadBytes[i] ^= maskBytes[i % 4]
                }
            }
        }
        try write(head, length: hlen)
        try write(payloadBytes, length: payloadBytes.count)
    }
    func close(code : Int = 1000, reason : String = "Normal Closure") {
        let f = Frame()
        f.code = .Close
        f.statusCode = UInt16(truncatingBitPattern: code)
        f.utf8.text = reason
        sendFrame(f)
    }
    func sendFrame(f : Frame) {
        lock()
        frames += [f]
        unlock()
        manager.signal()
    }
    func send(message : Any) {
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
    func ping() {
        let f = Frame()
        f.code = .Ping
        sendFrame(f)
    }
    func ping(message : Any){
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
private func ==(lhs: InnerWebSocket, rhs: InnerWebSocket) -> Bool {
    return lhs.id == rhs.id
}

private enum TCPConnSecurity {
    case None
    case NegoticatedSSL
	
	var level: String {
		switch self {
		case .None: return NSStreamSocketSecurityLevelNone
		case .NegoticatedSSL: return NSStreamSocketSecurityLevelNegotiatedSSL
		}
	}
}

// Manager class is used to minimize the number of dispatches and cycle through network events
// using fewers threads. Helps tremendously with lowing system resources when many conncurrent
// sockets are opened.
private class Manager {
    var queue = dispatch_queue_create("SwiftWebSocketInstance", nil)
    var once = dispatch_once_t()
    var mutex = pthread_mutex_t()
    var cond = pthread_cond_t()
    var websockets = Set<InnerWebSocket>()
    var _nextId = 0
    init(){
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&cond, nil)
        dispatch_async(dispatch_queue_create("SwiftWebSocket", nil)) {
            var wss : [InnerWebSocket] = []
            while true {
                var wait = true
                wss.removeAll()
                pthread_mutex_lock(&self.mutex)
                for ws in self.websockets {
                    wss.append(ws)
                }
                for ws in wss {
                    self.checkForConnectionTimeout(ws)
                    if ws.dirty {
                        pthread_mutex_unlock(&self.mutex)
                        ws.step()
                        pthread_mutex_lock(&self.mutex)
                        wait = false
                    }
                }
                if wait {
                    self.wait(250)
                }
                pthread_mutex_unlock(&self.mutex)
            }
        }
    }
    func checkForConnectionTimeout(ws : InnerWebSocket) {
        if ws.rd != nil && ws.wr != nil && (ws.rd.streamStatus == .Opening || ws.wr.streamStatus == .Opening) {
            let age = CFAbsoluteTimeGetCurrent() - ws.createdAt
            if age >= timeoutDuration {
                ws.connectionTimeout = true
            }
        }
    }
    func wait(timeInMs : Int) -> Int32 {
        var ts = timespec()
        var tv = timeval()
        gettimeofday(&tv, nil)
        ts.tv_sec = time(nil) + timeInMs / 1000;
        let v1 = Int(tv.tv_usec * 1000)
        let v2 = Int(1000 * 1000 * Int(timeInMs % 1000))
        ts.tv_nsec = v1 + v2;
        ts.tv_sec += ts.tv_nsec / (1000 * 1000 * 1000);
        ts.tv_nsec %= (1000 * 1000 * 1000);
        return pthread_cond_timedwait(&self.cond, &self.mutex, &ts)
    }
    func signal(){
        pthread_mutex_lock(&mutex)
        pthread_cond_signal(&cond)
        pthread_mutex_unlock(&mutex)
    }
    func add(websocket: InnerWebSocket) {
        pthread_mutex_lock(&mutex)
        websockets.insert(websocket)
        pthread_cond_signal(&cond)
        pthread_mutex_unlock(&mutex)
    }
    func remove(websocket: InnerWebSocket) {
        pthread_mutex_lock(&mutex)
        websockets.remove(websocket)
        pthread_cond_signal(&cond)
        pthread_mutex_unlock(&mutex)
    }
    func nextId() -> Int {
        pthread_mutex_lock(&mutex)
        defer { pthread_mutex_unlock(&mutex) }
        _nextId += 1
        return _nextId
    }
}

private let manager = Manager()

/// WebSocket objects are bidirectional network streams that communicate over HTTP. RFC 6455.
public class WebSocket: NSObject {
    private var ws: InnerWebSocket
    private var id = manager.nextId()
    private var opened: Bool
    public override var hashValue: Int { return id }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    public convenience init(_ url: String){
        self.init(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: [])
    }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    public convenience init(url: NSURL){
        self.init(request: NSURLRequest(URL: url), subProtocols: [])
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
        opened = true
        ws = InnerWebSocket(request: request, subProtocols: subProtocols, stub: false)
    }
    /// Create a WebSocket object with a deferred connection; the connection is not opened until the .open() method is called.
    public override init(){
        opened = false
        ws = InnerWebSocket(request: NSURLRequest(), subProtocols: [], stub: true)
        super.init()
        ws.eclose = {
            self.opened = false
        }
    }
    /// The URL as resolved by the constructor. This is always an absolute URL. Read only.
    public var url : String{ return ws.url }
    /// A string indicating the name of the sub-protocol the server selected; this will be one of the strings specified in the protocols parameter when creating the WebSocket object.
    public var subProtocol : String{ return ws.subProtocol }
    /// The compression options of the WebSocket.
    public var compression : WebSocketCompression{
        get { return ws.compression }
        set { ws.compression = newValue }
    }
    /// Allow for Self-Signed SSL Certificates. Default is false.
    public var allowSelfSignedSSL : Bool{
        get { return ws.allowSelfSignedSSL }
        set { ws.allowSelfSignedSSL = newValue }
    }
    /// The services of the WebSocket.
    public var services : WebSocketService{
        get { return ws.services }
        set { ws.services = newValue }
    }
    /// The events of the WebSocket.
    public var event : WebSocketEvents{
        get { return ws.event }
        set { ws.event = newValue }
    }
    /// The queue for firing off events. default is main_queue
    public var eventQueue : dispatch_queue_t?{
        get { return ws.eventQueue }
        set { ws.eventQueue = newValue }
    }
    /// A WebSocketBinaryType value indicating the type of binary data being transmitted by the connection. Default is .UInt8Array.
    public var binaryType : WebSocketBinaryType{
        get { return ws.binaryType }
        set { ws.binaryType = newValue }
    }
    /// The current state of the connection; this is one of the WebSocketReadyState constants. Read only.
    public var readyState : WebSocketReadyState{
        return ws.readyState
    }
    /// Opens a deferred or closed WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    public func open(url: String){
        open(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: [])
    }
    /// Opens a deferred or closed WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    public func open(nsurl url: NSURL){
        open(request: NSURLRequest(URL: url), subProtocols: [])
    }
    /// Opens a deferred or closed WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a list of protocols.
    public func open(url: String, subProtocols : [String]){
        open(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: subProtocols)
    }
    /// Opens a deferred or closed WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a protocol.
    public func open(url: String, subProtocol : String){
        open(request: NSURLRequest(URL: NSURL(string: url)!), subProtocols: [subProtocol])
    }
    /// Opens a deferred or closed WebSocket connection from an NSURLRequest; Also include a list of protocols.
    public func open(request request: NSURLRequest, subProtocols : [String] = []){
        if opened{
            return
        }
        opened = true
        ws = ws.copyOpen(request, subProtocols: subProtocols)
    }
    /// Opens a closed WebSocket connection from an NSURLRequest; Uses the same request and protocols as previously closed WebSocket
    public func open(){
        open(request: ws.request, subProtocols: ws.subProtocols)
    }
    /**
     Closes the WebSocket connection or connection attempt, if any. If the connection is already closed or in the state of closing, this method does nothing.

     :param: code An integer indicating the status code explaining why the connection is being closed. If this parameter is not specified, a default value of 1000 (indicating a normal closure) is assumed.
     :param: reason A human-readable string explaining why the connection is closing. This string must be no longer than 123 bytes of UTF-8 text (not characters).
     */
    public func close(code : Int = 1000, reason : String = "Normal Closure"){
        if !opened{
            return
        }
        opened = false
        ws.close(code, reason: reason)
    }
    /**
     Transmits message to the server over the WebSocket connection.

     :param: message The message to be sent to the server.
     */
    public func send(message : Any){
        if !opened{
            return
        }
        ws.send(message)
    }
    /**
     Transmits a ping to the server over the WebSocket connection.

     :param: optional message The data to be sent to the server.
     */
    public func ping(message : Any){
        if !opened{
            return
        }
        ws.ping(message)
    }
    /**
     Transmits a ping to the server over the WebSocket connection.
     */
    public func ping(){
        if !opened{
            return
        }
        ws.ping()
    }
}

public func ==(lhs: WebSocket, rhs: WebSocket) -> Bool {
    return lhs.id == rhs.id
}

extension WebSocket {
    /// The events of the WebSocket using a delegate.
    public var delegate : WebSocketDelegate? {
        get { return ws.eventDelegate }
        set { ws.eventDelegate = newValue }
    }
    /**
     Transmits message to the server over the WebSocket connection.

     :param: text The message (string) to be sent to the server.
     */
    @objc
    public func send(text text: String){
        send(text)
    }
    /**
     Transmits message to the server over the WebSocket connection.

     :param: data The message (binary) to be sent to the server.
     */
    @objc
    public func send(data data: NSData){
        send(data)
    }
}
