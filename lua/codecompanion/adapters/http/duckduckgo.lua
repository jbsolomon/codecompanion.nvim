local fmt = string.format
local named_entities = {
  amp = "&",
  apos = "'",
  gt = ">",
  lt = "<",
  nbsp = " ",
  quot = '"',
}

-- utf8.* does not exist on this LuaJIT build; emit the bytes by hand so numbered entities decode
local function codepoint_to_utf8(codepoint)
  if codepoint < 0x80 then
    return string.char(codepoint)
  elseif codepoint < 0x800 then
    return string.char(0xC0 + bit.rshift(codepoint, 6), 0x80 + bit.band(codepoint, 0x3F))
  elseif codepoint < 0x10000 then
    return string.char(
      0xE0 + bit.rshift(codepoint, 12),
      0x80 + bit.band(bit.rshift(codepoint, 6), 0x3F),
      0x80 + bit.band(codepoint, 0x3F)
    )
  end
  return string.char(
    0xF0 + bit.rshift(codepoint, 18),
    0x80 + bit.band(bit.rshift(codepoint, 12), 0x3F),
    0x80 + bit.band(bit.rshift(codepoint, 6), 0x3F),
    0x80 + bit.band(codepoint, 0x3F)
  )
end

local function decode_entities(text)
  text = text:gsub("&#(%d+);", function(decimal)
    return codepoint_to_utf8(decimal + 0)
  end)
  text = text:gsub("&#x(%x+);", function(hex)
    return codepoint_to_utf8(tonumber(hex, 16))
  end)
  text = text:gsub("&(%a+);", function(name)
    return named_entities[name] or "&" .. name .. ";"
  end)
  return text
end

-- DuckDuckGo wraps every result link in a redirect; unwrap it to the source URL
local function result_url(href)
  local uddg = href:match("[?&]uddg=([^&]*)")
  if not uddg then
    return decode_entities(href)
  end
  return uddg:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
end

---@class CodeCompanion.HTTPAdapter
return {
  name = "duckduckgo",
  formatted_name = "DuckDuckGo",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    method = "POST",
    compress = true,
  },
  url = "https://html.duckduckgo.com/html/?q=${query}",
  env = {},
  headers = {
    ["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64; rv:153.0) Gecko/20100101 Firefox/153.0",
    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ["Accept-Language"] = "en-US,en;q=0.9",
    ["Connection"] = "keep-alive",
    ["Upgrade-Insecure-Requests"] = "1",
    ["Sec-Fetch-Dest"] = "document",
    ["Sec-Fetch-Mode"] = "navigate",
    ["Sec-Fetch-Site"] = "none",
    ["Sec-Fetch-User"] = "?1",
    ["Priority"] = "u=0, i",
    ["TE"] = "trailers",
  },
  schema = {
    model = {
      default = "duckduckgo",
    },
  },
  handlers = {},
  methods = {
    tools = {
      web_search = {
        ---Setup the adapter for the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param opts table Tool options
        ---@param data table The data from the LLM's tool call
        ---@return nil
        setup = function(self, opts, data)
          self.env = vim.tbl_deep_extend("force", self.env or {}, {
            query = vim.uri_encode(data.query),
          })
        end,

        ---Process the output from the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          if data.status >= 300 then
            return {
              status = "error",
              content = fmt("Error %s", data.status),
            }
          end
          local function clean_html(html)
            return html:gsub("</?b[^>]*>", ""):gsub("<[^>]+>", " "):gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
          end
          local out = {}
          for href, title, content in
            data.body:gmatch(
              '<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]*)"[^>]*>(.-)</a>.-'
                .. '<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*href="[^"]*"[^>]*>(.-)</a>'
            )
          do
            table.insert(out, {
              title = decode_entities(clean_html(title)),
              url = result_url(href),
              content = decode_entities(clean_html(content)),
            })
          end
          if #out < 1 and data.body:find("challenge-form", 1, true) then
            return {
              status = "error",
              content = "Engine thinks you're a bot",
            }
          end
          return {
            status = "success",
            content = out,
          }
        end,
      },
    },
  },
}
