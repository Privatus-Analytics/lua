-- Shared setup for the specs: a clean module and a fake environment.
package.path = "./lib/?.lua;./lib/?/init.lua;" .. package.path

local privatus = require("privatus")

local helper = { env = {}, warnings = {} }

function helper.setup(settings)
  privatus.reset()
  helper.env = {}
  helper.warnings = {}
  privatus.getenv = function(name) return helper.env[name] end
  privatus.warn = function(message) helper.warnings[#helper.warnings + 1] = message end
  privatus.configure(settings or {})
  return privatus
end

return helper
