-- Privatus Analytics helpers for Lapis.
--
--   local privatus_lapis = require("privatus.lapis")
--   app:before_filter(privatus_lapis.before_filter)
--
-- Then in an etlua view (use <%- so the HTML is not escaped again):
--
--   <%- privatus_tag() %>
--   <button <%- privatus_event_attrs("Report exported", { format = "csv" }) %>>Export</button>
--   <a href="/pricing" <%- privatus_click_attr("pricing.cta") %>>See plans</a>
--
-- Props and nonce functions get the Lapis request (self).

local privatus = require("privatus")

local M = { core = privatus }

-- PRIVATUS_ENV when it is set, else the Lapis environment name.
function M.environment()
  local env = privatus.getenv("PRIVATUS_ENV")
  if env and env ~= "" then return env end
  local ok, config = pcall(require, "lapis.config")
  if not ok or type(config) ~= "table" or type(config.get) ~= "function" then return nil end
  local got, conf = pcall(config.get)
  if got and type(conf) == "table" then return conf._name end
  return nil
end

local function with_request(request, overrides)
  local copy = {}
  for name, value in pairs(overrides or {}) do copy[name] = value end
  if copy.request == nil then copy.request = request end
  if copy.environment == nil and privatus.settings.environment == nil then copy.environment = M.environment() end
  return copy
end

-- The tag for this request. In views: <%- privatus_tag() %> or
-- <%- privatus_tag({ props = { section = "billing" } }) %>.
function M.tag(request, overrides)
  return privatus.tag(with_request(request, overrides))
end

-- The queue stub for this request.
function M.queue_stub(request, overrides)
  return privatus.queue_stub(with_request(request, overrides))
end

function M.event_attrs(_, name, props)
  return privatus.event_attrs(name, props)
end

function M.event_data(_, name, props)
  return privatus.event_data(name, props)
end

function M.click_attr(_, name)
  return privatus.click_attr(name)
end

function M.click_data(_, name)
  return privatus.click_data(name)
end

-- Lapis calls request functions with the request first, in views and in
-- actions (self:privatus_tag()).
M.helpers = {
  privatus_tag = M.tag,
  privatus_queue_stub = M.queue_stub,
  privatus_event_attrs = M.event_attrs,
  privatus_event_data = M.event_data,
  privatus_click_attr = M.click_attr,
  privatus_click_data = M.click_data,
}

-- Adds the helpers to each request. Use with app:before_filter.
function M.before_filter(request)
  for name, fn in pairs(M.helpers) do request[name] = fn end
end

return M
