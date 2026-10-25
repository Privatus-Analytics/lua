#!/bin/sh
# Runs busted, luacheck, the OpenResty integration test, a plain Lua 5.1 and
# 5.4 smoke test, and the rock build in a pinned OpenResty image.
# Usage: ./run-docker.sh
set -e
docker run --rm -v "$PWD":/src:ro openresty/openresty:1.27.1.2-alpine-fat sh -c 'set -e
  cp -r /src /app && cd /app
  apk add --no-cache -q lua5.1 lua5.4 zip >/dev/null
  luarocks install busted >/dev/null
  luarocks install luacheck >/dev/null
  luarocks install etlua >/dev/null
  busted -o utfTerminal
  luacheck .
  lua5.1 test/smoke.lua
  lua5.4 test/smoke.lua
  resty test/smoke.lua
  sh test/integration.sh
  luarocks lint lua-resty-privatus-1.0.0-1.rockspec
  luarocks make lua-resty-privatus-1.0.0-1.rockspec >/dev/null
  luarocks pack lua-resty-privatus 1.0.0-1
  printf "github_account = Privatus-Analytics\ngithub_token = none\nupload_server = https://opm.openresty.org\ndownload_server = https://opm.openresty.org\n" > /root/.opmrc
  opm build && echo "opm build ok"
  # The OPM tarball must never carry private notes, tests or the example app.
  if tar tzf lua-resty-privatus-*.tar.gz | grep -E "SUBMISSION|example/|spec/|run-docker"; then echo "opm tarball has files it must not"; exit 1; fi
'
