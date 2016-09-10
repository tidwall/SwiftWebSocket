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
    case Protocoll = 1002, Payload = 1007, Undefined = -100, Codepoint = -101, Library = -102, Socket = -103
    var description : String {
        switch self {
        case .Protocoll: return "Protocol error"
        case .Payload: return "Invalid payload data"
        case .Codepoint: return "Invalid codepoint"
        case .Library: return "Library error"
        case .Undefined: return "Undefined error"
        case .Socket: return "Broken socket"
        }
    }
}

private func makeError(error : String, code: ErrCode) -> Error {
    return NSError(domain: "com.github.tidwall.WebSocketConn", code: code.rawValue, userInfo: [NSLocalizedDescriptionKey:"\(error)"])
}
private func makeError(error : Error, code: ErrCode) -> Error {
    let err = error as NSError
    return NSError(domain: err.domain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey:"\(err.localizedDescription)"])
}
private func makeError(error : String) -> Error {
    return makeError(error: error, code: ErrCode.Library)
}

private func jsonObject(text : String) throws -> [String: AnyObject] {
    if let data = text.data(using: String.Encoding.utf8, allowLossyConversion: false),
        let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.mutableContainers) as? [String : AnyObject] {
            return json
    }
    throw makeError(error: "not json")
}

// autobahn api
func getCaseCount(block: @escaping(_ : Int, _ : Error?)->()){
    let ws = WebSocket(baseURL + "/getCaseCount")
    ws.event.message = { (msg) in
        if let text = msg as? String {
            ws.close()
            if let i = Int(text) {
                block(i, nil)
            } else {
                block(0, makeError(error: "invalid response"))
            }
        }
    }
    ws.event.error = { error in
        block(0, error)
    }
}

func getCaseInfo(caseIdx : Int, block : @escaping(_ : String, _ : String, _ : Error?)->()){
    let ws = WebSocket(baseURL + "/getCaseInfo?case=\(caseIdx+1)")
    ws.event.message = { (msg) in
        if let text = msg as? String {
            ws.close()
            do {
                let json = try jsonObject(text: text)
                if json["id"] == nil || json["description"] == nil {
                    block("", "", makeError(error: "invalid response"))
                }
                block(json["id"] as! String, json["description"] as! String, nil)
            } catch {
                block("", "", error)
            }
        }
    }
    ws.event.error = { error in
        block("", "", error)
    }
}

func getCaseStatus(caseIdx : Int, block : @escaping(_ : Error?)->()){
    var responseText = ""
    let ws = WebSocket(baseURL + "/getCaseStatus?case=\(caseIdx+1)&agent=\(agent)")
    ws.event.error = { error in
        block(error)
    }
    ws.event.message = { (msg) in
        if let text = msg as? String {
            responseText = text
            ws.close()
        }
    }
    ws.event.close = { (code, reason, clean) in
        do {
            let json = try jsonObject(text: responseText)
            if let behavior = json["behavior"] as? String {
                if behavior == "OK" {
                    block(nil)
                } else if behavior == "FAILED"{
                    block(makeError(error: ""))
                } else {
                    block(makeError(error: behavior))
                }
                return
            }
        } catch {
            block(error)
        }
    }
}

func updateReports(echo: Bool = false, block : @escaping()->()){
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

func runCase(caseIdx : Int, caseCount : Int, block : @escaping(_ : Error?)->()) {
//    var start = NSDate().timeIntervalSince1970
//    var evstart = NSTimeInterval(0)
    getCaseInfo(caseIdx: caseIdx, block: { (id, description, error) in
        if error != nil{
            print("[ERR] getCaseInfo failed: \(error!)\n")
            exit(1)
        }

        var next = { ()->() in }


        print("[CASE] #\(caseIdx+1)/\(caseCount): \(id): \(description)")
        let failed : (_ : String)->() = { (message) in
            let error = makeError(error: message)
            printFailure(error: error)
            if stopOnFailure {
                block(error)    
            } else {
                next()
            }
        }
        let warn : (_ : String)->() = { (message) in
            printFailure(error: makeError(error: message))
        }
        next = { ()->() in
//            if showDuration {
//                let now = NSDate().timeIntervalSince1970
//                let recv = evstart == 0 ? 0 : (evstart - start) * 1000
//                let total = (now - start) * 1000
//                let send = total - recv
//                println("[DONE] %.0f ms (recv: %.0f ms, send: %.0f ms)", total, recv, send)
//            }
            getCaseStatus(caseIdx: caseIdx){ error in
                let f : ()->() = {
                    if let error = error as? NSError {
                        if error.localizedDescription == "INFORMATIONAL" {
                            if stopOnInfo {
                                failed(error.localizedDescription)
                                return
                            }
                        } else if stopOnFailure {
                            failed(error.localizedDescription)
                            return
                        }
                        warn(error.localizedDescription)
                    }
                    if caseIdx+1 == caseCount || stopAfterOne || (caseIdx+1 == stopAtCase){
                        block(nil)
                    } else {
                        runCase(caseIdx: caseIdx+1, caseCount: caseCount, block: block)
                    }
                }
                if keepStatsUpdated || caseIdx % 10 == 0 {
                    updateReports(echo: false, block: f)
                } else {
                    f()
                }
            }
        }
        var responseError : Error?
        //print(baseURL + "/runCase?case=\(caseIdx+1)&agent=\(agent)")
        let ws = WebSocket(baseURL + "/runCase?case=\(caseIdx+1)&agent=\(agent)")
        ws.eventQueue = nil
        ws.binaryType = .uInt8UnsafeBufferPointer

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
                failed(message)
            }
        }
        ws.event.message = { (msg) in
//            evstart = NSDate().timeIntervalSince1970
            ws.send(msg)
        }
    })
}
func printFailure(error : Error?){
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
    runCase(caseIdx: startCase-1, caseCount: count){ (error) in
        if error == nil{
            updateReports(echo: true){
               exit(0)
            }
        } else {
            updateReports(echo: true){
               exit(1)
            }
        }
    }
}

RunLoop.main.run()
