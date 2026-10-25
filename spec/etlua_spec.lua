-- Runs the etlua example from the README.
local helper = require("spec.helper")
local has_etlua, etlua = pcall(require, "etlua")

describe("etlua example", function()
  it("renders the tag and attributes", function()
    if not has_etlua then
      pending("etlua is not installed")
      return
    end
    local privatus = helper.setup({ site_id = "pa_TEST123456", enabled = true })
    local template = assert(etlua.compile([[
<head>
  <%- privatus.tag() %>
</head>
<button <%- privatus.event_attrs("Report exported", { format = "csv" }) %>>Export</button>
<a href="/pricing" <%- privatus.click_attr("pricing.cta") %>>See plans</a>
]]))
    local html = template({ privatus = privatus })
    assert.truthy(html:find('data-site="pa_TEST123456"', 1, true))
    assert.truthy(html:find('<button data-privatus-event="Report exported" data-privatus-prop-format="csv">', 1, true))
    assert.truthy(html:find('<a href="/pricing" data-privatus-click="pricing.cta">', 1, true))
  end)
end)
