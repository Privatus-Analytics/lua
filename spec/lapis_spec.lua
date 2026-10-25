local helper = require("spec.helper")

describe("privatus.lapis", function()
  local privatus, lapis_helpers, lapis_env

  before_each(function()
    lapis_env = "production"
    package.loaded["lapis.config"] = { get = function() return { _name = lapis_env } end }
    package.loaded["privatus.lapis"] = nil
    privatus = helper.setup({ site_id = "pa_TEST123456" })
    lapis_helpers = require("privatus.lapis")
  end)

  after_each(function() package.loaded["lapis.config"] = nil end)

  it("adds helpers that Lapis calls with the request first", function()
    local request = { plan = "pro" }
    lapis_helpers.before_filter(request)
    privatus.configure({ props = function(req) return { plan = req.plan } end })
    local tag = request.privatus_tag(request)
    assert.truthy(tag:find('{"plan":"pro"}', 1, true))
    assert.equal('data-privatus-event="Saved"', request.privatus_event_attrs(request, "Saved"))
    assert.equal('data-privatus-click="nav.home"', request.privatus_click_attr(request, "nav.home"))
  end)

  it("uses the Lapis environment when PRIVATUS_ENV is not set", function()
    assert.truthy(lapis_helpers.tag({}):find("pa_TEST123456", 1, true))
    lapis_env = "development"
    assert.equal("", lapis_helpers.tag({}))
  end)

  it("lets PRIVATUS_ENV win over the Lapis environment", function()
    helper.env.PRIVATUS_ENV = "staging"
    assert.equal("", lapis_helpers.tag({}))
  end)
end)
