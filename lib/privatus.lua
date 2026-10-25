-- Privatus Analytics for Lua.
--
-- Prints the cookieless Privatus Analytics script tag, the data attributes
-- the tracker reads for custom events and click maps, and the page props
-- script. Plain Lua 5.1 to 5.4 and LuaJIT. No other modules are needed.
--
-- It only builds HTML text. It never sends anything from the server, sets no
-- cookies and never reads IP addresses, user agents or any visitor id.

local M = {}

M.VERSION = "1.0.0"
M.DEFAULT_HOST = "https://privatusstats.com"
M.MARKER = "/js/pa.js"
M.PROPS_FUNCTION = "privatusPageProps"
M.QUEUE_STUB = "window.privatus=window.privatus||{q:[]};['track','pageview','props','optOut','optIn','ready']" ..
  ".forEach(function(m){window.privatus[m]=window.privatus[m]||function(){window.privatus.q.push(" ..
  "[m,Array.prototype.slice.call(arguments)])}})"

M.MAX_NAME = 120
M.MAX_KEY = 64
M.MAX_PROPS = 30
M.MAX_VALUE = 500
M.MAX_ITEMS = 30
M.MAX_CLICK = 100

M.SPA_MODES = { auto = true, history = true, hash = true, off = true }

-- Lua tables cannot hold nil. Use privatus.null where you mean "no value",
-- for example to remove one configured prop for one page. ngx.null and
-- cjson.null work too.
M.null = setmetatable({}, { __tostring = function() return "privatus.null" end })

-- Reads environment variables. Swap it out in tests.
M.getenv = os.getenv

-- Writes a warning, for example about a click map name that is not valid.
-- Uses the nginx error log inside OpenResty and stderr elsewhere.
function M.warn(message)
  local ngx = rawget(_G, "ngx")
  if type(ngx) == "table" and type(ngx.log) == "function" and ngx.WARN then
    ngx.log(ngx.WARN, message)
  else
    io.stderr:write(message, "\n")
  end
end

local function is_null(value)
  if value == nil or value == M.null then return true end
  local ngx = rawget(_G, "ngx")
  return type(ngx) == "table" and ngx.null ~= nil and value == ngx.null
end
M.is_null = is_null

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------

local REPLACEMENT = "\239\191\189" -- U+FFFD, for bytes that are not valid UTF-8

-- Returns the UTF-8 character that starts at byte i and the index after it.
-- A byte that does not start a valid character comes back as U+FFFD.
local function next_char(s, i)
  local c = s:byte(i)
  if c < 0x80 then return s:sub(i, i), i + 1 end
  local len, cp, min
  if c >= 0xC2 and c <= 0xDF then
    len, cp, min = 2, c - 0xC0, 0x80
  elseif c >= 0xE0 and c <= 0xEF then
    len, cp, min = 3, c - 0xE0, 0x800
  elseif c >= 0xF0 and c <= 0xF4 then
    len, cp, min = 4, c - 0xF0, 0x10000
  else
    return REPLACEMENT, i + 1
  end
  for j = i + 1, i + len - 1 do
    local b = s:byte(j)
    if not b or b < 0x80 or b > 0xBF then return REPLACEMENT, i + 1 end
    cp = cp * 64 + (b - 0x80)
  end
  if cp < min or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then
    return REPLACEMENT, i + 1
  end
  return s:sub(i, i + len - 1), i + len
end

-- Valid UTF-8 with at most max characters (not bytes).
local function cut(s, max)
  if #s <= max and not s:find("[\128-\255]") then return s end
  local out, i, n = {}, 1, 0
  while i <= #s and n < max do
    local char
    char, i = next_char(s, i)
    n = n + 1
    out[n] = char
  end
  return table.concat(out)
end
M.cut = cut

local function strip(s)
  return (s:match("^%s*(.-)%s*$"))
end

local HTML_ESCAPES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }

-- Escapes & < > " and ' for use in HTML text and attribute values.
function M.escape_html(value)
  return (tostring(value):gsub("[&<>\"']", HTML_ESCAPES))
end

-- Numbers as short text: 3, 1.5, 0.1. Nil for NaN and infinity.
local function number_text(n)
  if n ~= n or n == math.huge or n == -math.huge then return nil end
  if n == math.floor(n) and n > -1e15 and n < 1e15 then
    return string.format("%d", n)
  end
  for _, digits in ipairs({ 15, 16, 17 }) do
    local text = string.format("%." .. digits .. "g", n)
    if tonumber(text) == n then return text end
  end
  return string.format("%.17g", n)
end

-- Whether a table is a list: keys 1..n and nothing else. {} counts as a list.
local function is_list(t)
  if type(t) ~= "table" or is_null(t) then return false end
  local count = 0
  for key in pairs(t) do
    if type(key) ~= "number" then return false end
    count = count + 1
  end
  return count == #t
end

---------------------------------------------------------------------------
-- Prop keys and values
---------------------------------------------------------------------------

-- Lowercases a key, turns anything outside a-z 0-9 _ into _ (one _ per
-- character) and cuts it to 64 characters.
function M.normalize_key(key)
  local s = tostring(key)
  local out, i, n = {}, 1, 0
  while i <= #s and n < M.MAX_KEY do
    local char
    char, i = next_char(s, i)
    if #char == 1 then
      char = char:lower()
      if not char:find("^[a-z0-9_]$") then char = "_" end
    else
      char = "_"
    end
    n = n + 1
    out[n] = char
  end
  return table.concat(out)
end

-- Cleans keys only, keeping null values so a merge can remove a key.
-- Returns a map. When two keys clean to the same text, the one that sorts
-- last wins, so the result never depends on table order.
local function keyed(props)
  local map, entries = {}, {}
  if type(props) ~= "table" or is_null(props) then return map end
  for key, value in pairs(props) do
    entries[#entries + 1] = { M.normalize_key(key), tostring(key), value }
  end
  table.sort(entries, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[2] < b[2]
  end)
  for _, entry in ipairs(entries) do
    if entry[1] ~= "" then map[entry[1]] = entry[3] end
  end
  return map
end

-- Cleans props: keys as in normalize_key, null values dropped, at most 30.
-- Returns a list of { key, value } pairs sorted by key, because Lua tables
-- have no order of their own.
function M.normalize(props)
  local map, keys = keyed(props), {}
  for key, value in pairs(map) do
    if not is_null(value) then keys[#keys + 1] = key end
  end
  table.sort(keys)
  local out = {}
  for i = 1, math.min(#keys, M.MAX_PROPS) do
    out[i] = { keys[i], map[keys[i]] }
  end
  return out
end

-- A value as attribute text: true/false, numbers as written, lists joined
-- with commas. Nil when there is nothing to print.
local function scalar_text(value)
  local kind = type(value)
  if kind == "string" then return value end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return number_text(value) end
  return nil
end

local function string_value(value)
  local text
  if is_list(value) then
    local parts = {}
    for _, item in ipairs(value) do
      local part = not is_null(item) and scalar_text(item) or nil
      if part then parts[#parts + 1] = part end
    end
    text = table.concat(parts, ",")
  else
    text = scalar_text(value)
    if text == nil then return nil end
  end
  return cut(text, M.MAX_VALUE)
end

---------------------------------------------------------------------------
-- Event and click attributes
---------------------------------------------------------------------------

-- Turns a list of { name, value } pairs, or a map, into attribute HTML.
-- A map prints in name order. Every value is escaped. A value of true
-- prints the bare name.
function M.to_html(attrs)
  local pairs_list = attrs
  if not is_list(attrs) then
    pairs_list = {}
    for name, value in pairs(attrs or {}) do pairs_list[#pairs_list + 1] = { name, value } end
    table.sort(pairs_list, function(a, b) return tostring(a[1]) < tostring(b[1]) end)
  end
  local parts = {}
  for _, pair in ipairs(pairs_list) do
    local name, value = pair[1], pair[2]
    if value == true then
      parts[#parts + 1] = tostring(name)
    elseif not is_null(value) then
      parts[#parts + 1] = tostring(name) .. '="' .. M.escape_html(value) .. '"'
    end
  end
  return table.concat(parts, " ")
end

local function event_pairs(name, props)
  if is_null(name) then return {} end
  name = strip(cut(strip(tostring(name)), M.MAX_NAME))
  if name == "" then return {} end
  local list = { { "data-privatus-event", name } }
  for _, pair in ipairs(M.normalize(props)) do
    local value = string_value(pair[2])
    if value then list[#list + 1] = { "data-privatus-prop-" .. pair[1], value } end
  end
  return list
end

-- The event attributes as a map: { ["data-privatus-event"] = name,
-- ["data-privatus-prop-<key>"] = value, ... }. {} for an empty name.
function M.event_data(name, props)
  local map = {}
  for _, pair in ipairs(event_pairs(name, props)) do map[pair[1]] = pair[2] end
  return map
end

-- The event attributes as HTML to put inside a tag:
--   <button {{ event_attrs("Report exported", { format = "csv" }) }}>Export</button>
-- On a <form> the event is sent when the form is submitted.
-- Prints in every environment, even when the tag is off.
function M.event_attrs(name, props)
  return M.to_html(event_pairs(name, props))
end

-- Whether a click map name is valid: letters, digits, _ . : - and at most
-- 100 characters.
function M.valid_click(name)
  return type(name) == "string" and #name >= 1 and #name <= M.MAX_CLICK
    and name:find("^[A-Za-z0-9_%.:%-]+$") ~= nil
end

-- { ["data-privatus-click"] = name }, or {} when the name is not valid.
function M.click_data(name)
  if type(name) == "number" then name = tostring(name) end
  if M.valid_click(name) then return { ["data-privatus-click"] = name } end
  if (M.getenv("PRIVATUS_ENV") or "") ~= "production" then
    M.warn("[privatus] click map name " .. string.format("%q", tostring(name)) ..
      " is not valid. Use letters, digits and _ . : - only, at most 100 characters. Nothing was printed.")
  end
  return {}
end

-- The click map attribute as HTML: <a {{ click_attr("pricing.cta") }}>
-- Prints nothing when the name is not valid.
function M.click_attr(name)
  return M.to_html(M.click_data(name))
end

---------------------------------------------------------------------------
-- Page props JSON
---------------------------------------------------------------------------

local JSON_ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
  ["<"] = "\\u003c", [">"] = "\\u003e", ["&"] = "\\u0026",
}

-- A JSON string that is also safe inside a <script>: < > & U+2028 and
-- U+2029 are written as \u escapes.
function M.json_string(s)
  s = cut(s, #s) -- makes the text valid UTF-8
  s = s:gsub('[%z\1-\31"\\<>&]', function(char)
    return JSON_ESCAPES[char] or string.format("\\u%04x", char:byte())
  end)
  s = s:gsub("\226\128\168", "\\u2028"):gsub("\226\128\169", "\\u2029")
  return '"' .. s .. '"'
end

local function json_scalar(value)
  local kind = type(value)
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return number_text(value) end
  if kind == "string" then return M.json_string(cut(value, M.MAX_VALUE)) end
  return nil
end

local function json_value(value)
  if is_list(value) then
    local items = {}
    for _, item in ipairs(value) do
      if not is_null(item) then
        items[#items + 1] = item
        if #items == M.MAX_ITEMS then break end
      end
    end
    local out = {}
    for _, item in ipairs(items) do
      local json = json_scalar(item)
      if json then out[#out + 1] = json end
    end
    return "[" .. table.concat(out, ",") .. "]"
  end
  return json_scalar(value)
end

-- Page props as a JSON object string that is safe inside a <script>, or nil
-- when there is nothing to send. Numbers, booleans and lists keep their
-- JSON types. Keys print in sorted order.
function M.page_props_json(props)
  local parts = {}
  for _, pair in ipairs(M.normalize(props)) do
    local value = json_value(pair[2])
    if value then parts[#parts + 1] = M.json_string(pair[1]) .. ":" .. value end
  end
  if #parts == 0 then return nil end
  return "{" .. table.concat(parts, ",") .. "}"
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local function default_settings()
  return {
    -- site_id: the site id (starts with pa_). Falls back to PRIVATUS_SITE_ID.
    -- script_host: where /js/pa.js is served. Falls back to PRIVATUS_SCRIPT_HOST.
    -- modules: list of tracker modules. Not set keeps the tracker default.
    excluded_paths = {},
    -- domains: hostnames to count. Not set counts every host.
    -- spa: auto, history, hash or off.
    manual = false,
    -- enabled: true or false forces the tag on or off.
    -- environment: the current environment. Falls back to PRIVATUS_ENV.
    enabled_environments = { "production" },
    auto_inject = true,
    extra_attributes = {},
    props = {},
    queue_stub = false,
    -- nonce: a CSP nonce string, or a function(request) that returns one.
    max_buffer_size = 2 * 1024 * 1024,
  }
end

-- The current settings. Change them with privatus.configure.
M.settings = default_settings()

-- Merges a table of settings into the current ones. Use privatus.null to
-- clear one.
function M.configure(settings)
  for name, value in pairs(settings or {}) do
    if is_null(value) then M.settings[name] = nil else M.settings[name] = value end
  end
  return M.settings
end

-- Puts every setting back to its default. Handy in tests.
function M.reset()
  M.settings = default_settings()
  return M.settings
end

-- One setting, with the per call overrides on top.
local function option(overrides, name)
  local value
  if overrides and overrides[name] ~= nil then
    value = overrides[name]
  else
    value = M.settings[name]
  end
  if is_null(value) then return nil end
  return value
end

local function setting_or_env(overrides, name, env)
  local value = option(overrides, name)
  value = value ~= nil and strip(tostring(value)) or ""
  if value == "" then value = strip(M.getenv(env) or "") end
  return value
end

-- The site id, or nil when there is none.
function M.site_id(overrides)
  local value = setting_or_env(overrides, "site_id", "PRIVATUS_SITE_ID")
  return value ~= "" and value or nil
end

-- The script origin, without a trailing slash.
function M.script_host(overrides)
  local value = setting_or_env(overrides, "script_host", "PRIVATUS_SCRIPT_HOST")
  if value == "" then value = M.DEFAULT_HOST end
  return (value:gsub("/$", ""))
end

-- Whether the tag is on. enabled = true or false decides. Otherwise the tag
-- is on only when the environment (PRIVATUS_ENV) is in enabled_environments.
function M.enabled(overrides)
  local forced = option(overrides, "enabled")
  if forced ~= nil then return forced and true or false end
  local environment = option(overrides, "environment")
  if environment == nil or environment == "" then environment = M.getenv("PRIVATUS_ENV") or "development" end
  for _, name in ipairs(option(overrides, "enabled_environments") or {}) do
    if tostring(name) == tostring(environment) then return true end
  end
  return false
end

-- Whether the tag prints: there is a site id and the tag is on.
function M.render(overrides)
  return M.site_id(overrides) ~= nil and M.enabled(overrides)
end

---------------------------------------------------------------------------
-- The tag
---------------------------------------------------------------------------

local function call_with_request(value, overrides)
  if type(value) == "function" then return value(overrides and overrides.request) end
  return value
end

-- The configured props for this request (a table, or a function that gets
-- the request), with the per call props merged on top. privatus.null
-- removes one.
function M.page_props(overrides)
  local merged = keyed(call_with_request(M.settings.props, overrides))
  local more = overrides and overrides.props
  for key, value in pairs(keyed(call_with_request(more, overrides))) do merged[key] = value end
  return merged
end

local function nonce(overrides)
  local value = option(overrides, "nonce")
  value = call_with_request(value, overrides)
  if value == nil or value == false or is_null(value) or value == "" then return nil end
  return tostring(value)
end

-- nil stays nil. Anything else becomes a clean list of strings.
local function text_list(value)
  if value == nil then return nil end
  local items = type(value) == "table" and value or { value }
  local out = {}
  for _, item in ipairs(items) do
    for part in (scalar_text(item) or ""):gmatch("[^,]+") do
      part = strip(part)
      if part ~= "" then out[#out + 1] = part end
    end
  end
  return out
end

-- An ordered attribute list. Setting a name twice keeps its first place.
local function attribute_list()
  local list, index = {}, {}
  return list, function(name, value)
    if index[name] then
      list[index[name]][2] = value
    else
      list[#list + 1] = { name, value }
      index[name] = #list
    end
  end
end

local LIST_OPTIONS = {
  { "modules", "data-modules" }, { "excluded_paths", "data-exclude" }, { "domains", "data-domains" },
}

-- The tracker tag attributes as a list of { name, value } pairs.
function M.attributes(overrides)
  local list, set = attribute_list()
  set("defer", true)
  set("src", M.script_host(overrides) .. M.MARKER)
  set("data-site", M.site_id(overrides))
  for _, pair in ipairs(LIST_OPTIONS) do
    local values = text_list(option(overrides, pair[1]))
    -- Not set keeps the tracker default. An empty modules list loads none.
    if values and (pair[1] == "modules" or #values > 0) then set(pair[2], table.concat(values, ",")) end
  end
  local spa = tostring(option(overrides, "spa") or "")
  if M.SPA_MODES[spa] and spa ~= "auto" then set("data-spa", spa) end
  if option(overrides, "manual") == true then set("data-manual", "true") end
  local extra = option(overrides, "extra_attributes") or {}
  local names = {}
  for name in pairs(extra) do names[#names + 1] = tostring(name) end
  table.sort(names)
  for _, name in ipairs(names) do
    local value = extra[name]
    if not is_null(value) then set(name, value) end
  end
  local value = nonce(overrides)
  if value then set("nonce", value) end
  return list, set
end

local function inline_script(code, overrides)
  local value = nonce(overrides)
  local opening = value and ('<script nonce="' .. M.escape_html(value) .. '">') or "<script>"
  return opening .. code .. "</script>"
end

-- The queue stub script on its own (nonce included). Use it when you print
-- the tracker tag some other way. It prints even when the tag is off, so
-- privatus.track calls never fail.
function M.queue_stub(overrides)
  return inline_script(M.QUEUE_STUB, overrides)
end

-- The tracker tag, plus the queue stub and the page props script when they
-- are on. Without a site id or when the tag is off, it is only the queue
-- stub (when queue_stub is on) or "". The props function is not called then.
--
-- overrides: any setting for this call, plus request (passed to props and
-- nonce functions) and props (merged over the configured props).
function M.tag(overrides)
  if not M.render(overrides) then
    if option(overrides, "queue_stub") == true then return inline_script(M.QUEUE_STUB, overrides) end
    return ""
  end
  local props_json = M.page_props_json(M.page_props(overrides))
  local html = {}
  if option(overrides, "queue_stub") == true then html[#html + 1] = inline_script(M.QUEUE_STUB, overrides) end
  if props_json then
    html[#html + 1] = inline_script("window." .. M.PROPS_FUNCTION .. "=function(){return " .. props_json .. "}",
      overrides)
  end
  local attrs, set = M.attributes(overrides)
  if props_json then set("data-props", M.PROPS_FUNCTION) end
  html[#html + 1] = "<script " .. M.to_html(attrs) .. "></script>"
  return table.concat(html, "\n")
end

---------------------------------------------------------------------------
-- Adding the tag to a whole page
---------------------------------------------------------------------------

local HEAD_CLOSE = "</[Hh][Ee][Aa][Dd]>"

-- Puts the tag just before the first </head>. Leaves the page alone when it
-- has no </head>, already has /js/pa.js, or the tag is off.
function M.inject(html, overrides)
  if type(html) ~= "string" or html:find(M.MARKER, 1, true) or not M.render(overrides) then return html end
  local start, finish = html:find(HEAD_CLOSE)
  if not start then return html end
  local tag = M.tag(overrides)
  if tag == "" then return html end
  return html:sub(1, start - 1) .. tag .. "\n</head>" .. html:sub(finish + 1)
end

return M
