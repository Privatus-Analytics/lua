local helper = require("spec.helper")

describe("event and click attributes", function()
  local privatus

  before_each(function() privatus = helper.setup() end)

  it("turns an event into data attributes", function()
    assert.same({
      ["data-privatus-event"] = "Export CSV",
      ["data-privatus-prop-format"] = "csv",
      ["data-privatus-prop-source"] = "toolbar",
    }, privatus.event_data("Export CSV", { format = "csv", source = "toolbar" }))
    assert.equal('data-privatus-event="Export CSV" data-privatus-prop-format="csv" data-privatus-prop-source="toolbar"',
      privatus.event_attrs("Export CSV", { format = "csv", source = "toolbar" }))
  end)

  it("trims the name and cuts it to 120 characters", function()
    assert.equal("Export CSV", privatus.event_data("  Export CSV  ")["data-privatus-event"])
    assert.equal(string.rep("a", 120), privatus.event_data(string.rep("a", 200))["data-privatus-event"])
  end)

  it("counts characters, not bytes, when it cuts", function()
    local name = privatus.event_data(string.rep("é", 130))["data-privatus-event"]
    assert.equal(string.rep("é", 120), name)
  end)

  it("gives nothing for an empty name", function()
    assert.same({}, privatus.event_data("   ", { format = "csv" }))
    assert.same({}, privatus.event_data(nil))
    assert.equal("", privatus.event_attrs("", { format = "csv" }))
  end)

  it("lowercases, cleans and cuts prop keys", function()
    local attrs = privatus.event_data("Saved", { ["Report Type"] = "a", ["x-y"] = "b", [string.rep("K", 80)] = "c" })
    assert.equal("a", attrs["data-privatus-prop-report_type"])
    assert.equal("b", attrs["data-privatus-prop-x_y"])
    assert.equal("c", attrs["data-privatus-prop-" .. string.rep("k", 64)])
  end)

  it("turns each non ASCII character in a key into one underscore", function()
    assert.equal("caf_", privatus.normalize_key("Café"))
  end)

  it("turns values into text and drops null values", function()
    local attrs = privatus.event_data("Saved", {
      on = true, off = false, count = 3, ratio = 1.5, tags = { "a", "b" }, gone = privatus.null,
    })
    assert.equal("true", attrs["data-privatus-prop-on"])
    assert.equal("false", attrs["data-privatus-prop-off"])
    assert.equal("3", attrs["data-privatus-prop-count"])
    assert.equal("1.5", attrs["data-privatus-prop-ratio"])
    assert.equal("a,b", attrs["data-privatus-prop-tags"])
    assert.is_nil(attrs["data-privatus-prop-gone"])
  end)

  it("cuts values to 500 characters and keeps at most 30 props", function()
    local props = {}
    for i = 1, 40 do props["p" .. i] = "v" end
    local count = 0
    for _ in pairs(privatus.event_data("Saved", props)) do count = count + 1 end
    assert.equal(31, count)
    assert.equal(500, #privatus.event_data("Saved", { long = string.rep("x", 900) })["data-privatus-prop-long"])
  end)

  it("prints props in key order", function()
    assert.equal('data-privatus-event="E" data-privatus-prop-a="1" data-privatus-prop-b="2" data-privatus-prop-c="3"',
      privatus.event_attrs("E", { c = 3, a = 1, b = 2 }))
  end)

  it("escapes every value for HTML", function()
    assert.equal('data-privatus-event="Say &quot;hi&quot; &lt;now&gt;" data-privatus-prop-note="a&amp;b&#39;"',
      privatus.event_attrs('Say "hi" <now>', { note = "a&b'" }))
  end)

  it("prints even when the tag is off", function()
    privatus.configure({ enabled = false })
    assert.equal('data-privatus-event="Saved"', privatus.event_attrs("Saved"))
  end)

  it("turns a valid click name into a data attribute", function()
    assert.equal('data-privatus-click="pricing.cta"', privatus.click_attr("pricing.cta"))
    assert.same({ ["data-privatus-click"] = "a-b_c:d.1" }, privatus.click_data("a-b_c:d.1"))
  end)

  it("gives nothing for an invalid click name and warns outside production", function()
    for _, name in ipairs({ "", "has space", string.rep("x", 101), "<b>" }) do
      assert.equal("", privatus.click_attr(name))
    end
    assert.equal("", privatus.click_attr(nil))
    assert.equal(5, #helper.warnings)
    assert.truthy(helper.warnings[1]:find("not valid", 1, true))
  end)

  it("does not warn in production", function()
    helper.env.PRIVATUS_ENV = "production"
    assert.equal("", privatus.click_attr("has space"))
    assert.equal(0, #helper.warnings)
  end)
end)
