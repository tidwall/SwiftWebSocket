import Foundation

let baseURL = "ws://localhost:9001"
let agent = "SwiftWebSocket"
let debug = false
let keepStatsUpdated = false
let stopOnFailure = false
let stopOnInfo = false
let stopAfterOne = false
let showDuration = false

let startCase = 1
let stopAtCase = 999

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

private func jsonObject(text : String) throws -> [String: AnyObject] {
    if let data = text.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false),
        let json = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableContainers) as? [String : AnyObject] {
            return json
    }
    throw makeError("not json")
}

// autobahn api
func getCaseCount(block:(count : Int, error : ErrorType?)->()){
    let ws = WebSocket(baseURL + "/getCaseCount")
    ws.event.message = { (msg) in
        if let text = msg as? String {
            ws.close()
            if let i = Int(text) {
                block(count: i, error: nil)
            } else {
                block(count: 0, error: makeError("invalid response"))
            }
        }
    }
    ws.event.error = { error in
        block(count: 0, error: error)
    }
}

func getCaseInfo(caseIdx : Int, block :(id : String, description : String, error : ErrorType?)->()){
    let ws = WebSocket(baseURL + "/getCaseInfo?case=\(caseIdx+1)")
    ws.event.message = { (msg) in
        if let text = msg as? String {
            ws.close()
            do {
                let json = try jsonObject(text)
                if json["id"] == nil || json["description"] == nil {
                    block(id: "", description: "", error: makeError("invalid response"))
                }
                block(id: json["id"] as! String, description: json["description"] as! String, error: nil)
            } catch {
                block(id: "", description: "", error: error)
            }
        }
    }
    ws.event.error = { error in
        block(id: "", description: "", error: error)
    }
}

func getCaseStatus(caseIdx : Int, block : (error : ErrorType?)->()){
    var responseText = ""
    let ws = WebSocket(baseURL + "/getCaseStatus?case=\(caseIdx+1)&agent=\(agent)")
    ws.event.error = { error in
        block(error: error)
    }
    ws.event.message = { (msg) in
        if let text = msg as? String {
            responseText = text
            ws.close()
        }
    }
    ws.event.close = { (code, reason, clean) in
        do {
            let json = try jsonObject(responseText)
            if let behavior = json["behavior"] as? String {
                if behavior == "OK" {
                    block(error: nil)
                } else if behavior == "FAILED"{
                    block(error: makeError(""))
                } else {
                    block(error: makeError(behavior))
                }
                return
            }
        } catch {
            block(error: error)
        }
    }
}

func updateReports(echo: Bool = false, block : ()->()){
    var success = false
    let ws = WebSocket(baseURL + "/updateReports?agent=\(agent)")
    ws.event.close = { (code, reason, clean) in
        if echo {
            if !success{
                print("[ERR] reports failed to update")
                exit(1)
            }
        }
        block()
    }
    ws.event.open = {
        ws.close()
        success = true
    }
}

func runCase(caseIdx : Int, caseCount : Int, block : (error : ErrorType?)->()) {
//    var start = NSDate().timeIntervalSince1970
//    var evstart = NSTimeInterval(0)
    getCaseInfo(caseIdx, block: { (id, description, error) in
        if error != nil{
            print("[ERR] getCaseInfo failed: \(error!)\n")
            exit(1)
        }

        var next = { ()->() in }


        print("[CASE] #\(caseIdx+1)/\(caseCount): \(id): \(description)")
        let failed : (message : String)->() = { (message) in
            let error = makeError(message)
            printFailure(error)
            if stopOnFailure {
                block(error: error)    
            } else {
                next()
            }
        }
        let warn : (message : String)->() = { (message) in
            printFailure(makeError(message))
        }
        next = { ()->() in
//            if showDuration {
//                let now = NSDate().timeIntervalSince1970
//                let recv = evstart == 0 ? 0 : (evstart - start) * 1000
//                let total = (now - start) * 1000
//                let send = total - recv
//                println("[DONE] %.0f ms (recv: %.0f ms, send: %.0f ms)", total, recv, send)
//            }
            getCaseStatus(caseIdx){ error in
                let f : ()->() = {
                    if let error = error as? NSError {
                        if error.localizedDescription == "INFORMATIONAL" {
                            if stopOnInfo {
                                failed(message : error.localizedDescription)
                                return
                            }
                        } else if stopOnFailure {
                            failed(message : error.localizedDescription)
                            return
                        }
                        warn(message : error.localizedDescription)
                    }
                    if caseIdx+1 == caseCount || stopAfterOne || (caseIdx+1 == stopAtCase){
                        block(error: nil)
                    } else {
                        runCase(caseIdx+1, caseCount: caseCount, block: block)
                    }
                }
                if keepStatsUpdated || caseIdx % 10 == 0 {
                    updateReports(false, block: f)
                } else {
                    f()
                }
            }
        }
        var responseError : ErrorType?
        //print(baseURL + "/runCase?case=\(caseIdx+1)&agent=\(agent)")
        let ws = WebSocket(baseURL + "/runCase?case=\(caseIdx+1)&agent=\(agent)")
        ws.eventQueue = nil
        ws.binaryType = .UInt8UnsafeBufferPointer

        if id.hasPrefix("13.") || id.hasPrefix("12.") {
            ws.compression.on = true
            if id.hasPrefix("13.1"){
                ws.compression.noContextTakeover = false
                ws.compression.maxWindowBits =  0
            }
            if id.hasPrefix("13.2"){
                ws.compression.noContextTakeover = true
                ws.compression.maxWindowBits = 0
            }
            if id.hasPrefix("13.3"){
                ws.compression.noContextTakeover = false
                ws.compression.maxWindowBits = 8
            }
            if id.hasPrefix("13.4"){
                ws.compression.noContextTakeover = false
                ws.compression.maxWindowBits = 15
            }
            if id.hasPrefix("13.5"){
                ws.compression.noContextTakeover = true
                ws.compression.maxWindowBits = 8
            }
            if id.hasPrefix("13.6"){
                ws.compression.noContextTakeover = true
                ws.compression.maxWindowBits = 15
            }
            if id.hasPrefix("13.7"){
                ws.compression.noContextTakeover = true
                ws.compression.maxWindowBits = 8
            }
        }
        ws.event.end = { (code, reason, clean, error) in
            responseError = error
            if responseError == nil {
                next()
            } else {
                var message = ""
                if let error = responseError as? NSError {
                    message += error.localizedDescription
                }
                if code != 0 {
                    message += " with code '\(code)' and reason '\(reason)'"
                }
                failed(message: message)
            }
        }
        ws.event.message = { (msg) in
//            evstart = NSDate().timeIntervalSince1970
            ws.send(msg)
        }
    })
}
func printFailure(error : ErrorType?){
    let error = error as? NSError
    if error == nil || error!.localizedDescription == "" {
        print("[ERR] FAILED")
        exit(1)
    } else {
        if error!.localizedDescription == "INFORMATIONAL" {
            //printinfo("INFORMATIONAL")
        } else {
            print("[ERR] FAILED: \(error!.localizedDescription)")
        }
    }
}

getCaseCount { (count, error) in
    if error != nil{
        print("[ERR] getCaseCount failed: \(error!)")
        exit(1)
    }
    runCase(startCase-1, caseCount: count){ (error) in
        if error == nil{
            updateReports(true){
               exit(0)
            }
        } else {
            updateReports(true){
               exit(1)
            }
        }
    }
}

NSRunLoop.mainRunLoop().run()