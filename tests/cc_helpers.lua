---[[Copy pasted from codecompanion/tests/helpers.lua]]

local Helpers = {}

---Mock the plugin config
---@return table
local function mock_config()
    local config_module = require("codecompanion.config")
    config_module.setup = function(args)
        config_module.config = args or {}
    end
    config_module.can_send_code = function()
        return true
    end
    return config_module
end

---Set up the CodeCompanion plugin with test configuration
---@return nil
Helpers.setup_plugin = function(config)
    local test_config = require("tests.cc_config")
    --INFO: Don't know why config is not updated with codecompanion.setup() but needs these 2 lines
    local config_module = mock_config()
    config_module.setup(vim.tbl_deep_extend("force", test_config, config or {}))
    local codecompanion = require("codecompanion")
    codecompanion.setup(vim.tbl_deep_extend("force", test_config, config or {}))
    return codecompanion
end

---Mock the submit function of a chat to avoid actual API calls
---@param response string The mocked response content
---@param status? string The status to set (default: "success")
---@return function The original submit function for restoration
Helpers.mock_submit = function(response, tools, status)
    local original_submit = require("codecompanion.interactions.chat").submit

    require("codecompanion.interactions.chat").submit = function(self)
        self.status = status or "success"
        self:done({ response or "Mocked response" }, tools)
        return true
    end

    return original_submit
end

---Restore the original submit function
---@param original function The original submit function to restore
---@return nil
Helpers.restore_submit = function(original)
    require("codecompanion.interactions.chat").submit = original
end

---Setup and mock a chat buffer
---@param config? table
---@param adapter? table
Helpers.setup_chat_buffer = function(config, adapter)
    local test_config = vim.deepcopy(require("tests.cc_config"))
    local config_module = mock_config()
    config_module.setup(vim.tbl_deep_extend("force", test_config, config or {}))
    -- Extend the adapters
    if adapter then
        config_module.adapters[adapter.name] = adapter.config
    end
    local chat = require("codecompanion.interactions.chat").new({
        context = { bufnr = 1, filetype = "lua" },
        adapter = adapter and adapter.name or "test_adapter",
    })
    return chat
end

Helpers.send_to_llm = function(chat, message, callback)
    message = message or "Hello there"
    chat:submit()
    chat:add_buf_message({ role = "llm", content = message })
    chat.status = "success"
    if callback then
        callback()
    end
    chat:done({ message })
end

---Clean down the chat buffer if required
---@return nil
Helpers.teardown_chat_buffer = function()
    package.loaded["codecompanion.utils.foo"] = nil
    package.loaded["codecompanion.utils.bar"] = nil
    package.loaded["codecompanion.utils.bar_again"] = nil
end

return Helpers
