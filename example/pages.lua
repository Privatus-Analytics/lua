-- The pages of the conformance example app. Each page prints the tag with
-- require("resty.privatus").tag(), the helper the README shows.
local privatus = require("resty.privatus")

local NONCE = "testnonce"
local NASTY = "</script><script>window.__pwned=1</script>\226\128\168\226\128\169&<>\"'"

local function page_props(extra)
  local props = { plan = "pro", role = "admin", beta = true, seats = 3 }
  for key, value in pairs(extra or {}) do props[key] = value end
  return props
end

local function layout(title, head, body)
  return "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>" .. title ..
    "</title>\n" .. head .. "\n</head>\n<body>\n" .. body .. "\n</body>\n</html>\n"
end

local pages = {}

function pages.home()
  return layout("Home", privatus.tag({ props = page_props(), queue_stub = true }), "<h1>Home</h1>")
end

function pages.event()
  return layout("Events", privatus.tag({ props = page_props(), queue_stub = true }), table.concat({
    "<h1>Events</h1>",
    '<button type="button" ' .. privatus.event_attrs("Report exported", { format = "csv", source = "toolbar" }) ..
      ">Export report</button>",
    '<p><a href="#pricing" ' .. privatus.click_attr("pricing.cta") .. ">Pricing</a></p>",
    '<form action="/event" method="get" ' .. privatus.event_attrs("Signup form") .. ">",
    '  <button type="submit">Sign up</button>',
    "</form>",
  }, "\n"))
end

function pages.nasty()
  return layout("Nasty", privatus.tag({ props = page_props({ nasty = NASTY }), queue_stub = true }),
    '<h1>Nasty values</h1>\n<button type="button" ' .. privatus.event_attrs("Nasty value", { nasty = NASTY }) ..
      ">Nasty</button>")
end

-- Off with the queue stub on prints only the stub, so privatus.track still
-- works. Off with the stub off prints nothing.
local function off(queue_stub)
  return "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>Off</title>\n" ..
    '<meta name="privatus-off-start">' ..
    privatus.tag({ enabled = false, props = page_props(), queue_stub = queue_stub }) ..
    '<meta name="privatus-off-end">\n</head>\n<body><h1>Off</h1></body>\n</html>\n'
end

function pages.off() return off(true) end
function pages.off_plain() return off(false) end

-- No tag in the page. The filters on this location add it.
function pages.auto()
  return "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<title>Auto inject</title>\n" ..
    "</head>\n<body><h1>Auto inject</h1><p>No tag in the template. The middleware adds it.</p></body>\n</html>\n"
end

local M = {}

function M.serve(name)
  ngx.header["Content-Type"] = "text/html; charset=utf-8"
  ngx.header["Content-Security-Policy"] = "script-src 'nonce-" .. NONCE .. "' " .. privatus.core.script_host()
  ngx.print(pages[name]())
end

return M
