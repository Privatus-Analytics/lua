std = "max"
max_line_length = 120
include_files = { "lib/**/*.lua", "spec/**/*.lua", "test/**/*.lua", "*.rockspec", ".luacheckrc", ".busted" }

files["lib/resty"] = { std = "+ngx_lua" }
files["spec"] = { std = "+busted" }
