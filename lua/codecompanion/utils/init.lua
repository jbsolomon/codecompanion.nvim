local log = require("codecompanion.utils.log")

local api = vim.api

local M = {}

---Is the filetype the chat buffer or its input?
---@param ft string
---@return boolean
function M.is_chat_ft(ft)
  return vim.tbl_contains(require("codecompanion.config").constants.CHAT_FILETYPES, ft)
end

---Is the filetype anywhere the user writes a prompt, including the inline prompt box?
---@param ft string
---@return boolean
function M.is_prompt_ft(ft)
  return vim.tbl_contains(require("codecompanion.config").constants.PROMPT_FILETYPES, ft)
end

---Fire an event
---@param event string
---@param opts? table
function M.fire(event, opts)
  opts = opts or {}
  api.nvim_exec_autocmds("User", { pattern = "CodeCompanion" .. event, data = opts })
end

---Notify the user
---@param msg string
---@param level? number|string
---@param opts? table
---@return nil
function M.notify(msg, level, opts)
  opts = opts or {}
  level = level or vim.log.levels.INFO

  return vim.notify(msg, level, {
    title = opts.title or "CodeCompanion",
  })
end

---Make the first letter uppercase
---@param str string
---@return string
M.capitalize = function(str)
  local result = str:gsub("^%l", string.upper)
  return result
end

---Check if a table is an array
---@param t table
---@return boolean
M.is_array = function(t)
  if type(t) ~= "table" then
    return false
  end
  if vim.islist then
    return vim.islist(t)
  end
  return vim.tbl_islist(t)
end

---@param table table
---@param value string
---@return boolean
M.contains = function(table, value)
  for _, v in pairs(table) do
    if v == value then
      return true
    end
  end
  return false
end

M._noop = function() end

---@param name string
---@return nil
M.set_dot_repeat = function(name)
  vim.go.operatorfunc = "v:lua.require'codecompanion.utils'._noop"
  vim.cmd.normal({ args = { "g@l" }, bang = true })
  vim.go.operatorfunc = string.format("v:lua.require'codecompanion'.%s", name)
end

---Extract placeholder names from a string
---@param str string The string to search for placeholders
---@return table List of unique placeholder names found (e.g. {"diff", "selection"})
function M.extract_placeholders(str)
  local placeholders = {}
  local seen = {}

  for placeholder in str:gmatch("%${([^}]+)}") do
    if not seen[placeholder] then
      seen[placeholder] = true
      table.insert(placeholders, placeholder)
    end
  end

  return placeholders
end

---Extract all placeholders from a prompts structure (recursively)
---@param prompts table|string The prompts structure to search
---@return table List of unique placeholder names found
function M.extract_all_placeholders(prompts)
  local all_placeholders = {}
  local seen = {}

  local function extract_recursive(value)
    if type(value) == "string" then
      local found = M.extract_placeholders(value)
      for _, placeholder in ipairs(found) do
        if not seen[placeholder] then
          seen[placeholder] = true
          table.insert(all_placeholders, placeholder)
        end
      end
    elseif type(value) == "table" then
      for _, v in pairs(value) do
        extract_recursive(v)
      end
    end
  end

  extract_recursive(prompts)
  return all_placeholders
end

---Escape percent signs in a string for use as a gsub replacement value.
---In Lua's gsub, the replacement string treats %0-%9 as capture references
---and %% as a literal percent. This function doubles all percent signs so
---that the replacement is inserted verbatim.
---@param str string
---@return string
local function escape_gsub_replacement(str)
  return (str:gsub("%%", "%%%%"))
end

---Replace any placeholders (e.g. ${placeholder}) in a string or table
---@param t table|string The content to process
---@param replacements table<string, string> Map of placeholder names to replacement values
---@return string|nil The replaced string if input was string, or nil if input was table (modified in place)
function M.replace_placeholders(t, replacements)
  if type(t) == "string" then
    for placeholder, replacement in pairs(replacements) do
      t = t:gsub("%${" .. vim.pesc(placeholder) .. "}", escape_gsub_replacement(replacement))
    end
    return t
  else
    for key, value in pairs(t) do
      if type(value) == "table" then
        M.replace_placeholders(value, replacements)
      elseif type(value) == "string" then
        for placeholder, replacement in pairs(replacements) do
          value = value:gsub("%${" .. vim.pesc(placeholder) .. "}", escape_gsub_replacement(replacement))
        end
        t[key] = value
      end
    end
  end
end

---@param msg string
---@param vars table
---@param mapping table
---@return string
function M.replace_vars(msg, vars, mapping)
  local replacements = {}
  for _, var_name in ipairs(vars) do
    -- Check if the variable exists in the mapping
    if mapping[var_name] then
      table.insert(replacements, mapping[var_name])
    else
      error("Variable '" .. var_name .. "' not found in the mapping.")
    end
  end
  return string.format(msg, unpack(replacements))
end

---Safely get the filetype
---@param filetype string
---@return string
function M.safe_filetype(filetype)
  if filetype == "C++" then
    return "cpp"
  end
  return filetype
end

---Set an option in Neovim
---@param bufnr number
---@param opt string
---@param value any
function M.set_option(bufnr, opt, value)
  if api.nvim_set_option_value then
    return api.nvim_set_option_value(opt, value, {
      buf = bufnr,
    })
  end

  if api.nvim_buf_set_option then
    return api.nvim_buf_set_option(bufnr, opt, value)
  end
end

---Convert an ISO 8601 timestamp to a Unix timestamp
---@param iso string ISO 8601 timestamp (e.g. "2026-03-18T22:29:29.993Z")
---@return number|nil
function M.timestamp_from_iso(iso)
  local pattern = "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)"
  local year, month, day, hour, min, sec = iso:match(pattern)
  if not year then
    return nil
  end

  ---@type osdateparam
  local date = {
    day = tonumber(day), --[[@as number]]
    hour = tonumber(hour), --[[@as number]]
    min = tonumber(min), --[[@as number]]
    month = tonumber(month), --[[@as number]]
    sec = tonumber(sec), --[[@as number]]
    year = tonumber(year), --[[@as number]]
  }

  -- The timestamp is UTC, but os.time() reads the table as local time, so add
  -- the local offset from UTC to recover the true instant
  local now = os.time()
  local utc = os.date("!*t", now) --[[@as osdateparam]]
  local utc_offset = os.difftime(now, os.time(utc))

  return os.time(date) + utc_offset
end

---Make a timestamp relative
---@param timestamp number Unix timestamp
---@return string Relative time string (e.g. "5m", "2h")
function M.make_relative(timestamp)
  local now = os.time()
  local diff = now - timestamp

  if diff < 60 then
    return diff .. "s"
  elseif diff < 3600 then
    return math.floor(diff / 60) .. "m"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. "h"
  else
    return math.floor(diff / 86400) .. "d"
  end
end

---Add a callback to a set of callbacks
---@param callbacks table|nil The existing callbacks
---@param event string The event to add the callback to
---@param fn function The callback function
function M.callbacks_extend(callbacks, event, fn)
  callbacks = callbacks or {}
  local existing = callbacks[event]
  if not existing then
    callbacks[event] = fn
  elseif type(existing) == "function" then
    callbacks[event] = { existing, fn }
  else
    table.insert(existing, fn)
  end
  return callbacks
end

---Resolve a config value into the module, table or function it points at
---@param args { value: string|function, source?: string }
---@return any|nil
function M.resolve(args)
  local value = args.value
  if type(value) == "function" then
    return value
  end
  if type(value) ~= "string" then
    return nil
  end

  local source = args.source or "CodeCompanion"

  for _, name in ipairs({ "codecompanion." .. value, value }) do
    local ok, resolved = pcall(require, name)
    if ok then
      return resolved
    end
    -- A module that is on the runtimepath but fails to load must surface its own error
    if not tostring(resolved):match("module '" .. vim.pesc(name) .. "' not found") then
      return log:error("[%s] `%s` could not be loaded: %s", source, name, resolved)
    end
  end

  local chunk, err = loadfile(vim.fs.normalize(value))
  if err or not chunk then
    log:error("[%s] Could not resolve `%s`", source, value)
    return nil
  end

  return chunk()
end

---Resolve a nested table value using a dot-separated path string
---@param tbl table The table to traverse
---@param path string The dot-separated path (e.g. "interactions.chat.tools.memory")
---@return any|nil The resolved value, or nil if the path doesn't exist
function M.resolve_nested_value(tbl, path)
  local parts = vim.split(path, ".", { plain = true })
  local resolved = tbl
  for _, part in ipairs(parts) do
    resolved = resolved[part]
    if not resolved then
      return nil
    end
  end
  return resolved
end

---Convert a word to singular or plural form based on count
---@param count number The count to determine singular or plural
---@param word string The base word (singular form)
---@return string The word with "s" appended if count ~= 1, or the original word if inputs are invalid
function M.pluralize(count, word)
  if type(count) ~= "number" or type(word) ~= "string" then
    return word or "item"
  end
  return count == 1 and word or word .. "s"
end

---Deep copy a table, truncating any string values
---@param tbl table
---@param max_len? number
---@return table
function M.truncate(tbl, max_len)
  if not max_len then
    max_len = 255
  end

  local output = {}
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      output[k] = M.truncate(v, max_len)
    elseif type(v) == "string" and #v > max_len then
      output[k] = v:sub(1, max_len) .. "...[truncated]"
    else
      output[k] = v
    end
  end

  return output
end

-- Written out in bytes because LuaJIT has no `utf8` module to name it with
local UTF8_REPLACEMENT_CHARACTER = "\239\191\189" -- U+FFFD
local NON_ASCII_BYTES = "[\128-\255]"

local function is_continuation(byte)
  return byte ~= nil and byte >= 0x80 and byte <= 0xBF
end

---The width of the UTF-8 sequence starting at `position`, or nil when the bytes there don't form one
---@param text string
---@param position number
---@return number?
local function utf8_sequence_width(text, position)
  local lead = text:byte(position)
  local second = text:byte(position + 1)

  local width
  if lead >= 0xC2 and lead <= 0xDF then
    width = 2
  elseif lead >= 0xE0 and lead <= 0xEF then
    width = 3
  elseif lead >= 0xF0 and lead <= 0xF4 then
    width = 4
  else
    return nil
  end

  -- Beyond the lead byte, these ranges would give an overlong encoding, a UTF-16 surrogate or a
  -- codepoint past U+10FFFF, and the API hosts reject the whole request for them
  if not is_continuation(second) then
    return nil
  end
  if (lead == 0xE0 and second < 0xA0) or (lead == 0xED and second >= 0xA0) then
    return nil
  end
  if (lead == 0xF0 and second < 0x90) or (lead == 0xF4 and second > 0x8F) then
    return nil
  end

  for offset = 2, width - 1 do
    if not is_continuation(text:byte(position + offset)) then
      return nil
    end
  end

  return width
end

---Replace every byte that isn't part of a valid UTF-8 sequence with U+FFFD
---@param text string
---@return string
function M.ensure_valid_utf8(text)
  local parts = {}
  local clean_from = 1
  local position = text:find(NON_ASCII_BYTES)

  while position do
    local width = utf8_sequence_width(text, position)
    if width then
      position = text:find(NON_ASCII_BYTES, position + width)
    else
      table.insert(parts, text:sub(clean_from, position - 1))
      table.insert(parts, UTF8_REPLACEMENT_CHARACTER)
      clean_from = position + 1
      position = text:find(NON_ASCII_BYTES, clean_from)
    end
  end

  if #parts == 0 then
    return text
  end

  table.insert(parts, text:sub(clean_from))
  return table.concat(parts)
end

return M
