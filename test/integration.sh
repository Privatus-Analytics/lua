#!/bin/sh
# Starts OpenResty with test/nginx.conf and checks the pages with curl.
# Run it inside the openresty/openresty alpine-fat image (see run-docker.sh).
set -eu

mkdir -p /tmp/privatus-test/logs
export PRIVATUS_SITE_ID=pa_TEST123456
export PRIVATUS_ENV=production
openresty -p /tmp/privatus-test -c /app/test/nginx.conf
trap 'openresty -p /tmp/privatus-test -c /app/test/nginx.conf -s stop 2>/dev/null || true' EXIT
sleep 1

base=http://127.0.0.1:8080
passed=0
failed=0

check() { # name, condition result
  if [ "$2" = 0 ]; then passed=$((passed + 1)); echo "ok - $1"; else failed=$((failed + 1)); echo "not ok - $1"; fi
}
has() { printf '%s' "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
lacks() { printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }

tag='<script defer src="https://privatusstats.com/js/pa.js" data-site="pa_TEST123456" data-modules="engage,auto"'

body=$(curl -s "$base/static.html")
headers=$(curl -s -D - -o /dev/null "$base/static.html" | tr -d '\r')
check "static page gets the tag before </head>" "$(has "$body" "$tag></script>
</head>")"
check "static page drops Content-Length" "$(lacks "$headers" "Content-Length")"
check "static page is sent in chunks" "$(has "$headers" "Transfer-Encoding: chunked")"

body=$(curl -s "$base/chunked")
check "chunked page gets the props script with the nonce" "$(has "$body" '<script nonce="n0nce">window.privatusPageProps=function(){return {"plan":"pro"}}</script>')"
check "chunked page gets data-props and the nonce on the tag" "$(has "$body" 'nonce="n0nce" data-props="privatusPageProps"></script>
</head><body>hi</body></html>')"

body=$(curl -s "$base/json")
check "JSON is left alone" "$(lacks "$body" "pa.js")"
headers=$(curl -s -D - -o /dev/null "$base/json" | tr -d '\r')
check "JSON keeps Content-Length" "$(has "$headers" "Content-Length: 18")"

check "encoded responses are left alone" "$(lacks "$(curl -s "$base/encoded")" "pa_TEST123456")"
check "pages with the tag are left alone" "$(lacks "$(curl -s "$base/already")" "pa_TEST123456")"
check "non 200 pages are left alone" "$(lacks "$(curl -s "$base/missing")" "pa.js")"
check "pages without a head are left alone" "$(has "$(curl -s "$base/nohead")" "<p>No head here</p>")"
check "Ajax requests are left alone" "$(lacks "$(curl -s -H 'X-Requested-With: XMLHttpRequest' "$base/static.html")" "pa.js")"
check "enabled = false per location" "$(lacks "$(curl -s "$base/off")" "pa.js")"

headers=$(curl -s -I "$base/static.html" | tr -d '\r')
check "HEAD keeps Content-Length" "$(has "$headers" "Content-Length:")"

body=$(curl -s "$base/big")
check "pages over max_buffer_size are sent unchanged" "$(lacks "$body" "pa.js")"
check "pages over max_buffer_size are complete" "$(has "$body" "</body></html>")"

if grep -q "\[error\]" /tmp/privatus-test/error.log; then
  failed=$((failed + 1)); echo "not ok - error log is clean"; cat /tmp/privatus-test/error.log
else
  passed=$((passed + 1)); echo "ok - error log is clean"
fi

echo "integration: $passed passed, $failed failed"
[ "$failed" = 0 ]
