# Privatus Analytics for Lua and OpenResty

**Real visitor numbers for your Lua web app. No cookies, no cookie pop-up, no bots.**

You want to know if people use your Lua web app. But Google Analytics uses
cookies, so in many countries you must show a cookie pop-up first (the box that
asks visitors to say yes to cookies). Many people click no, so they never show
up in your numbers. Bots add fake visits on top.

This package adds the Privatus Analytics script to your site. On OpenResty
(nginx with Lua) it puts the script in the head of every HTML page for you.
Lapis views get a few helpers, and the plain Lua core works in any Lua app. The
script sets no cookies and keeps no IP addresses. Bots are filtered out before
they are counted.

So you see how many real people came, which pages they looked at and where they
came from, on one simple dashboard. A report comes to your inbox each week, and
you can set alerts for when traffic jumps or drops. And you don't need a cookie
pop-up for your analytics.

**Free plan, no card:** 10,000 events a month (an event is a page view or an action you track) on up to 3 sites. [Start free at privatusanalytics.com](https://privatusanalytics.com).

- **No cookies.** No cookies and no hidden IDs on your visitors' devices, and no IP
  addresses are kept. Laws differ by country, so check your own legal advice.
- **Real people, not bots.** Known bots, data centers and spam visits are left
  out on every plan.
- **Small and fast.** The script is about 3 KB when compressed.

## What this package does

- `resty.privatus` puts the script in the `<head>` of every HTML page that
  [OpenResty](https://openresty.org) (nginx with Lua) sends.
- `privatus.lapis` gives [Lapis](https://leafo.net/lapis/) views a few helpers.
- `privatus` is the plain Lua core. It builds the same HTML in any Lua app,
  with no other modules needed.
- The package only prints the browser script. It never sends events from your
  server and sets no cookies.

You need a Privatus Analytics account to see your reports, and there is a
free plan. [Sign up at privatusanalytics.com](https://privatusanalytics.com).

## Requirements

* Lua 5.1 to 5.4, or LuaJIT. OpenResty uses LuaJIT.
* For the filters: OpenResty 1.19 or later.
* A Privatus Analytics site id (it starts with `pa_`). You find it under
  Site settings, Tracking.

## Install

With [LuaRocks](https://luarocks.org) (the Lua package manager):

```sh
luarocks install lua-resty-privatus
```

or with OPM (the OpenResty package manager):

```sh
opm get Privatus-Analytics/lua-resty-privatus
```

For the full setup guide and every tracker option, see the [Privatus
Analytics docs](https://privatusanalytics.com/docs).

Set your site id with an environment variable:

```sh
PRIVATUS_SITE_ID=pa_YOURSITEID
PRIVATUS_ENV=production
```

or in a Lua table:

```lua
require("privatus").configure({ site_id = "pa_YOURSITEID" })
```

nginx hides environment variables from Lua unless you list them. Add these
lines at the top level of `nginx.conf` (outside `http {}`):

```nginx
env PRIVATUS_SITE_ID;
env PRIVATUS_ENV;
env PRIVATUS_SCRIPT_HOST;
```

## Add the tag

### OpenResty: let the filters add it

Put the filter pair in `http {}`, `server {}` or one `location {}`:

```nginx
env PRIVATUS_SITE_ID;
env PRIVATUS_ENV;

http {
  init_by_lua_block {
    require("resty.privatus").configure({
      -- site_id = "pa_YOURSITEID",  -- or PRIVATUS_SITE_ID
      modules = { "engage", "auto" },
    })
  }

  header_filter_by_lua_block { require("resty.privatus").header_filter() }
  body_filter_by_lua_block   { require("resty.privatus").body_filter() }

  server {
    listen 80;
    location / {
      proxy_pass http://app;
      proxy_set_header Accept-Encoding "";  # so the filters see plain HTML
    }
  }
}
```

With `PRIVATUS_ENV=production` every page gets, just before `</head>`:

```html
<script defer src="https://privatusstats.com/js/pa.js" data-site="pa_YOURSITEID" data-modules="engage,auto"></script>
```

The filters only touch `text/html` responses with status 200. They skip Ajax
requests (with `X-Requested-With: XMLHttpRequest`), `HEAD` requests, pages
without a `</head>`, and pages that already have `/js/pa.js`.

How it works: `header_filter` picks the HTML pages and removes their
`Content-Length` header, because the page gets longer. `body_filter` keeps
the HTML chunks in memory until the last one, adds the tag, and sends the
page. Other responses (images, JSON, files) pass straight through and are
never kept in memory. A page bigger than `max_buffer_size` (2 MB) is sent
unchanged.

Responses that already have a `Content-Encoding` header (they are compressed)
are left alone. If your app server compresses pages, set
`proxy_set_header Accept-Encoding "";` as above. nginx's own `gzip on;` is
fine, because it compresses after the filters have run.

You can pass settings to `header_filter` for one location. `body_filter`
then uses the same ones:

```nginx
location /docs/ {
  header_filter_by_lua_block {
    require("resty.privatus").header_filter({ excluded_paths = { "/docs/drafts/*" } })
  }
  body_filter_by_lua_block { require("resty.privatus").body_filter() }
}
```

If a `location` has its own `header_filter_by_lua*` or `body_filter_by_lua*`
for something else, nginx uses that one instead of the one from `http {}`.
Call the Privatus Analytics filters from your own code there.

### OpenResty: in your own templates

In a `content_by_lua*` handler, `require("resty.privatus").tag()` returns the
tag for the current request. Print it in your `<head>`.

### Lapis

Add the helpers with a before filter:

```lua
local lapis = require("lapis")
local privatus_lapis = require("privatus.lapis")

local app = lapis.Application()
app:enable("etlua")
app:before_filter(privatus_lapis.before_filter)
```

Then in an etlua view, for example `views/layout.etlua`. Use `<%-` so the
HTML is not escaped a second time:

```erb
<head>
  <title>My app</title>
  <%- privatus_tag() %>
</head>
```

In Lua code use `self:privatus_tag()`. In Lapis the environment comes from
`PRIVATUS_ENV` when it is set, and from the Lapis environment
(`lapis server production`) when it is not.

### Any other Lua app, and etlua on its own

The core module returns plain strings:

```lua
local privatus = require("privatus")
local etlua = require("etlua")

local template = etlua.compile([[
<head>
  <%- privatus.tag() %>
</head>
<button <%- privatus.event_attrs("Report exported", { format = "csv" }) %>>Export</button>
]])

print(template({ privatus = privatus }))
```

`privatus.inject(html)` adds the tag before `</head>` in a page you already
have as a string.

In every case the tag prints nothing when there is no site id, and nothing
outside production (see below). The one exception is the queue stub: when it
is on, it still prints (see [Track from your own
JavaScript](#track-from-your-own-javascript)).

## Configuration

Every setting is optional except the site id. Pass them as a Lua table:

```lua
require("privatus").configure({
  site_id          = "pa_YOURSITEID",               -- or PRIVATUS_SITE_ID
  script_host      = "https://privatusstats.com",   -- or PRIVATUS_SCRIPT_HOST
  modules          = { "engage", "auto", "vitals", "clicks", "ask" },
  excluded_paths   = { "/admin/*", "/preview/*" },
  domains          = { "example.com", "www.example.com" },
  spa              = "auto",   -- auto, history, hash or off
  manual           = false,    -- true turns off the automatic pageview
  enabled_environments = { "production" },
  extra_attributes = { ["data-mask"] = "/orders/*->/orders/:id" },
  props            = function(request) return { plan = request.ctx.plan } end,
  queue_stub       = false,
  nonce            = function(request) return request.ctx.csp_nonce end,
})
```

`require("resty.privatus").configure` is the same function. Call it once, in
`init_by_lua*` for OpenResty or at start up for other apps.

| Setting | Default | What it does |
|---|---|---|
| `site_id` | `PRIVATUS_SITE_ID` | The `data-site` attribute. Nothing prints without it |
| `script_host` | `https://privatusstats.com` | Where `/js/pa.js` is served. Change it only if you host your own copy. Falls back to `PRIVATUS_SCRIPT_HOST` |
| `modules` | tracker default (`engage`) | The `data-modules` attribute. Setting it replaces the default, so keep `engage` for time on page and scroll depth. `{}` loads none |
| `excluded_paths` | none | The `data-exclude` attribute. Path globs the tracker never counts |
| `domains` | all hosts | The `data-domains` attribute. Count only these hostnames |
| `spa` | `auto` | The `data-spa` attribute |
| `manual` | `false` | The `data-manual` attribute |
| `enabled` | not set | `true` or `false` forces the tag on or off everywhere |
| `environment` | `PRIVATUS_ENV` | The current environment. When neither is set it is `development` (in Lapis, the Lapis environment) |
| `enabled_environments` | `{ "production" }` | Environments that get the tag. Used when `enabled` is not set |
| `auto_inject` | `true` | `false` turns the OpenResty filters off without removing them from `nginx.conf` |
| `extra_attributes` | `{}` | Any other `data-*` attribute. `true` prints the name alone |
| `props` | `{}` | Page props sent with every pageview and event. A table, or a function that gets the request. See below |
| `queue_stub` | `false` | Prints a small script first, so `privatus.track` calls made before the tracker loads are kept and sent later. It still prints when the tag is off, so those calls never fail |
| `nonce` | not set | A Content Security Policy nonce for the script tags. A string, or a function that gets the request |
| `max_buffer_size` | `2097152` (2 MB) | OpenResty filters: pages bigger than this are sent without the tag |

Each tracker attribute is explained in the [script attributes
reference](https://privatusanalytics.com/docs/tracker/attributes), and the
modules in [Modules](https://privatusanalytics.com/docs/tracker/modules).

You can also override a setting for one call:

```lua
privatus.tag({ modules = { "engage", "auto" }, excluded_paths = { "/preview/*" } })
```

Lua tables cannot hold `nil`. To clear a setting for one call, or to remove
one prop, use `privatus.null` (`ngx.null` and `cjson.null` work too):

```lua
privatus.tag({ modules = privatus.null })  -- back to the tracker default
```

### What the request is

`props` and `nonce` functions get a request:

* In the OpenResty filters and `resty.privatus.tag()`: a table with
  `method`, `uri`, `args`, `host`, `var` (`ngx.var`) and `ctx` (`ngx.ctx`).
  Set `ngx.ctx` values in your `access_by_lua*` or content code, and read
  them in the function.
* In Lapis: the Lapis request (`self`).
* In plain Lua: whatever you pass as `request` in `privatus.tag({ request = ... })`.

### Content Security Policy nonce

A nonce is a random value that your Content Security Policy header uses to
allow one inline script. OpenResty has no nonce of its own. If you make one,
store it in `ngx.ctx` and pass a function:

```lua
nonce = function(request) return request.ctx.csp_nonce end
```

### Development and test

Development, test and staging requests are not counted by default, so your own
clicking around never reaches your reports. The tag prints only when
`PRIVATUS_ENV` is `production`. To see the tag while you build, set
`enabled = true`. The tracker also ignores `localhost` unless you pass
`data-allow-local` or `data-debug` (see [Debug
mode](https://privatusanalytics.com/docs/tracker/debug)):

```lua
privatus.configure({ enabled = true, extra_attributes = { ["data-debug"] = "true" } })
```

### Leaving people out

Use `data-exclude` through `excluded_paths` for admin areas. To leave out
signed-in staff, skip the tag for them. With the filters, set a flag in
`ngx.ctx` in your own code (for example `ngx.ctx.staff = true` in
`access_by_lua*`) and only call the header filter when it is not set:

```nginx
header_filter_by_lua_block {
  if not ngx.ctx.staff then require("resty.privatus").header_filter() end
}
```

In a Lapis view, where `current_user` is your own value:

```erb
<% if not (current_user and current_user.admin) then %><%- privatus_tag() %><% end %>
```

## Product analytics: see which features people use

Privatus Analytics can show which buttons, forms and features people really use. You
add a few attributes to your HTML. The tracker reads them in the browser and
sends the events. Your server still sends nothing.

### Name events well

Use a short "Noun verb" name, like `Report exported` or `Invite sent`. Put the
details in props, not in the name. So write `Report exported` with
`format = "csv"`, not `Report exported as CSV`. Then all exports add up in one
place, and you can split them by format.

### Events on buttons, links and forms

`event_attrs` returns the attributes to put inside a tag you write yourself:

```erb
<button <%- privatus.event_attrs("Report exported", { format = "csv", source = "toolbar" }) %>>Export</button>
```

In Lapis views it is `privatus_event_attrs(...)`. It prints:

```html
<button data-privatus-event="Report exported" data-privatus-prop-format="csv" data-privatus-prop-source="toolbar">Export</button>
```

`event_data` returns the same attributes as a table with the full attribute
names, for HTML builders such as Lapis widgets:

```lua
button(privatus.event_data("Report exported", { format = "csv" }), "Export")
```

On a form, the event is sent when the form is submitted:

```erb
<form action="/newsletter" method="post" <%- privatus.event_attrs("Newsletter joined", { list = "weekly" }) %>>
```

The rules:

* The name is trimmed and cut to 120 characters. An empty name prints nothing.
* Prop keys are made lowercase. Anything that is not a letter, a digit or `_`
  becomes `_`, so `"Report Type"` becomes `report_type`. Keys are cut to 64
  characters.
* At most 30 props. Values become text: `true`, `false`, numbers as written,
  lists joined with commas. `privatus.null` values are left out. Values are cut
  to 500 characters.
* Lua tables have no order, so props print sorted by key.
* Everything is escaped for HTML.
* The attributes print in every environment, even when the tag is off. They do
  nothing without the tracker, so your pages look the same in development and
  production.

### Click maps

A click map shows where people click on a page. Give the important parts a
name so they stay easy to find, even when the page changes:

```erb
<a href="/pricing" <%- privatus.click_attr("pricing.cta") %>>See plans</a>
```

`click_data` returns `{ ["data-privatus-click"] = "pricing.cta" }` for HTML
builders. A name may use letters, digits and `_ . : -`, up to 100 characters.
Anything else prints nothing, and outside production the package writes a
warning (to the nginx error log in OpenResty, and to stderr elsewhere).

### Page props: plan, role and other groups

Page props are sent with every pageview and event on the page. Use them to
split your reports by plan, role, app version, feature flag or account tier.

Set them for every page with a function. It runs on each request and gets the
request:

```lua
privatus.configure({
  props = function(request)
    return { plan = request.ctx.plan, role = request.ctx.role, app_version = "2.4" }
  end,
})
```

A plain table works too. You can also set or change props for one call. They
are merged over the configured ones, and `privatus.null` removes one:

```lua
privatus.tag({ props = { section = "billing", role = privatus.null } })
```

The tag then prints a small script before the tracker, with your nonce when
you have one, and points the tracker at it:

```html
<script nonce="...">window.privatusPageProps=function(){return {"plan":"pro","role":"admin"}}</script>
<script defer src="https://privatusstats.com/js/pa.js" data-site="pa_YOURSITEID" data-props="privatusPageProps"></script>
```

Keys follow the same rules as event props. Numbers and true or false stay as
they are, and lists stay lists (up to 30 items). The props are escaped so they
are safe inside a script. The JSON (the data format the script reads) is
written by this package, so you do not need a JSON module.

**Never put names, emails, user ids or anything that points to one person in
props.** Privatus Analytics counts visitors without any id. Put groups (like the plan or
the role), not people. The server also removes emails and long ids it finds.

### Track from your own JavaScript

For things that are not a click or a submit, call the tracker from your
JavaScript, as the [JavaScript API
docs](https://privatusanalytics.com/docs/tracker/javascript-api) explain:

```js
privatus.track("Feature used", { feature: "export" })
```

If your code may run before the tracker has loaded, switch on the queue stub.
It prints a tiny script before the tracker that keeps your calls in a list and
sends them once the tracker is ready:

```lua
privatus.configure({ queue_stub = true })
```

or for one call: `privatus.tag({ queue_stub = true })`. The stub prints even
where the tag is off (in development, with `enabled = false`, or with no site
id). Then only the stub prints: no tracker and no page props. So you can
always call `privatus.track(...)`. In development the calls just wait in the
queue and are never sent. The OpenResty filters still add nothing when the
tag is off.

### See the results

* [Funnels](https://privatusanalytics.com/docs/features/funnels): how many
  people go from one step to the next.
* [Click maps](https://privatusanalytics.com/docs/features/click-maps): where
  people click.
* [Goals](https://privatusanalytics.com/docs/features/goals): turn an event
  into a goal to count conversions.
* [Events](https://privatusanalytics.com/docs/events): every custom event and
  its props.

## Privacy

The script sets no cookies and stores nothing in the browser. The event, click
and props helpers only print HTML attributes and a small script. The OpenResty
filters only change the HTML. They never read IP addresses or browser details
and never send anything. Keep people out of your props and event props: no
names, emails or user ids. See the [privacy
documentation](https://privatusanalytics.com/docs/privacy) for what is
collected.

If you have a privacy policy, it should say which tools handle your visitors' data. You can paste this:

> This website uses [Privatus Analytics](https://privatusanalytics.com/privacy-analytics) to count visits. It
> does not use cookies and does not follow you from one website to another. Your IP address is used for a moment
> to count visits and is never stored.

Change it to fit your site. The [privacy policy generator](https://privatusanalytics.com/tools/privacy-policy-generator)
makes a longer version with your site's name in it.

## Development

The tests run in Docker so your local Lua does not matter:

```sh
./run-docker.sh
```

It uses the `openresty/openresty` alpine-fat image. It runs the busted specs,
luacheck (a Lua linter), a smoke test on plain Lua 5.1 and 5.4, an OpenResty
test that starts nginx with `test/nginx.conf` and checks real pages with
curl, and builds the rock and the OPM package.

## Contributing

Bug reports and pull requests are welcome at
https://github.com/Privatus-Analytics/lua.

## License

MIT. See [LICENSE](LICENSE). Privatus Analytics is a product of Two Phase LLC,
Wyoming, USA.
