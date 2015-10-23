#!/bin/bash

export GOPATH=$(cd $(dirname "${BASH_SOURCE[0]}"); pwd)
cd $GOPATH

go get "github.com/gorilla/websocket"
go run server.go $@
