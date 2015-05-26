#!/bin/bash

set -e

cd $(dirname "${BASH_SOURCE[0]}")

git checkout gh-pages
cleanup() {
	git checkout master	
}
trap cleanup EXIT

if [ -f "reports/build.png" ]; then
	cp -rf reports/build.png ../build.png
	git add ../build.png
fi
if [ -d "reports/clients/" ]; then
	cp -rf reports/clients/ ../results/
	git add ../results/
fi
git commit -m 'updated result'
git push
