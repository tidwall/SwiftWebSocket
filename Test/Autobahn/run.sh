#!/bin/bash

#export PATH=/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin:"${PATH}"

cd $(dirname "${BASH_SOURCE[0]}")
WSTEST=$(ls $HOME/Library/Python/2.*/bin/wstest 2>/dev/null)
set -e
if [ ! -f "$WSTEST" ] || [ "$UPGRADE" == "1" ]; then
	pip install --user --upgrade unittest2
	pip install --user --upgrade autobahntestsuite
	WSTEST=$(ls $HOME/Library/Python/2.*/bin/wstest)
fi
if [ "$SERVER" == "1" ]; then
	$WSTEST -m fuzzingserver
	exit
fi 
if [ "$CLIENT" != "1" ]; then
	$WSTEST -m fuzzingserver &
	WSTEST_PID=$!
	cleanup() {
		kill $WSTEST_PID
		if [ "$SUCCESS" == "1" ]; then
			cp -f res/passing.png reports/build.png
			printf "\033[0;32m[SUCCESS]\033[0m\n"
		else
			if [ -d "reports/clients/" ]; then
				cp -f res/failing.png reports/build.png
				printf "\033[0;31m[FAILURE]\033[0m\n"
			else
				printf "\033[0;31m[FAILURE]\033[0m Cancelled Early\n"
				exit
			fi
		fi
		printf "\033[0;33mDon't forget to run 'test/gh-pages.sh' to process the results.\033[0m\n"
	}
	trap cleanup EXIT
	sleep 1
fi
printf "\033[0;33m[BUILDING]\033[0m\n"
rm -fr reports
mkdir -p reports
mkdir -p /tmp/SwiftWebSocket/tests

cat ../../Source/WebSocket.swift > /tmp/SwiftWebSocket/tests/main.swift
echo "" >> /tmp/SwiftWebSocket/tests/main.swift
cat autobahn.swift >> /tmp/SwiftWebSocket/tests/main.swift
#swift -Ounchecked /tmp/SwiftWebSocket/tests/main.swift
swift /tmp/SwiftWebSocket/tests/main.swift

SUCCESS=1
