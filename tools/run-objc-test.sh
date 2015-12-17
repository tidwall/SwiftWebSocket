#!/bin/bash

set -o pipefail

: ${BUILDTOOL:=xcodebuild} #Default

# Xcode Build Command Line
# https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/xcodebuild.1.html
: ${PROJECT:="SwiftWebSocket.xcodeproj"}
: ${SCHEME:="SwiftWebSocket-iOS"}
: ${TARGET:="Test-ObjectiveC"}
: ${SDK:="iphonesimulator"}

echo "Started: $(date)"

init() {
  # Launch the simulator before running the tests
  # Avoid "iPhoneSimulator: Timed out waiting"
  open -b com.apple.iphonesimulator
}

COMMAND="-project \"${PROJECT}\" -scheme \"${SCHEME}\" -sdk \"${SDK}\""

case "${BUILDTOOL}" in
  xctool) echo "Selected build tool: xctool"
  init
    # Tests (Swift & Objective-C)
  	case "${CLASS}" in
  	  "") echo "Testing all classes"
      COMMAND="xctool clean test "${COMMAND}
      ;;
      *) echo "Testing ${CLASS}"
      COMMAND="xctool clean test -only ${CLASS} "${COMMAND}
      ;;
  	esac
  ;;
  xcodebuild-travis) echo "Selected tool: xcodebuild + xcpretty (format: travisci)"
  init
    # Use xcpretty together with tee to store the raw log in a file, and get the pretty output in the terminal
    COMMAND="xcodebuild clean test "${COMMAND}" | tee xcodebuild.log | xcpretty -f `xcpretty-travis-formatter`"
  ;;
  xcodebuild-pretty) echo "Selected tool: xcodebuild + xcpretty"
  init
    COMMAND="xcodebuild clean test "${COMMAND}" | xcpretty --test"
  ;;
  xcodebuild) echo "Selected tool: xcodebuild"
  init
    COMMAND="xcodebuild clean test "${COMMAND}
  ;;
  *) echo "No build tool especified" && exit 2
esac

set -x
eval "${COMMAND}"
