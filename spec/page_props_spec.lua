local helper = require("spec.helper")

describe("page props JSON", function()
  local privatus

  before_each(function() privatus = helper.setup() end)

  it("turns props into a JSON object", function()
    assert.equal('{"plan":"pro","role":"admin"}', privatus.page_props_json({ plan = "pro", role = "admin" }))
  end)

  it("gives nil for empty props", function()
    assert.is_nil(privatus.page_props_json({}))
    assert.is_nil(privatus.page_props_json(nil))
    assert.is_nil(privatus.page_props_json({ gone = privatus.null }))
  end)

  it("keeps numbers, booleans and lists as JSON types", function()
    assert.equal('{"beta":true,"flags":["a","b",3],"old":false,"ratio":1.5,"seats":5}',
      privatus.page_props_json({
        seats = 5, ratio = 1.5, beta = true, old = false, flags = { "a", privatus.null, "b", 3 },
      }))
  end)

  it("cleans keys like event props", function()
    assert.equal('{"app_version":"2.1"}', privatus.page_props_json({ ["App Version"] = "2.1" }))
  end)

  it("limits props, list items and value length", function()
    local many, list = {}, {}
    for i = 1, 40 do many["p" .. i] = i end
    for i = 1, 50 do list[i] = tostring(i) end
    local _, commas = privatus.page_props_json(many):gsub(",", "")
    assert.equal(29, commas)
    local _, items = privatus.page_props_json({ list = list }):gsub('"%d+"', "")
    assert.equal(30, items)
    assert.equal('{"long":"' .. string.rep("x", 500) .. '"}', privatus.page_props_json({ long = string.rep("x", 900) }))
  end)

  it("is safe inside a script tag", function()
    local json = privatus.page_props_json({ note = "</script><b>&\226\128\168\226\128\169" })
    assert.equal('{"note":"\\u003c/script\\u003e\\u003cb\\u003e\\u0026\\u2028\\u2029"}', json)
    assert.is_nil(json:find("[<>&]"))
  end)

  it("escapes quotes, backslashes and control characters", function()
    assert.equal('{"q":"a\\"b\\\\c\\n\\t\\u0001"}', privatus.page_props_json({ q = 'a"b\\c\n\t\1' }))
  end)

  it("keeps UTF-8 text and replaces broken bytes", function()
    assert.equal('{"bad":"\239\191\189x","city":"Zürich"}',
      privatus.page_props_json({ city = "Zürich", bad = "\255x" }))
  end)

  it("drops values JSON cannot hold", function()
    assert.equal('{"ok":1}', privatus.page_props_json({ ok = 1, nan = 0 / 0, inf = math.huge, map = { a = 1 } }))
  end)
end)
