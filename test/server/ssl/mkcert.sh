#!/bin/bash

set -e
cd $(dirname "${BASH_SOURCE[0]}")

subj="$@"
if [ "$opts" == "" ]; then
	subj="/C=US/ST=Arizona/L=Tempe/O=Tidwall/OU=IT/CN=mytestdomain.com"
fi
rm -rf server.*
#openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 -keyout server.key -out server.cer -subj "$subj"
openssl genrsa -des3 -passout pass:x -out server.pass.key 2048
openssl rsa -passin pass:x -in server.pass.key -out server.key
rm server.pass.key
openssl req -new -key server.key -out server.csr -subj "/C=US/ST=Arizona/L=Tempe/O=Tidwall/CN=mytestdomain.com"
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.cer