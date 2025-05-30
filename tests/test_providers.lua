local h = require("tests.helpers")
local eq, new_set = MiniTest.expect.equality, MiniTest.new_set
local T = new_set()

local child = h.new_child_neovim()

T = new_set({
    hooks = {
        pre_once = function()
            child.setup()
            -- Setup logging once for all tests
            child.lua([[
                local log = require("codecompanion._extensions.history.log")
                log.setup_logging(false) -- Disable logging for tests
            ]])
        end,
        post_once = child.stop,
    },
})

-- Picker Resolution Tests
T["Picker Resolution"] = new_set()

T["Picker Resolution"]["should auto-resolve to valid picker"] = function()
    local result = child.lua([[
        local pickers = require("codecompanion._extensions.history.pickers")
        local resolved = pickers.history
        local valid_options = { "telescope", "fzf-lua", "snacks", "default" }
        return {
            resolved_picker = resolved,
            is_valid = vim.tbl_contains(valid_options, resolved),
            is_string = type(resolved) == "string"
        }
    ]])

    eq(true, result.is_valid)
    eq(true, result.is_string)
end

T["Picker Resolution"]["should use resolved picker in history init"] = function()
    local result = child.lua([[
        -- Test that history extension uses the auto-resolved picker
        local History = require("codecompanion._extensions.history").History
        local pickers = require("codecompanion._extensions.history.pickers")
        
        -- Create history instance (simulating extension setup)
        local opts = {
            picker = pickers.history, -- This should be auto-resolved
            dir_to_save = vim.fn.stdpath("data") .. "/test-history",
            enable_logging = false,
            summary = {}
        }
        
        local history = History.new(opts)
        
        return {
            picker_from_init = pickers.history,
            picker_from_history = history.opts.picker,
            pickers_match = pickers.history == history.opts.picker
        }
    ]])

    eq(true, result.pickers_match)
    eq("string", type(result.picker_from_init))
end

return T
