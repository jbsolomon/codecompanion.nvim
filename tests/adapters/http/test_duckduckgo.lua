local h = require("tests.helpers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["DuckDuckGo adapter"] = new_set({
  hooks = {
    pre_case = function()
      adapter = require("codecompanion.adapters").resolve("duckduckgo")
    end,
  },
})

local function first_result()
  local body = table.concat(vim.fn.readfile("tests/adapters/http/stubs/duckduckgo_results.html"), "\n")
  return adapter.methods.tools.web_search.callback(adapter, { status = 200, body = body }).content[1]
end

T["DuckDuckGo adapter"]["recovers the source URL from the redirect wrapper"] = function()
  local result = first_result()

  h.eq("https://neovim.io/news/2025/03/", result.url)
  h.expect_not_contains("uddg", result.url)
end

T["DuckDuckGo adapter"]["decodes entities in the snippet"] = function()
  local result = first_result()

  h.expect_contains("There's", result.content)
  h.expect_not_contains("&#", result.content)
  h.expect_not_contains("&amp;", result.content)
end

return T
