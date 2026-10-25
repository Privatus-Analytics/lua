-- Privatus Analytics for OpenResty.
--
-- A header filter and body filter pair that adds the tracking script just
-- before </head> in HTML pages:
--
--   init_by_lua_block {
--     require("resty.privatus").configure({ site_id = "pa_YOURSITEID" })
--   }
--   header_filter_by_lua_block { require("resty.privatus").header_filter() }
--   body_filter_by_lua_block   { require("resty.privatus").body_filter() }
--
-- It only changes the HTML. It never sends anything from the server.

local privatus = require("privatus")

local _M = {
  _VERSION = privatus.VERSION,
  core = privatus,
  configure = privatus.configure,
  reset = privatus.reset,
  event_attrs = privatus.event_attrs,
  event_data = privatus.event_data,
  click_attr = privatus.click_attr,
  click_data = privatus.click_data,
  null = privatus.null,
}

local function header(name)
  local value = ngx.header[name]
  if type(value) == "table" then value = value[1] end
  return value
end

-- What props and nonce functions get as their request argument.
function _M.request()
  return {
    method = ngx.req.get_method(),
    uri = ngx.var.uri,
    args = ngx.var.args,
    host = ngx.var.host,
    var = ngx.var,
    ctx = ngx.ctx,
  }
end

local function with_request(overrides)
  local copy = {}
  for name, value in pairs(overrides or {}) do copy[name] = value end
  if copy.request == nil then copy.request = _M.request() end
  return copy
end

-- The tag for this request, for templates you render in a content handler.
-- Props and nonce functions get the request from _M.request().
function _M.tag(overrides)
  return privatus.tag(with_request(overrides))
end

-- The queue stub for this request, when you print the tag yourself.
function _M.queue_stub(overrides)
  return privatus.queue_stub(with_request(overrides))
end

-- Whether this response should get the tag. Call it in header_filter.
function _M.should_inject(overrides)
  local auto = overrides and overrides.auto_inject
  if auto == nil then auto = privatus.settings.auto_inject end
  if auto == false then return false end
  if ngx.status ~= 200 or ngx.req.get_method() == "HEAD" then return false end
  local content_type = header("Content-Type")
  if not content_type or not content_type:lower():find("^%s*text/html") then return false end
  if header("Content-Encoding") then return false end
  local requested_with = ngx.var.http_x_requested_with
  if requested_with and requested_with:lower() == "xmlhttprequest" then return false end
  return privatus.render(overrides)
end

-- Run in header_filter_by_lua*. Removes Content-Length from HTML pages that
-- may get the tag, so nginx sends the changed page in chunks. Other
-- responses are left alone and are not buffered.
function _M.header_filter(overrides)
  if not _M.should_inject(overrides) then return end
  ngx.header["Content-Length"] = nil
  ngx.ctx.privatus = { overrides = overrides or {}, buffer = {}, size = 0 }
end

-- Run in body_filter_by_lua*. Keeps the HTML until the last chunk, then
-- adds the tag before </head> and sends the whole page.
function _M.body_filter()
  local state = ngx.ctx.privatus
  if not state or state.done then return end

  local chunk, eof = ngx.arg[1], ngx.arg[2]
  if chunk and chunk ~= "" then
    state.size = state.size + #chunk
    state.buffer[#state.buffer + 1] = chunk
  end

  local limit = state.overrides.max_buffer_size or privatus.settings.max_buffer_size
  if limit and state.size > limit then
    -- Too big to hold in memory: send it unchanged.
    state.done = true
    ngx.arg[1] = table.concat(state.buffer)
    state.buffer = nil
    return
  end

  if not eof then
    ngx.arg[1] = nil
    return
  end

  state.done = true
  local html = table.concat(state.buffer)
  state.buffer = nil
  local ok, result = pcall(privatus.inject, html, with_request(state.overrides))
  if not ok then
    ngx.log(ngx.ERR, "[privatus] could not add the tag: ", result)
    result = html
  end
  ngx.arg[1] = result
end

return _M
