#!/bin/bash
set -e 

cd $(dirname "${BASH_SOURCE[0]}")
cd ..
jazzy -g https://github.com/tidwall/SwiftWebSocket -o docsb --skip-undocumented -a "Josh Baker" -m "SwiftWebSocket" -u "http://github.com/tidwall"

echo ".nav-group-name a[href=\"Extensions.html\"] { display: none; }" >> docsb/css/jazzy.css
echo ".nav-group-name a[href=\"Extensions.html\"] ~ ul { display: none; }" >> docsb/css/jazzy.css
printf "%s(\".nav-group-name a[href='Extensions.html']\").parent().hide()\n" "$" >> docsb/js/jazzy.js
printf "%s(\".nav-group-name a[href='../Extensions.html']\").parent().hide()\n" "$" >> docsb/js/jazzy.js
printf "%s(\"header .content-wrapper a[href='index.html']\").parent().html(\"<a href='index.html'>SwiftWebSocket Docs</a>\")\n" "$" >> docsb/js/jazzy.js
printf "%s(\"header .content-wrapper a[href='../index.html']\").parent().html(\"<a href='../index.html'>SwiftWebSocket Docs</a>\")\n" "$" >> docsb/js/jazzy.js

git checkout gh-pages
function cleanup {
	git reset
	git checkout master
}
trap cleanup EXIT
rm -rf docs
mv docsb docs
git add docs/
git commit -m "updated docs"
echo "Make sure to push the gh-pages branch"