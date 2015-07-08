package main

import (
	"github.com/gorilla/websocket"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/", handler)
	log.Print("Running server on port 6789")
	http.ListenAndServe(":6789", nil)
}

func handler(w http.ResponseWriter, r *http.Request) {
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
		_, msg, err := ws.ReadMessage()
		if err != nil {
			log.Print(err)
			return
		}
		log.Print("rcvd: '" + string(msg) + "'")
	}
}
