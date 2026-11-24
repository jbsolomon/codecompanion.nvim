local log = require("codecompanion.utils.log")

local fmt = string.format

---@class CodeCompanion.AdapterArgs
return {
  name = "markitdown",
  formatted_name = "MarkItDown",
  opts = {
    stream = false,
    timeout = 120000, -- Timeout for the conversion (milliseconds)
    command = { "markitdown" }, -- Command used to convert a page; prepend a runner like { "uvx", "markitdown" }
    ---Override the default HTTP request with a CLI-based one
    ---@param self CodeCompanion.HTTPClient
    ---@param _payload table
    ---@param actions { callback: fun(err: nil|table, data: nil|table) }
    ---@param _opts? table
    ---@return vim.SystemObj|nil
    request = function(self, _payload, actions, _opts)
      local url = self.adapter.env.url
      if not url then
        return actions.callback({ message = "No URL provided" }, nil)
      end

      local command = self.adapter.opts.command
      local timeout = self.adapter.opts.timeout
      local command_display = table.concat(command, " ")

      local function fail(message)
        log:error("[MarkItDown Adapter] %s", message)
        actions.callback({ message = message }, nil)
      end

      local argv = vim.list_extend(vim.deepcopy(command), { url })

      local ok, job = pcall(vim.system, argv, { text = true, timeout = timeout }, function(result)
        self.methods.schedule(function()
          if result.code == 124 then
            return fail(fmt("`%s` timed out after %dms", command_display, timeout))
          end
          if result.code ~= 0 then
            return fail(fmt("Failed to run `%s` (exit %d): %s", command_display, result.code, result.stderr or ""))
          end
          actions.callback(nil, { body = result.stdout })
        end)
      end)

      if not ok then
        return fail(fmt("Failed to run `%s`: %s", command_display, job))
      end

      return job
    end,
  },
  env = {},
  schema = {
    model = {
      default = "markitdown",
    },
  },
  methods = {
    slash_commands = {
      fetch = {
        ---Setup the adapter for the fetch slash command
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table
        ---@return nil
        setup = function(self, data)
          self.env = vim.tbl_deep_extend("force", self.env, {
            url = data.url,
          })
        end,

        ---Process the output from the fetch slash command
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          if not data.body or data.body == "" then
            return { status = "error", content = "No content returned" }
          end
          return { status = "success", content = data.body }
        end,
      },
    },
    tools = {
      fetch_webpage = {
        ---Setup the adapter for the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data from the LLM's tool call
        ---@return nil
        setup = function(self, data)
          self.env = vim.tbl_deep_extend("force", self.env, {
            url = data.url,
          })
        end,

        ---Process the output from the fetch webpage tool
        ---@param self CodeCompanion.HTTPAdapter
        ---@param data table The data returned from the fetch
        ---@return table{status: string, content: string}|nil
        callback = function(self, data)
          if not data.body or data.body == "" then
            return { status = "error", content = "No content returned" }
          end
          return { status = "success", content = data.body }
        end,
      },
    },
  },
}
