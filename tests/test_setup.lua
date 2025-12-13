local h = require("tests.helpers")
local eq, new_set = MiniTest.expect.equality, MiniTest.new_set
local T = new_set()
local child = h.new_child_neovim()

T = new_set({
    hooks = {
        pre_case = function()
            child.setup()
            child.lua([[
              h = require('tests.helpers')
              cc_h = require('tests.cc_helpers')
              codecompanion = cc_h.setup_plugin({
                extensions = {
                  history = {
                    enabled = true,
                    opts = {
                      keymap = "gh",
                      auto_generate_title = true,
                      continue_last_chat = false,
                      delete_on_clearing_chat = false,
                      picker = "default", -- Use default picker to avoid telescope dependency
                      enable_logging = true,
                      dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history-test",
                    }
                  }
                }
              })
            ]])
        end,
        post_case = function() end,

        post_once = child.stop,
    },
})

-- Test the History module initialization
T["History module"] = new_set()

T["History module"]["should be loaded"] = function()
    local history_exists = child.lua_get([[
      package.loaded["codecompanion._extensions.history"] ~= nil
  ]])
    eq(true, history_exists)
end

T["History module"]["available in codecompanion"] = function()
    local has_property = child.lua_get([[
      codecompanion.extensions.history ~= nil
    ]])
    eq(true, has_property)
end

T["History module"]["should register :CodeCompanionHistory command"] = function()
    local has_command = child.lua_get([[
      vim.fn.exists(":CodeCompanionHistory") == 2
    ]])
    eq(true, has_command)
end

T["History module"]["should register keymap"] = function()
    local has_keymap = child.lua([[
      local keymap = require("codecompanion.config").interactions.chat.keymaps["Saved Chats"]
      return keymap and keymap.modes.n == "gh"
    ]])
    eq(true, has_keymap)
end

return T
