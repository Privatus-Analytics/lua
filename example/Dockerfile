# Conformance example app (OpenResty). Build with the package folder as the
# context:  docker build -f example/Dockerfile .
FROM openresty/openresty:1.27.1.2-alpine
# The package from this repo's own source, not from OPM or LuaRocks, copied
# where OpenResty looks for Lua modules (the same place opm installs to).
COPY lib/ /usr/local/openresty/site/lualib/
COPY example/pages.lua /app/pages.lua
COPY example/nginx.conf /app/nginx.conf
EXPOSE 8080
CMD ["openresty", "-p", "/usr/local/openresty/nginx/", "-c", "/app/nginx.conf"]
