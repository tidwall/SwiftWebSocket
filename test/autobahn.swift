import Foundation

let baseURL = "ws://localhost:9001"
let agent = "SwiftWebSocket"
let debug = false
let keepStatsUpdated = false
let stopOnFailure = false
let stopOnInfo = false
let stopAfterOne = false
let showDuration = false

let startCase =  1 
let stopAtCase = 999

private func jsonObject(text : String) -> [String: AnyObject]? {
    if let data = text.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false) {
        return NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableContainers, error: nil) as? [String : AnyObject]
    }
    return nil
}
private func makeError(error : String) -> NSError {
    return NSError(domain: "com.github.tidwall.SwiftSocket.test", code: -19010, userInfo: [NSLocalizedDescriptionKey:error])
}

// autobahn api
func getCaseCount(block:(count : Int, err : NSError?)->()){
    var ws = WebSocket(url: baseURL + "/getCaseCount")
    ws.event.message = { (msg) in
        if let text = msg as? String {
            ws.close()
            if let i = text.toInt() {
                block(count: i, err: nil)
            } else {
                block(count: 0, err: makeError("invalid response"))
            }
        }
    }
    ws.event.error = { (err) in
        block(count: 0, err: err)
    }
}

func getCaseInfo(caseIdx : Int, block :(id : String, description : String, err : NSError?)->()){
    var ws = WebSocket(url: baseURL + "/getCaseInfo?case=\(caseIdx+1)")
    ws.event.message = { (msg) in
        if let text = msg as? String {
            ws.close()
            if let json = jsonObject(text) {
                if json["id"] == nil || json["description"] == nil {
                    block(id: "", description: "", err: makeError("invalid response"))
                }
                block(id: json["id"] as! String, description: json["description"] as! String, err: nil)
            } else {
                block(id: "", description: "", err: makeError("not json"))
            }
        }
    }
    ws.event.error = { (err) in
        block(id: "", description: "", err: err)
    }
}

func getCaseStatus(caseIdx : Int, block : (err : NSError?)->()){
    var responseText = ""
    var ws = WebSocket(url: baseURL + "/getCaseStatus?case=\(caseIdx+1)&agent=\(agent)")
    ws.event.error = { (err) in
        block(err: err)
    }
    ws.event.message = { (msg) in
        if let text = msg as? String {
            responseText = text
            ws.close()
        }
    }
    ws.event.close = { (code, reason, clean) in
        if let json = jsonObject(responseText){
            if let behavior = json["behavior"] as? String {
                if behavior == "OK" {
                    block(err: nil)
                } else if behavior == "FAILED"{
                    block(err: makeError(""))
                } else {
                    block(err: makeError(behavior))
                }
                return
            }
        }
        block(err: makeError("invalid json"))
    }
}

func updateReports(echo: Bool = false, block : ()->()){
    var success = false
    var ws = WebSocket(url: baseURL + "/updateReports?agent=\(agent)")
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

func runCase(caseIdx : Int, caseCount : Int, block : (err : NSError?)->()) {
    var start = NSDate().timeIntervalSince1970
    var evstart = NSTimeInterval(0)
    getCaseInfo(caseIdx, { (id, description, err) in
        if err != nil{
            println("[ERR] getCaseInfo failed: \(err!)\n")
            exit(1)
        }


        println("[CASE] #\(caseIdx+1)/\(caseCount): \(id): \(description)")
        let failed : (message : String)->() = { (message) in
            block(err: makeError(message))
        }
        let warn : (message : String)->() = { (message) in
            printFailure(makeError(message))
        }
        let next = { ()->() in
            if showDuration {
                var now = NSDate().timeIntervalSince1970
                var recv = evstart == 0 ? 0 : (evstart - start) * 1000
                var total = (now - start) * 1000
                var send = total - recv
                //println("[DONE] %.0f ms (recv: %.0f ms, send: %.0f ms)", total, recv, send)
            }
            getCaseStatus(caseIdx){ (err) in
                var f : ()->() = {
                    if err != nil{
                        if err!.localizedDescription == "INFORMATIONAL" {
                            if stopOnInfo {
                                failed(message : err!.localizedDescription)
                                return
                            }
                        } else if stopOnFailure {
                            failed(message : err!.localizedDescription)
                            return
                        }
                        warn(message : err!.localizedDescription)
                    }
                    if caseIdx+1 == caseCount || stopAfterOne || (caseIdx+1 == stopAtCase){
                        block(err: nil)
                    } else {
                        runCase(caseIdx+1, caseCount, block)
                    }
                }
                if keepStatsUpdated {
                    updateReports(echo: false, f)
                } else {
                    f()
                }
            }
        }
        var responseError : NSError?
        var ws = WebSocket(url: baseURL + "/runCase?case=\(caseIdx+1)&agent=\(agent)")
        ws.event.synced = true
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
        //ws.binaryType = .NSData
        ws.event.end = { (code, reason, clean, err) in
            responseError = err
            if responseError == nil {
                next()
            } else {
                var message = ""
                if responseError != nil{
                    message += responseError!.localizedDescription
                }
                if code != 0 {
                    message += " with code '\(code)' and reason '\(reason)'"
                }
                failed(message: message)
            }
        }
        ws.event.message = { (msg) in
            evstart = NSDate().timeIntervalSince1970
            ws.send(msg)
        }
    })
}
func printFailure(err : NSError?){
    if err == nil || err!.localizedDescription == "" {
        println("[ERR] FAILED")
        exit(1)
    } else {
        if err!.localizedDescription == "INFORMATIONAL" {
            //printinfo("INFORMATIONAL")
        } else {
            println("[ERR] FAILED: \(err!.localizedDescription)")
            exit(1)
        }
    }
}

getCaseCount { (count, err) in
    if err != nil{
        println("[ERR] getCaseCount failed: \(err!)")
        exit(1)
    }
    runCase(startCase-1, count){ (err) in
        if err == nil{
        } else {
            printFailure(err)
            exit(1)
        }
        updateReports(echo: true){
            exit(0)
        }
    }
}


NSRunLoop.mainRunLoop().run()
