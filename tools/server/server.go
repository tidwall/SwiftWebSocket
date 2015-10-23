package main

import (
	"flag"
	"fmt"
	"github.com/gorilla/websocket"
	"log"
	"net/http"
	"time"
)

var port int
var crt, key string
var host string
var s string
var ports string
var _case string

func main() {

	flag.StringVar(&crt, "crt", "", "ssl cert file")
	flag.StringVar(&key, "key", "", "ssl key file")
	flag.StringVar(&host, "host", "localhost", "listening server host")
	flag.StringVar(&_case, "case", "", "choose a specialized case, (hang)")
	flag.IntVar(&port, "port", 6789, "listening server port")
	flag.Parse()

	if crt != "" || key != "" {
		s = "s"
		if port != 443 {
			ports = fmt.Sprintf(":%d", port)
		}
	} else if port != 80 {
		ports = fmt.Sprintf(":%d", port)
	}
	http.HandleFunc("/client", client)
	http.HandleFunc("/echo", socket)
	log.Printf("Running server on %s:%d\n", host, port)
	switch _case {
	case "hang":
		log.Printf("case: %s (long connection hanging)\n", _case)
	}
	log.Printf("ws%s://%s%s/echo      (echo socket)\n", s, host, ports)
	log.Printf("http%s://%s%s/client  (javascript test client)\n", s, host, ports)
	var err error
	if crt != "" || key != "" {
		err = http.ListenAndServeTLS(fmt.Sprintf(":%d", port), crt, key, nil)
	} else {
		err = http.ListenAndServe(fmt.Sprintf(":%d", port), nil)
	}
	if err != nil {
		log.Fatal("ListenAndServe: ", err)
	}
}

func socket(w http.ResponseWriter, r *http.Request) {
	log.Print("connection established")
	if _case == "hang" {
		hang := time.Minute
		log.Printf("hanging for %s\n", hang.String())
		time.Sleep(hang)
	}
	ws, err := websocket.Upgrade(w, r, nil, 1024, 1024)
	if err != nil {
		log.Print(err)
		return
	}
	defer func() {
		ws.Close()
		log.Print("connection closed")
	}()
	for {
		msgt, msg, err := ws.ReadMessage()
		if err != nil {
			log.Print(err)
			return
		}
		log.Print("rcvd: '" + string(msg) + "'")
		ws.WriteMessage(msgt, msg)
	}
}

func client(w http.ResponseWriter, r *http.Request) {
	log.Print("client request")
	w.Header().Set("Content-Type", "text/html")
	w.Write([]byte(`
		<pre id="out"></pre>
		<script>
		var console={log:function(s){document.getElementById("out").innerHTML+=s+"\n";}};
		var messageNum = 0;
		var ws = new WebSocket("` + fmt.Sprintf("ws%s://%s%s/echo", s, host, ports) + `")
		function send(){
			messageNum++;
            var msg = messageNum + ": " + new Date()
            console.log("send: " + msg)
            ws.send(msg)
        }
        ws.onopen = function(){
        	console.log("opened")
            send()
        }
        ws.onclose = function(){
            console.log("close")
        }
        ws.onerror = function(ev){
            console.log("error " + ev)
        }
        ws.onmessage = function(msg){
            console.log("recv: " + msg.data)
            if (messageNum == 10) {
                ws.close()
            } else {
                send()
            }
        }
		</script>
	`))
}
