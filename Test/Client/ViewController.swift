//
//  ViewController.swift
//  Client
//
//  Created by Josh Baker on 4/14/16.
//  Copyright © 2016 ONcast, LLC. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    func echoTest(){
        var messageNum = 0
        let ws = WebSocket("ws://localhost:6790/echo")
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
            print("close \(code) \(reason)")
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        echoTest()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

