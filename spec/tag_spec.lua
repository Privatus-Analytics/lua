local helper = require("spec.helper")

local BASIC = '<script defer src="https://privatusstats.com/js/pa.js" data-site="pa_TEST123456"></script>'

describe("the tag", function()
  local privatus

  before_each(function() privatus = helper.setup({ site_id = "pa_TEST123456", enabled = true }) end)

  it("prints the basic snippet", function()
    assert.equal(BASIC, privatus.tag())
  end)

  it("prints nothing without a site id", function()
    privatus.configure({ site_id = privatus.null })
    assert.equal("", privatus.tag())
  end)

  it("reads the site id and script host from the environment", function()
    privatus.configure({ site_id = privatus.null })
    helper.env.PRIVATUS_SITE_ID = " pa_ENV "
    helper.env.PRIVATUS_SCRIPT_HOST = "https://stats.example.com/"
    assert.equal('<script defer src="https://stats.example.com/js/pa.js" data-site="pa_ENV"></script>', privatus.tag())
  end)

  it("is off outside production unless enabled is set", function()
    privatus.configure({ enabled = privatus.null })
    assert.equal("", privatus.tag())
    helper.env.PRIVATUS_ENV = "staging"
    assert.equal("", privatus.tag())
    helper.env.PRIVATUS_ENV = "production"
    assert.equal(BASIC, privatus.tag())
  end)

  it("enabled = false forces it off in production", function()
    helper.env.PRIVATUS_ENV = "production"
    privatus.configure({ enabled = false })
    assert.equal("", privatus.tag())
  end)

  it("uses enabled_environments and environment", function()
    privatus.configure({ enabled = privatus.null, enabled_environments = { "production", "staging" } })
    assert.equal(BASIC, privatus.tag({ environment = "staging" }))
    assert.equal("", privatus.tag({ environment = "development" }))
  end)

  it("adds modules and exclusions", function()
    privatus.configure({ modules = { "engage", "auto" }, excluded_paths = { "/admin/*", "/preview/*" } })
    local tag = privatus.tag()
    assert.truthy(tag:find('data-modules="engage,auto"', 1, true))
    assert.truthy(tag:find('data-exclude="/admin/*,/preview/*"', 1, true))
  end)

  it("loads no modules for an empty list", function()
    privatus.configure({ modules = {} })
    assert.truthy(privatus.tag():find('data-modules=""', 1, true))
  end)

  it("adds domains, spa mode and manual mode", function()
    privatus.configure({ domains = "example.com, www.example.com", spa = "hash", manual = true })
    assert.equal('<script defer src="https://privatusstats.com/js/pa.js" data-site="pa_TEST123456" ' ..
      'data-domains="example.com,www.example.com" data-spa="hash" data-manual="true"></script>', privatus.tag())
  end)

  it("ignores an unknown spa mode and the auto default", function()
    assert.is_nil(privatus.tag({ spa = "bogus" }):find("data-spa"))
    assert.is_nil(privatus.tag({ spa = "auto" }):find("data-spa"))
  end)

  it("escapes attribute values", function()
    privatus.configure({ excluded_paths = { '/a"b' } })
    assert.truthy(privatus.tag():find('data-exclude="/a&quot;b"', 1, true))
  end)

  it("lets per call options override the settings", function()
    privatus.configure({ modules = { "engage" } })
    assert.truthy(privatus.tag({ modules = { "vitals" } }):find('data-modules="vitals"', 1, true))
    assert.is_nil(privatus.tag({ modules = privatus.null }):find("data-modules"))
  end)

  it("adds extra attributes and a nonce", function()
    privatus.configure({ extra_attributes = { ["data-mask"] = "/orders/*->/orders/:id", ["data-debug"] = true } })
    local tag = privatus.tag({ nonce = "abc123" })
    assert.truthy(tag:find('data-mask="/orders/*-&gt;/orders/:id"', 1, true))
    assert.truthy(tag:find(' data-debug ', 1, true))
    assert.truthy(tag:find('nonce="abc123"', 1, true))
  end)

  it("calls a nonce function with the request", function()
    privatus.configure({ nonce = function(request) return request.nonce end })
    assert.truthy(privatus.tag({ request = { nonce = "n1" } }):find('nonce="n1"', 1, true))
  end)

  it("prints page props before the tag and data-props on it", function()
    assert.equal('<script>window.privatusPageProps=function(){return {"plan":"pro","role":"admin"}}</script>\n' ..
      '<script defer src="https://privatusstats.com/js/pa.js" data-site="pa_TEST123456" ' ..
      'data-props="privatusPageProps"></script>', privatus.tag({ props = { plan = "pro", role = "admin" } }))
  end)

  it("gives the props script the nonce", function()
    local html = privatus.tag({ props = { plan = "pro" }, nonce = "abc" })
    assert.equal(1, html:find('<script nonce="abc">window.privatusPageProps=', 1, true))
  end)

  it("prints no props script for empty props", function()
    assert.is_nil(privatus.tag({ props = { plan = privatus.null } }):find("privatusPageProps"))
  end)

  it("accepts configured props as a table or a function of the request", function()
    privatus.configure({ props = { plan = "pro" } })
    assert.truthy(privatus.tag():find('{"plan":"pro"}', 1, true))
    privatus.configure({ props = function(request) return { plan = request.plan } end })
    assert.truthy(privatus.tag({ request = { plan = "team" } }):find('{"plan":"team"}', 1, true))
  end)

  it("merges per call props over configured props and null removes one", function()
    privatus.configure({ props = { plan = "pro", role = "admin" } })
    local html = privatus.tag({ props = { role = privatus.null, tier = "gold" } })
    assert.truthy(html:find('{"plan":"pro","tier":"gold"}', 1, true))
  end)

  it("does not call the props function when the tag is off", function()
    privatus.configure({ enabled = false, props = function() error("should not run") end })
    assert.equal("", privatus.tag())
  end)

  it("prints the official queue stub first", function()
    privatus.configure({ queue_stub = true })
    local html = privatus.tag({ nonce = "abc", props = { plan = "pro" } })
    local parts = {}
    for line in html:gmatch("[^\n]+") do parts[#parts + 1] = line end
    assert.equal('<script nonce="abc">' .. privatus.QUEUE_STUB .. "</script>", parts[1])
    assert.truthy(parts[2]:find("privatusPageProps", 1, true))
    assert.truthy(parts[3]:find("/js/pa.js", 1, true))
  end)

  it("uses the official queue stub", function()
    assert.equal("window.privatus=window.privatus||{q:[]};['track','pageview','props','optOut','optIn','ready']" ..
      ".forEach(function(m){window.privatus[m]=window.privatus[m]||function(){window.privatus.q.push(" ..
      "[m,Array.prototype.slice.call(arguments)])}})", privatus.QUEUE_STUB)
  end)

  it("switches the queue stub on per call", function()
    assert.truthy(privatus.tag({ queue_stub = true }):find("q:[]", 1, true))
    assert.is_nil(privatus.tag():find("q:[]", 1, true))
    assert.equal('<script nonce="x">' .. privatus.QUEUE_STUB .. "</script>", privatus.queue_stub({ nonce = "x" }))
  end)

  describe("when the tag is off", function()
    local stub = '<script nonce="abc">' .. require("privatus").QUEUE_STUB .. "</script>"
    local boom = function() error("should not run") end

    it("prints exactly the queue stub, with the nonce, when the stub is on", function()
      privatus.configure({ enabled = false, queue_stub = true, props = boom })
      assert.equal(stub, privatus.tag({ nonce = "abc", props = { plan = "pro" } }))
      assert.equal("<script>" .. privatus.QUEUE_STUB .. "</script>", privatus.tag())
    end)

    it("prints nothing when the stub is off", function()
      privatus.configure({ enabled = false })
      assert.equal("", privatus.tag({ nonce = "abc", props = { plan = "pro" } }))
    end)

    it("prints only the stub without a site id", function()
      privatus.configure({ site_id = privatus.null, queue_stub = true, props = boom })
      assert.equal(stub, privatus.tag({ nonce = "abc", props = { plan = "pro" } }))
    end)

    it("prints only the stub outside production", function()
      privatus.configure({ enabled = privatus.null, queue_stub = true })
      helper.env.PRIVATUS_ENV = "development"
      assert.equal(stub, privatus.tag({ nonce = "abc" }))
    end)

    it("prints only the stub when turned off per call", function()
      assert.equal(stub, privatus.tag({ enabled = false, queue_stub = true, nonce = "abc", props = { plan = "pro" } }))
    end)

    it("still gives the stub from queue_stub()", function()
      privatus.configure({ enabled = false })
      assert.equal(stub, privatus.queue_stub({ nonce = "abc" }))
    end)
  end)
end)

describe("inject", function()
  local privatus

  before_each(function() privatus = helper.setup({ site_id = "pa_TEST123456", enabled = true }) end)

  it("puts the tag before </head>", function()
    assert.equal("<html><head><title>x</title>" .. BASIC .. "\n</head><body></body></html>",
      privatus.inject("<html><head><title>x</title></head><body></body></html>"))
  end)

  it("finds </HEAD> in any case and only the first one", function()
    assert.equal("<HEAD>" .. BASIC .. "\n</head>x</head>", privatus.inject("<HEAD></HEAD>x</head>"))
  end)

  it("leaves pages that already have the tag or have no head", function()
    local page = '<head><script src="/js/pa.js"></script></head>'
    assert.equal(page, privatus.inject(page))
    assert.equal("<p>hi</p>", privatus.inject("<p>hi</p>"))
  end)

  it("leaves pages alone when the tag is off", function()
    assert.equal("<head></head>", privatus.inject("<head></head>", { enabled = false }))
  end)

  it("adds nothing when the tag is off, even with the queue stub on", function()
    assert.equal("<head></head>", privatus.inject("<head></head>", { enabled = false, queue_stub = true }))
    assert.equal("<head></head>", privatus.inject("<head></head>", { site_id = privatus.null, queue_stub = true }))
  end)

  it("keeps % signs in the tag as they are", function()
    privatus.configure({ excluded_paths = { "/100%25" } })
    assert.truthy(privatus.inject("<head></head>"):find('data-exclude="/100%25"', 1, true))
  end)
end)
