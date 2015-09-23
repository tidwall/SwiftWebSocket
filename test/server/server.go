package main

import (
	"github.com/gorilla/websocket"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/client", client)
	http.HandleFunc("/echo", socket)
	log.Print("Running server on port 6789")
	log.Print("ws://localhost:6789/client  (javascript test client)")
	log.Print("ws://localhost:6789/echo    (echo socket)")
	http.ListenAndServe(":6789", nil)
}

func socket(w http.ResponseWriter, r *http.Request) {
	log.Print("connection established")
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
		Open the Javascript Console
		<script>
		var messageNum = 0;
		var ws = new WebSocket("ws://localhost:6789/echo")
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
