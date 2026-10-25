-- Checks the core module on plain Lua (5.1 to 5.4) without busted or nginx:
--   lua5.1 test/smoke.lua
package.path = "./lib/?.lua;" .. package.path
local privatus = require("privatus")

privatus.configure({ site_id = "pa_TEST123456", enabled = true })
local tag = privatus.tag({ props = { plan = "pro", seats = 3, ratio = 0.1, flags = { "a", true } } })
assert(tag == '<script>window.privatusPageProps=function(){return {"flags":["a",true],"plan":"pro","ratio":0.1,' ..
  '"seats":3}}</script>\n<script defer src="https://privatusstats.com/js/pa.js" data-site="pa_TEST123456" ' ..
  'data-props="privatusPageProps"></script>', tag)
assert(privatus.event_attrs("Report exported", { format = "csv", count = 2 }) ==
  'data-privatus-event="Report exported" data-privatus-prop-count="2" data-privatus-prop-format="csv"')
assert(privatus.click_attr("pricing.cta") == 'data-privatus-click="pricing.cta"')
assert(privatus.page_props_json({ note = "</script>\226\128\168" }) == '{"note":"\\u003c/script\\u003e\\u2028"}')
assert(privatus.event_data(string.rep("é", 130))["data-privatus-event"] == string.rep("é", 120))
print(_VERSION .. ": smoke ok")
