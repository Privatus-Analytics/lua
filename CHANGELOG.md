# Changelog

## 1.0.0 - 2026-10-25

- Initial release.
- `privatus` module in plain Lua 5.1 to 5.4 and LuaJIT: `tag`, `event_attrs`, `event_data`, `click_attr`,
  `click_data`, `page_props_json`, `queue_stub` and `inject`. No other modules needed.
- `resty.privatus` for OpenResty: a `header_filter` and `body_filter` pair that adds the tag before `</head>`
  in HTML pages, including pages sent in chunks.
- `privatus.lapis` view helpers for Lapis.
- Page props from a table or a function that gets the request, and an optional queue stub.
- The tag prints only when `PRIVATUS_ENV` is `production`, unless `enabled` is set.
