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
    var ptr : UnsafeMutableRawPointer
    var cap : Int
    var len : Int
    init(){
        len = 0
        cap = windowBufferSize
        ptr = malloc(cap)
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
                ptr = realloc(ptr, cap)
            }
            len = newValue
        }
    }
    func append(_ bytes: UnsafePointer<UInt8>, length: Int){
        let prevLen = len
        count = len+length
        memcpy(ptr+prevLen, bytes, length)
    }
    var array : [UInt8] {
        get {
            var array = [UInt8](repeating: 0, count: count)
            memcpy(&array, ptr, count)
            return array
        }
        set {
            count = 0
            append(newValue, length: newValue.count)
        }
    }
    var nsdata : Data {
        get {
            return Data(bytes: ptr.assumingMemoryBound(to: UInt8.self), count: count)
        }
        set {
            count = 0
            append((newValue as NSData).bytes.bindMemory(to: UInt8.self, capacity: newValue.count), length: newValue.count)
        }
    }
    var buffer : UnsafeBufferPointer<UInt8> {
        get {
            return UnsafeBufferPointer<UInt8>(start: ptr.assumingMemoryBound(to: UInt8.self), count: count)
        }
        set {
            count = 0
            append(newValue.baseAddress!, length: newValue.count)
        }
    }
}

private enum OpCode : UInt8, CustomStringConvertible {
    case `continue` = 0x0, text = 0x1, binary = 0x2, close = 0x8, ping = 0x9, pong = 0xA
    var isControl : Bool {
        switch self {
        case .close, .ping, .pong:
            return true
        default:
            return false
        }
    }
    var description : String {
        switch self {
        case .`continue`: return "Continue"
        case .text: return "Text"
        case .binary: return "Binary"
        case .close: return "Close"
        case .ping: return "Ping"
        case .pong: return "Pong"
        }
    }
}

/// The WebSocketEvents struct is used by the events property and manages the events for the WebSocket connection.
public struct WebSocketEvents {
    /// An event to be called when the WebSocket connection's readyState changes to .Open; this indicates that the connection is ready to send and receive data.
    public var open : ()->() = {}
    /// An event to be called when the WebSocket connection's readyState changes to .Closed.
    public var close : (_ code : Int, _ reason : String, _ wasClean : Bool)->() = {(code, reason, wasClean) in}
    /// An event to be called when an error occurs.
    public var error : (_ error : Error)->() = {(error) in}
    /// An event to be called when a message is received from the server.
    public var message : (_ data : Any)->() = {(data) in}
    /// An event to be called when a pong is received from the server.
    public var pong : (_ data : Any)->() = {(data) in}
    /// An event to be called when the WebSocket process has ended; this event is guarenteed to be called once and can be used as an alternative to the "close" or "error" events.
    public var end : (_ code : Int, _ reason : String, _ wasClean : Bool, _ error : Error?)->() = {(code, reason, wasClean, error) in}
}

/// The WebSocketBinaryType enum is used by the binaryType property and indicates the type of binary data being transmitted by the WebSocket connection.
public enum WebSocketBinaryType : CustomStringConvertible {
    /// The WebSocket should transmit [UInt8] objects.
    case uInt8Array
    /// The WebSocket should transmit NSData objects.
    case nsData
    /// The WebSocket should transmit UnsafeBufferPointer<UInt8> objects. This buffer is only valid during the scope of the message event. Use at your own risk.
    case uInt8UnsafeBufferPointer
    public var description : String {
        switch self {
        case .uInt8Array: return "UInt8Array"
        case .nsData: return "NSData"
        case .uInt8UnsafeBufferPointer: return "UInt8UnsafeBufferPointer"
        }
    }
}

/// The WebSocketReadyState enum is used by the readyState property to describe the status of the WebSocket connection.
@objc public enum WebSocketReadyState : Int, CustomStringConvertible {
    /// The connection is not yet open.
    case connecting = 0
    /// The connection is open and ready to communicate.
    case open = 1
    /// The connection is in the process of closing.
    case closing = 2
    /// The connection is closed or couldn't be opened.
    case closed = 3
    fileprivate var isClosed : Bool {
        switch self {
        case .closing, .closed:
            return true
        default:
            return false
        }
    }
    /// Returns a string that represents the ReadyState value.
    public var description : String {
        switch self {
        case .connecting: return "Connecting"
        case .open: return "Open"
        case .closing: return "Closing"
        case .closed: return "Closed"
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
public struct WebSocketService :  OptionSet {
    public typealias RawValue = UInt
    var value: UInt = 0
    init(_ value: UInt) { self.value = value }
    public init(rawValue value: UInt) { self.value = value }
    public init(nilLiteral: ()) { self.value = 0 }
    public static var allZeros: WebSocketService { return self.init(0) }
    static func fromMask(_ raw: UInt) -> WebSocketService { return self.init(raw) }
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

public enum WebSocketError : Error, CustomStringConvertible {
    case memory
    case needMoreInput
    case invalidHeader
    case invalidAddress
    case network(String)
    case libraryError(String)
    case payloadError(String)
    case protocolError(String)
    case invalidResponse(String)
    case invalidCompressionOptions(String)
    public var description : String {
        switch self {
        case .memory: return "Memory"
        case .needMoreInput: return "NeedMoreInput"
        case .invalidAddress: return "InvalidAddress"
        case .invalidHeader: return "InvalidHeader"
        case let .invalidResponse(details): return "InvalidResponse(\(details))"
        case let .invalidCompressionOptions(details): return "InvalidCompressionOptions(\(details))"
        case let .libraryError(details): return "LibraryError(\(details))"
        case let .protocolError(details): return "ProtocolError(\(details))"
        case let .payloadError(details): return "PayloadError(\(details))"
        case let .network(details): return "Network(\(details))"
        }
    }
    public var details : String {
        switch self {
        case .invalidResponse(let details): return details
        case .invalidCompressionOptions(let details): return details
        case .libraryError(let details): return details
        case .protocolError(let details): return details
        case .payloadError(let details): return details
        case .network(let details): return details
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
    func append(_ byte : UInt8) throws {
        if count == 0 {
            if byte <= 0x7F {
                text.append(String(UnicodeScalar(byte)))
                return
            }
            if byte == 0xC0 || byte == 0xC1 {
                throw WebSocketError.payloadError("invalid codepoint: invalid byte")
            }
            if byte >> 5 & 0x7 == 0x6 {
                count = 2
            } else if byte >> 4 & 0xF == 0xE {
                count = 3
            } else if byte >> 3 & 0x1F == 0x1E {
                count = 4
            } else {
                throw WebSocketError.payloadError("invalid codepoint: frames")
            }
            procd = 1
            codepoint = (UInt32(byte) & (0xFF >> count)) << ((count-1) * 6)
            return
        }
        if byte >> 6 & 0x3 != 0x2 {
            throw WebSocketError.payloadError("invalid codepoint: signature")
        }
        codepoint += UInt32(byte & 0x3F) << ((count-procd-1) * 6)
        if codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF) {
            throw WebSocketError.payloadError("invalid codepoint: out of bounds")
        }
        procd += 1
        if procd == count {
            if codepoint <= 0x7FF && count > 2 {
                throw WebSocketError.payloadError("invalid codepoint: overlong")
            }
            if codepoint <= 0xFFFF && count > 3 {
                throw WebSocketError.payloadError("invalid codepoint: overlong")
            }
            procd = 0
            count = 0
            text.append(String.init(describing: UnicodeScalar(codepoint)!))
        }
        return
    }
    func append(_ bytes : UnsafePointer<UInt8>, length : Int) throws {
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
                text += NSString(bytes: bytes, length: length, encoding: String.Encoding.ascii.rawValue)! as String
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
    static func bytes(_ string : String) -> [UInt8]{
        let data = string.data(using: String.Encoding.utf8)!
        return [UInt8](UnsafeBufferPointer<UInt8>(start: (data as NSData).bytes.bindMemory(to: UInt8.self, capacity: data.count), count: data.count))
    }
    static func string(_ bytes : [UInt8]) -> String{
        if let str = NSString(bytes: bytes, length: bytes.count, encoding: String.Encoding.utf8.rawValue) {
            return str as String
        }
        return ""
    }
}

private class Frame {
    var inflate = false
    var code = OpCode.continue
    var utf8 = UTF8()
    var payload = Payload()
    var statusCode = UInt16(0)
    var finished = true
    static func makeClose(_ statusCode: UInt16, reason: String) -> Frame {
        let f = Frame()
        f.code = .close
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

private class Delegate : NSObject, StreamDelegate {
    @objc func stream(_ aStream: Stream, handle eventCode: Stream.Event){
        manager.signal()
    }
}


@_silgen_name("zlibVersion") private func zlibVersion() -> OpaquePointer
@_silgen_name("deflateInit2_") private func deflateInit2(_ strm : UnsafeMutableRawPointer, level : CInt, method : CInt, windowBits : CInt, memLevel : CInt, strategy : CInt, version : OpaquePointer, stream_size : CInt) -> CInt
@_silgen_name("deflateInit_") private func deflateInit(_ strm : UnsafeMutableRawPointer, level : CInt, version : OpaquePointer, stream_size : CInt) -> CInt
@_silgen_name("deflateEnd") private func deflateEnd(_ strm : UnsafeMutableRawPointer) -> CInt
@_silgen_name("deflate") private func deflate(_ strm : UnsafeMutableRawPointer, flush : CInt) -> CInt
@_silgen_name("inflateInit2_") private func inflateInit2(_ strm : UnsafeMutableRawPointer, windowBits : CInt, version : OpaquePointer, stream_size : CInt) -> CInt
@_silgen_name("inflateInit_") private func inflateInit(_ strm : UnsafeMutableRawPointer, version : OpaquePointer, stream_size : CInt) -> CInt
@_silgen_name("inflate") private func inflateG(_ strm : UnsafeMutableRawPointer, flush : CInt) -> CInt
@_silgen_name("inflateEnd") private func inflateEndG(_ strm : UnsafeMutableRawPointer) -> CInt

private func zerror(_ res : CInt) -> Error? {
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
    return WebSocketError.payloadError("zlib: \(err): \(res)")
}

private struct z_stream {
    var next_in : UnsafePointer<UInt8>? = nil
    var avail_in : CUnsignedInt = 0
    var total_in : CUnsignedLong = 0

    var next_out : UnsafeMutablePointer<UInt8>? = nil
    var avail_out : CUnsignedInt = 0
    var total_out : CUnsignedLong = 0

    var msg : UnsafePointer<CChar>? = nil
    var state : OpaquePointer? = nil

    var zalloc : OpaquePointer? = nil
    var zfree : OpaquePointer? = nil
    var opaque : OpaquePointer? = nil

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
    var buffer = malloc(windowBufferSize)
    init?(windowBits : Int){
        if buffer == nil {
            return nil
        }
        self.windowBits = windowBits
        let ret = inflateInit2(&strm, windowBits: -CInt(windowBits), version: zlibVersion(), stream_size: CInt(MemoryLayout<z_stream>.size))
        if ret != 0 {
            return nil
        }
    }
    deinit{
        _ = inflateEndG(&strm)
        free(buffer)
    }
    func inflate(_ bufin : UnsafePointer<UInt8>, length : Int, final : Bool) throws -> (p : UnsafeMutablePointer<UInt8>, n : Int){
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
                strm.next_out = buf?.assumingMemoryBound(to: UInt8.self)
                _ = inflateG(&strm, flush: 0)
                let have = bufsiz - Int(strm.avail_out)
                bufsiz -= have
                buflen += have
                if strm.avail_out != 0{
                    break
                }
                if bufsiz == 0 {
                    bufferSize *= 2
                    let nbuf = realloc(buffer, bufferSize)
                    if nbuf == nil {
                        throw WebSocketError.payloadError("memory")
                    }
                    buffer = nbuf
                    buf = buffer?.advanced(by: Int(buflen))
                    bufsiz = bufferSize - buflen
                }
            }
        }
        return (buffer!.assumingMemoryBound(to: UInt8.self), buflen)
    }
}

private class Deflater {
    var windowBits = 0
    var memLevel = 0
    var strm = z_stream()
    var bufferSize = windowBufferSize
    var buffer = malloc(windowBufferSize)
    init?(windowBits : Int, memLevel : Int){
        if buffer == nil {
            return nil
        }
        self.windowBits = windowBits
        self.memLevel = memLevel
        let ret = deflateInit2(&strm, level: 6, method: 8, windowBits: -CInt(windowBits), memLevel: CInt(memLevel), strategy: 0, version: zlibVersion(), stream_size: CInt(MemoryLayout<z_stream>.size))
        if ret != 0 {
            return nil
        }
    }
    deinit{
        _ = deflateEnd(&strm)
        free(buffer)
    }
    /*func deflate(_ bufin : UnsafePointer<UInt8>, length : Int, final : Bool) -> (p : UnsafeMutablePointer<UInt8>, n : Int, err : NSError?){
        return (nil, 0, nil)
    }*/
}

/// WebSocketDelegate is an Objective-C alternative to WebSocketEvents and is used to delegate the events for the WebSocket connection.
@objc public protocol WebSocketDelegate {
    /// A function to be called when the WebSocket connection's readyState changes to .Open; this indicates that the connection is ready to send and receive data.
    func webSocketOpen()
    /// A function to be called when the WebSocket connection's readyState changes to .Closed.
    func webSocketClose(_ code: Int, reason: String, wasClean: Bool)
    /// A function to be called when an error occurs.
    func webSocketError(_ error: NSError)
    /// A function to be called when a message (string) is received from the server.
    @objc optional func webSocketMessageText(_ text: String)
    /// A function to be called when a message (binary) is received from the server.
    @objc optional func webSocketMessageData(_ data: Data)
    /// A function to be called when a pong is received from the server.
    @objc optional func webSocketPong()
    /// A function to be called when the WebSocket process has ended; this event is guarenteed to be called once and can be used as an alternative to the "close" or "error" events.
    @objc optional func webSocketEnd(_ code: Int, reason: String, wasClean: Bool, error: NSError?)
}

/// WebSocket objects are bidirectional network streams that communicate over HTTP. RFC 6455.
private class InnerWebSocket: Hashable {
    var id : Int
    var mutex = pthread_mutex_t()
    let request : URLRequest!
    let subProtocols : [String]!
    var frames : [Frame] = []
    var delegate : Delegate
    var inflater : Inflater!
    var deflater : Deflater!
    var outputBytes : UnsafeMutablePointer<UInt8>?
    var outputBytesSize : Int = 0
    var outputBytesStart : Int = 0
    var outputBytesLength : Int = 0
    var inputBytes : UnsafeMutablePointer<UInt8>?
    var inputBytesSize : Int = 0
    var inputBytesStart : Int = 0
    var inputBytesLength : Int = 0
    var createdAt = CFAbsoluteTimeGetCurrent()
    var connectionTimeout = false
    var eclose : ()->() = {}
    var _eventQueue : DispatchQueue? = DispatchQueue.main
    var _subProtocol = ""
    var _compression = WebSocketCompression()
    var _allowSelfSignedSSL = false
    var _services = WebSocketService.None
    var _event = WebSocketEvents()
    var _eventDelegate: WebSocketDelegate?
    var _binaryType = WebSocketBinaryType.uInt8Array
    var _readyState = WebSocketReadyState.connecting
    var _networkTimeout = TimeInterval(-1)


    var url : String {
        return request.url!.description
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
    var eventQueue : DispatchQueue? {
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

    func copyOpen(_ request: URLRequest, subProtocols : [String] = []) -> InnerWebSocket{
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

    init(request: URLRequest, subProtocols : [String] = [], stub : Bool = false){
        pthread_mutex_init(&mutex, nil)
        self.id = manager.nextId()
        self.request = request
        self.subProtocols = subProtocols
        self.outputBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: windowBufferSize)
        self.outputBytesSize = windowBufferSize
        self.inputBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: windowBufferSize)
        self.inputBytesSize = windowBufferSize
        self.delegate = Delegate()
        if stub{
            manager.queue.asyncAfter(deadline: DispatchTime.now() + Double(0) / Double(NSEC_PER_SEC)){
                _ = self
            }
        } else {
            manager.queue.asyncAfter(deadline: DispatchTime.now() + Double(0) / Double(NSEC_PER_SEC)){
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
    @inline(__always) fileprivate func lock(){
        pthread_mutex_lock(&mutex)
    }
    @inline(__always) fileprivate func unlock(){
        pthread_mutex_unlock(&mutex)
    }

    fileprivate var dirty : Bool {
        lock()
        defer { unlock() }
        if exit {
            return false
        }
        if connectionTimeout {
            return true
        }
        if stage != .readResponse && stage != .handleFrames {
            return true
        }
        if rd.streamStatus == .opening && wr.streamStatus == .opening {
            return false;
        }
        if rd.streamStatus != .open || wr.streamStatus != .open {
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
        case openConn
        case readResponse
        case handleFrames
        case closeConn
        case end
    }
    var stage = Stage.openConn
    var rd : InputStream!
    var wr : OutputStream!
    var atEnd = false
    var closeCode = UInt16(0)
    var closeReason = ""
    var closeClean = false
    var closeFinal = false
    var finalError : Error?
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
            case .openConn:
                try openConn()
                stage = .readResponse
            case .readResponse:
                try readResponse()
                privateReadyState = .open
                fire {
                    self.event.open()
                    self.eventDelegate?.webSocketOpen()
                }
                stage = .handleFrames
            case .handleFrames:
                try stepOutputFrames()
                if closeFinal {
                    privateReadyState = .closing
                    stage = .closeConn
                    return
                }
                let frame = try readFrame()
                switch frame.code {
                case .text:
                    fire {
                        self.event.message(frame.utf8.text)
                        self.eventDelegate?.webSocketMessageText?(frame.utf8.text)
                    }
                case .binary:
                    fire {
                        switch self.binaryType {
                        case .uInt8Array:
                            self.event.message(frame.payload.array)
                        case .nsData:
                            self.event.message(frame.payload.nsdata)
                            // The WebSocketDelegate is necessary to add Objective-C compability and it is only possible to send binary data with NSData.
                            self.eventDelegate?.webSocketMessageData?(frame.payload.nsdata)
                        case .uInt8UnsafeBufferPointer:
                            self.event.message(frame.payload.buffer)
                        }
                    }
                case .ping:
                    let nframe = frame.copy()
                    nframe.code = .pong
                    lock()
                    frames += [nframe]
                    unlock()
                case .pong:
                    fire {
                        switch self.binaryType {
                        case .uInt8Array:
                            self.event.pong(frame.payload.array)
                        case .nsData:
                            self.event.pong(frame.payload.nsdata)
                        case .uInt8UnsafeBufferPointer:
                            self.event.pong(frame.payload.buffer)
                        }
                        self.eventDelegate?.webSocketPong?()
                    }
                case .close:
                    lock()
                    frames += [frame]
                    unlock()
                default:
                    break
                }
            case .closeConn:
                if let error = finalError {
                    self.event.error(error)
                    self.eventDelegate?.webSocketError(error as NSError)
                }
                privateReadyState = .closed
                if rd != nil {
                    closeConn()
                    fire {
                        self.eclose()
                        self.event.close(Int(self.closeCode), self.closeReason, self.closeFinal)
                        self.eventDelegate?.webSocketClose(Int(self.closeCode), reason: self.closeReason, wasClean: self.closeFinal)
                    }
                }
                stage = .end
            case .end:
                fire {
                    self.event.end(Int(self.closeCode), self.closeReason, self.closeClean, self.finalError)
                    self.eventDelegate?.webSocketEnd?(Int(self.closeCode), reason: self.closeReason, wasClean: self.closeClean, error: self.finalError as NSError?)
                }
                exit = true
                manager.remove(self)
            }
        } catch WebSocketError.needMoreInput {
            more = true
        } catch {
            if finalError != nil {
                return
            }
            finalError = error
            if stage == .openConn || stage == .readResponse {
                stage = .closeConn
            } else {
                var frame : Frame?
                if let error = error as? WebSocketError{
                    switch error {
                    case .network(let details):
                        if details == atEndDetails{
                            stage = .closeConn
                            frame = Frame.makeClose(1006, reason: "Abnormal Closure")
                            atEnd = true
                            finalError = nil
                        }
                    case .protocolError:
                        frame = Frame.makeClose(1002, reason: "Protocol error")
                    case .payloadError:
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
                        manager.queue.asyncAfter(deadline: DispatchTime.now() + Double(0) / Double(NSEC_PER_SEC)){
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
    func stepBuffers(_ more: Bool) throws {
        if rd != nil {
            if stage != .closeConn && rd.streamStatus == Stream.Status.atEnd  {
                if atEnd {
                    return;
                }
                throw WebSocketError.network(atEndDetails)
            }
            if more {
                while rd.hasBytesAvailable {
                    var size = inputBytesSize
                    while size-(inputBytesStart+inputBytesLength) < windowBufferSize {
                        size *= 2
                    }
                    if size > inputBytesSize {
                        let ptr = realloc(inputBytes, size)
                        if ptr == nil {
                            throw WebSocketError.memory
                        }
                        inputBytes = ptr?.assumingMemoryBound(to: UInt8.self)
                        inputBytesSize = size
                    }
                    let n = rd.read(inputBytes!+inputBytesStart+inputBytesLength, maxLength: inputBytesSize-inputBytesStart-inputBytesLength)
                    if n > 0 {
                        inputBytesLength += n
                    }
                }
            }
        }
        if wr != nil && wr.hasSpaceAvailable && outputBytesLength > 0 {
            let n = wr.write(outputBytes!+outputBytesStart, maxLength: outputBytesLength)
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
                throw WebSocketError.network(timeoutDetails)
            }
            if let error = rd?.streamError {
                throw WebSocketError.network(error.localizedDescription)
            }
            if let error = wr?.streamError {
                throw WebSocketError.network(error.localizedDescription)
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
                if frame.code == .close {
                    closeCode = frame.statusCode
                    closeReason = frame.utf8.text
                    closeFinal = true
                    return
                }
            }
        }
    }
    @inline(__always) func fire(_ block: ()->()){
        if let queue = eventQueue {
            queue.sync {
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
            if frame.code == .continue{
                throw WebSocketError.protocolError("leader frame cannot be a continue frame")
            }
            if !finished {
                readStateSaved = true
                readStateFrame = frame
                readStateFinished = finished
                throw WebSocketError.needMoreInput
            }
        } else {
            frame = readStateFrame!
            finished = readStateFinished
            if !finished {
                let cf = try readFrameFragment(frame)
                finished = cf.finished
                if cf.code != .continue {
                    if !cf.code.isControl {
                        throw WebSocketError.protocolError("only ping frames can be interlaced with fragments")
                    }
                    leaderFrame = frame
                    return cf
                }
                if !finished {
                    readStateSaved = true
                    readStateFrame = frame
                    readStateFinished = finished
                    throw WebSocketError.needMoreInput
                }
            }
        }
        if !frame.utf8.completed {
            throw WebSocketError.payloadError("incomplete utf8")
        }
        readStateSaved = false
        readStateFrame = nil
        readStateFinished = false
        return frame
    }

    func closeConn() {
        rd.remove(from: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
        wr.remove(from: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
        rd.delegate = nil
        wr.delegate = nil
        rd.close()
        wr.close()
    }

    func openConn() throws {
        var req = request!
        req.setValue("websocket", forHTTPHeaderField: "Upgrade")
        req.setValue("Upgrade", forHTTPHeaderField: "Connection")
        if req.value(forHTTPHeaderField: "User-Agent") == nil {
                req.setValue("SwiftWebSocket", forHTTPHeaderField: "User-Agent")
        }
        req.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")

        if req.url == nil || req.url!.host == nil{
            throw WebSocketError.invalidAddress
        }
        if req.url!.port == nil || req.url!.port! == 80 || req.url!.port! == 443 {
            req.setValue(req.url!.host!, forHTTPHeaderField: "Host")
        } else {
            req.setValue("\(req.url!.host!):\(req.url!.port!)", forHTTPHeaderField: "Host")
        }
        let origin = req.value(forHTTPHeaderField: "Origin")
        if origin == nil || origin! == ""{
            req.setValue(req.url!.absoluteString, forHTTPHeaderField: "Origin")
        }
        if subProtocols.count > 0 {
            req.setValue(subProtocols.joined(separator: ","), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        if req.url!.scheme != "wss" && req.url!.scheme != "ws" {
            throw WebSocketError.invalidAddress
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
		if req.url!.scheme == "wss" {
			port = req.url!.port ?? 443
			security = .negoticatedSSL
		} else {
			port = req.url!.port ?? 80
			security = .none
		}

		var path = CFURLCopyPath(req.url! as CFURL!) as String
        if path == "" {
            path = "/"
        }
        if let q = req.url!.query {
            if q != "" {
                path += "?" + q
            }
        }
        var reqs = "GET \(path) HTTP/1.1\r\n"
        for key in req.allHTTPHeaderFields!.keys {
            if let val = req.value(forHTTPHeaderField: key) {
                reqs += "\(key): \(val)\r\n"
            }
        }
        var keyb = [UInt32](repeating: 0, count: 4)
        for i in 0 ..< 4 {
            keyb[i] = arc4random()
        }
        let rkey = Data(bytes: UnsafePointer(keyb), count: 16).base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0))
        reqs += "Sec-WebSocket-Key: \(rkey)\r\n"
        reqs += "\r\n"
        var header = [UInt8]()
        for b in reqs.utf8 {
            header += [b]
        }
        let addr = ["\(req.url!.host!)", "\(port)"]
        if addr.count != 2 || Int(addr[1]) == nil {
            throw WebSocketError.invalidAddress
        }

        var (rdo, wro) : (InputStream?, OutputStream?)
        var readStream:  Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, addr[0] as CFString!, UInt32(Int(addr[1])!), &readStream, &writeStream);
        rdo = readStream!.takeRetainedValue()
        wro = writeStream!.takeRetainedValue()
        (rd, wr) = (rdo!, wro!)
        rd.setProperty(security.level, forKey: Stream.PropertyKey.socketSecurityLevelKey)
		wr.setProperty(security.level, forKey: Stream.PropertyKey.socketSecurityLevelKey)
        if services.contains(.VoIP) {
            rd.setProperty(StreamNetworkServiceTypeValue.voIP.rawValue, forKey: Stream.PropertyKey.networkServiceType)
            wr.setProperty(StreamNetworkServiceTypeValue.voIP.rawValue, forKey: Stream.PropertyKey.networkServiceType)
        }
        if services.contains(.Video) {
            rd.setProperty(StreamNetworkServiceTypeValue.video.rawValue, forKey: Stream.PropertyKey.networkServiceType)
            wr.setProperty(StreamNetworkServiceTypeValue.video.rawValue, forKey: Stream.PropertyKey.networkServiceType)
        }
        if services.contains(.Background) {
            rd.setProperty(StreamNetworkServiceTypeValue.background.rawValue, forKey: Stream.PropertyKey.networkServiceType)
            wr.setProperty(StreamNetworkServiceTypeValue.background.rawValue, forKey: Stream.PropertyKey.networkServiceType)
        }
        if services.contains(.Voice) {
            rd.setProperty(StreamNetworkServiceTypeValue.voice.rawValue, forKey: Stream.PropertyKey.networkServiceType)
            wr.setProperty(StreamNetworkServiceTypeValue.voice.rawValue, forKey: Stream.PropertyKey.networkServiceType)
        }
        if allowSelfSignedSSL {
            let prop: Dictionary<NSObject,NSObject> = [kCFStreamSSLPeerName: kCFNull, kCFStreamSSLValidatesCertificateChain: NSNumber(value: false)]
            rd.setProperty(prop, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String as String))
            wr.setProperty(prop, forKey: Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String as String))
        }
        rd.delegate = delegate
        wr.delegate = delegate
        rd.schedule(in: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
        wr.schedule(in: RunLoop.main, forMode: RunLoopMode.defaultRunLoopMode)
        rd.open()
        wr.open()
        try write(header, length: header.count)
    }

    func write(_ bytes: UnsafePointer<UInt8>, length: Int) throws {
        if outputBytesStart+outputBytesLength+length > outputBytesSize {
            var size = outputBytesSize
            while outputBytesStart+outputBytesLength+length > size {
                size *= 2
            }
            let ptr = realloc(outputBytes, size)
            if ptr == nil {
                throw WebSocketError.memory
            }
            outputBytes = ptr?.assumingMemoryBound(to: UInt8.self)
            outputBytesSize = size
        }
        memcpy(outputBytes!+outputBytesStart+outputBytesLength, bytes, length)
        outputBytesLength += length
    }

    func readResponse() throws {
        let end : [UInt8] = [ 0x0D, 0x0A, 0x0D, 0x0A ]
        let ptr = memmem(inputBytes!+inputBytesStart, inputBytesLength, end, 4)
        if ptr == nil {
            throw WebSocketError.needMoreInput
        }
        let buffer = inputBytes!+inputBytesStart
        let bufferCount = ptr!.assumingMemoryBound(to: UInt8.self)-(inputBytes!+inputBytesStart)
        let string = NSString(bytesNoCopy: buffer, length: bufferCount, encoding: String.Encoding.utf8.rawValue, freeWhenDone: false) as String?
        if string == nil {
            throw WebSocketError.invalidHeader
        }
        let header = string!
        var needsCompression = false
        var serverMaxWindowBits = 15
        let clientMaxWindowBits = 15
        var key = ""
        let trim : (String)->(String) = { (text) in return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)}
        let eqval : (String,String)->(String) = { (line, del) in return trim(line.components(separatedBy: del)[1]) }
        let lines = header.components(separatedBy: "\r\n")
        for i in 0 ..< lines.count {
            let line = trim(lines[i])
            if i == 0  {
                if !line.hasPrefix("HTTP/1.1 101"){
                    throw WebSocketError.invalidResponse(line)
                }
            } else if line != "" {
                var value = ""
                if line.hasPrefix("\t") || line.hasPrefix(" ") {
                    value = trim(line)
                } else {
                    key = ""
                    if let r = line.range(of: ":") {
                        key = trim(line.substring(to: r.lowerBound))
                        value = trim(line.substring(from: r.upperBound))
                    }
                }
                
                switch key.lowercased() {
                case "sec-websocket-subprotocol":
                    privateSubProtocol = value
                case "sec-websocket-extensions":
                    let parts = value.components(separatedBy: ";")
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
                throw WebSocketError.invalidCompressionOptions("server_max_window_bits")
            }
            if serverMaxWindowBits < 8 || serverMaxWindowBits > 15 {
                throw WebSocketError.invalidCompressionOptions("client_max_window_bits")
            }
            inflater = Inflater(windowBits: serverMaxWindowBits)
            if inflater == nil {
                throw WebSocketError.invalidCompressionOptions("inflater init")
            }
            deflater = Deflater(windowBits: clientMaxWindowBits, memLevel: 8)
            if deflater == nil {
                throw WebSocketError.invalidCompressionOptions("deflater init")
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
                throw WebSocketError.needMoreInput
            }
            let b = bytes.pointee
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
    var fragStateCode = OpCode.continue
    var fragStateLeaderCode = OpCode.continue
    var fragStateUTF8 = UTF8()
    var fragStatePayload = Payload()
    var fragStateStatusCode = UInt16(0)
    var fragStateHeaderLen = 0
    var buffer = [UInt8](repeating: 0, count: windowBufferSize)
    var reusedPayload = Payload()
    func readFrameFragment(_ leader : Frame?) throws -> Frame {
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

        let reader = ByteReader(bytes: inputBytes!+inputBytesStart, length: inputBytesLength)
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
                throw WebSocketError.protocolError("invalid extension")
            } else {
                inflate = false
            }
            code = OpCode.binary
            if let c = OpCode(rawValue: (b & 0xF)){
                code = c
            } else {
                throw WebSocketError.protocolError("invalid opcode")
            }
            if !fin && code.isControl {
                throw WebSocketError.protocolError("unfinished control frame")
            }
            b = try reader.readByte()
            if b >> 7 & 0x1 == 0x1 {
                throw WebSocketError.protocolError("server sent masked frame")
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
                    throw WebSocketError.protocolError("invalid payload size for control frame")
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
            if code == .continue {
                if code.isControl {
                    throw WebSocketError.protocolError("control frame cannot have the 'continue' opcode")
                }
                if leader == nil {
                    throw WebSocketError.protocolError("continue frame is missing it's leader")
                }
            }
            if code.isControl {
                if leader != nil {
                    leader = nil
                }
                if inflate {
                    throw WebSocketError.protocolError("control frame cannot be compressed")
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
            if leaderCode == .close {
                if len == 1 {
                    throw WebSocketError.protocolError("invalid payload size for close frame")
                }
                if len >= 2 {
                    let b1 = try reader.readByte()
                    let b2 = try reader.readByte()
                    statusCode = (UInt16(b1) << 8) + UInt16(b2)
                    len -= 2
                    if statusCode < 1000 || statusCode > 4999  || (statusCode >= 1004 && statusCode <= 1006) || (statusCode >= 1012 && statusCode <= 2999) {
                        throw WebSocketError.protocolError("invalid status code for close frame")
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
            (bytes, bytesLen) = (UnsafeMutablePointer<UInt8>.init(mutating: reader.bytes), rlen)
        }
        reader.bytes += rlen

        if leaderCode == .text || leaderCode == .close {
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
            throw WebSocketError.needMoreInput
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

    var head = [UInt8](repeating: 0, count: 0xFF)
    func writeFrame(_ f : Frame) throws {
        if !f.finished{
            throw WebSocketError.libraryError("cannot send unfinished frames")
        }
        var hlen = 0
        let b : UInt8 = 0x80
        var deflate = false
        if deflater != nil {
            if f.code == .binary || f.code == .text {
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
    func close(_ code : Int = 1000, reason : String = "Normal Closure") {
        let f = Frame()
        f.code = .close
        f.statusCode = UInt16(truncatingIfNeeded: code)
        f.utf8.text = reason
        sendFrame(f)
    }
    func sendFrame(_ f : Frame) {
        lock()
        frames += [f]
        unlock()
        manager.signal()
    }
    func send(_ message : Any) {
        let f = Frame()
        if let message = message as? String {
            f.code = .text
            f.utf8.text = message
        } else if let message = message as? [UInt8] {
            f.code = .binary
            f.payload.array = message
        } else if let message = message as? UnsafeBufferPointer<UInt8> {
            f.code = .binary
            f.payload.append(message.baseAddress!, length: message.count)
        } else if let message = message as? Data {
            f.code = .binary
            f.payload.nsdata = message
        } else {
            f.code = .text
            f.utf8.text = "\(message)"
        }
        sendFrame(f)
    }
    func ping() {
        let f = Frame()
        f.code = .ping
        sendFrame(f)
    }
    func ping(_ message : Any){
        let f = Frame()
        f.code = .ping
        if let message = message as? String {
            f.payload.array = UTF8.bytes(message)
        } else if let message = message as? [UInt8] {
            f.payload.array = message
        } else if let message = message as? UnsafeBufferPointer<UInt8> {
            f.payload.append(message.baseAddress!, length: message.count)
        } else if let message = message as? Data {
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
    case none
    case negoticatedSSL
	
	var level: String {
		switch self {
		case .none: return StreamSocketSecurityLevel.none.rawValue
		case .negoticatedSSL: return StreamSocketSecurityLevel.negotiatedSSL.rawValue
		}
	}
}

// Manager class is used to minimize the number of dispatches and cycle through network events
// using fewers threads. Helps tremendously with lowing system resources when many conncurrent
// sockets are opened.
private class Manager {
    var queue = DispatchQueue(label: "SwiftWebSocketInstance", attributes: [])
    var once = Int()
    var mutex = pthread_mutex_t()
    var cond = pthread_cond_t()
    var websockets = Set<InnerWebSocket>()
    var _nextId = 0
    init(){
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&cond, nil)
        DispatchQueue(label: "SwiftWebSocket", attributes: []).async {
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
                    _ = self.wait(250)
                }
                pthread_mutex_unlock(&self.mutex)
            }
        }
    }
    func checkForConnectionTimeout(_ ws : InnerWebSocket) {
        if ws.rd != nil && ws.wr != nil && (ws.rd.streamStatus == .opening || ws.wr.streamStatus == .opening) {
            let age = CFAbsoluteTimeGetCurrent() - ws.createdAt
            if age >= timeoutDuration {
                ws.connectionTimeout = true
            }
        }
    }
    func wait(_ timeInMs : Int) -> Int32 {
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
    func add(_ websocket: InnerWebSocket) {
        pthread_mutex_lock(&mutex)
        websockets.insert(websocket)
        pthread_cond_signal(&cond)
        pthread_mutex_unlock(&mutex)
    }
    func remove(_ websocket: InnerWebSocket) {
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
open class WebSocket: NSObject {
    fileprivate var ws: InnerWebSocket
    fileprivate var id = manager.nextId()
    fileprivate var opened: Bool
    open override var hashValue: Int { return id }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    public convenience init(_ url: String){
        self.init(request: URLRequest(url: URL(string: url)!), subProtocols: [])
    }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    public convenience init(url: URL){
        self.init(request: URLRequest(url: url), subProtocols: [])
    }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a list of protocols.
    public convenience init(_ url: String, subProtocols : [String]){
        self.init(request: URLRequest(url: URL(string: url)!), subProtocols: subProtocols)
    }
    /// Create a WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a protocol.
    public convenience init(_ url: String, subProtocol : String){
        self.init(request: URLRequest(url: URL(string: url)!), subProtocols: [subProtocol])
    }
    /// Create a WebSocket connection from an NSURLRequest; Also include a list of protocols.
    public init(request: URLRequest, subProtocols : [String] = []){
        let hasURL = request.url != nil
        opened = hasURL
        ws = InnerWebSocket(request: request, subProtocols: subProtocols, stub: !hasURL)
        super.init()
        // weak/strong pattern from:
        // http://stackoverflow.com/a/17105368/424124
        // https://dhoerl.wordpress.com/2013/04/23/i-finally-figured-out-weakself-and-strongself/
        ws.eclose = { [weak self] in
            if let strongSelf = self {
                strongSelf.opened = false
            }
        }
    }
    /// Create a WebSocket object with a deferred connection; the connection is not opened until the .open() method is called.
    public convenience override init(){
        var request = URLRequest(url: URL(string: "http://apple.com")!)
        request.url = nil
        self.init(request: request, subProtocols: [])
    }
    /// The URL as resolved by the constructor. This is always an absolute URL. Read only.
    open var url : String{ return ws.url }
    /// A string indicating the name of the sub-protocol the server selected; this will be one of the strings specified in the protocols parameter when creating the WebSocket object.
    open var subProtocol : String{ return ws.subProtocol }
    /// The compression options of the WebSocket.
    open var compression : WebSocketCompression{
        get { return ws.compression }
        set { ws.compression = newValue }
    }
    /// Allow for Self-Signed SSL Certificates. Default is false.
    open var allowSelfSignedSSL : Bool{
        get { return ws.allowSelfSignedSSL }
        set { ws.allowSelfSignedSSL = newValue }
    }
    /// The services of the WebSocket.
    open var services : WebSocketService{
        get { return ws.services }
        set { ws.services = newValue }
    }
    /// The events of the WebSocket.
    open var event : WebSocketEvents{
        get { return ws.event }
        set { ws.event = newValue }
    }
    /// The queue for firing off events. default is main_queue
    open var eventQueue : DispatchQueue?{
        get { return ws.eventQueue }
        set { ws.eventQueue = newValue }
    }
    /// A WebSocketBinaryType value indicating the type of binary data being transmitted by the connection. Default is .UInt8Array.
    open var binaryType : WebSocketBinaryType{
        get { return ws.binaryType }
        set { ws.binaryType = newValue }
    }
    /// The current state of the connection; this is one of the WebSocketReadyState constants. Read only.
    open var readyState : WebSocketReadyState{
        return ws.readyState
    }
    /// Opens a deferred or closed WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    open func open(_ url: String){
        open(request: URLRequest(url: URL(string: url)!), subProtocols: [])
    }
    /// Opens a deferred or closed WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond.
    open func open(nsurl url: URL){
        open(request: URLRequest(url: url), subProtocols: [])
    }
    /// Opens a deferred or closed WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a list of protocols.
    open func open(_ url: String, subProtocols : [String]){
        open(request: URLRequest(url: URL(string: url)!), subProtocols: subProtocols)
    }
    /// Opens a deferred or closed WebSocket connection to a URL; this should be the URL to which the WebSocket server will respond. Also include a protocol.
    open func open(_ url: String, subProtocol : String){
        open(request: URLRequest(url: URL(string: url)!), subProtocols: [subProtocol])
    }
    /// Opens a deferred or closed WebSocket connection from an NSURLRequest; Also include a list of protocols.
    open func open(request: URLRequest, subProtocols : [String] = []){
        if opened{
            return
        }
        opened = true
        ws = ws.copyOpen(request, subProtocols: subProtocols)
    }
    /// Opens a closed WebSocket connection from an NSURLRequest; Uses the same request and protocols as previously closed WebSocket
    open func open(){
        open(request: ws.request, subProtocols: ws.subProtocols)
    }
    /**
     Closes the WebSocket connection or connection attempt, if any. If the connection is already closed or in the state of closing, this method does nothing.

     :param: code An integer indicating the status code explaining why the connection is being closed. If this parameter is not specified, a default value of 1000 (indicating a normal closure) is assumed.
     :param: reason A human-readable string explaining why the connection is closing. This string must be no longer than 123 bytes of UTF-8 text (not characters).
     */
    open func close(_ code : Int = 1000, reason : String = "Normal Closure"){
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
    open func send(_ message : Any){
        if !opened{
            return
        }
        ws.send(message)
    }
    /**
     Transmits a ping to the server over the WebSocket connection.

     :param: optional message The data to be sent to the server.
     */
    open func ping(_ message : Any){
        if !opened{
            return
        }
        ws.ping(message)
    }
    /**
     Transmits a ping to the server over the WebSocket connection.
     */
    open func ping(){
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
    public func send(text: String){
        send(text)
    }
    /**
     Transmits message to the server over the WebSocket connection.

     :param: data The message (binary) to be sent to the server.
     */
    @objc
    public func send(data: Data){
        send(data)
    }
}
