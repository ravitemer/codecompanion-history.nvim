---@brief [[
--- ACP Session ID Persistence Tests
---
--- This test suite verifies the functionality of ACP session ID save/restore
--- in the CodeCompanion history extension. It tests:
---
--- 1. Save Operations:
---    - Capturing acp_session_id from ACP connection
---    - Handling chats without ACP connection
---
--- 2. Backward Compatibility:
---    - Loading old chats without acp_session_id
---
--- 3. Data Integrity:
---    - acp_session_id preserved through save/load cycle
---    - acp_session_id preserved through duplication
---]]

local h = require("tests.helpers")
local eq, new_set = MiniTest.expect.equality, MiniTest.new_set
local T = new_set()

local child = h.new_child_neovim()

T = new_set({
    hooks = {
        pre_case = function()
            child.setup()
            child.lua([[
              local log = require("codecompanion._extensions.history.log")
              log.setup_logging(false)

              local Storage = require("codecompanion._extensions.history.storage")
              test_storage = Storage.new({
                  dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history-acp-test-" .. os.time()
              })
            ]])
        end,
        post_case = function()
            child.lua([[
              if test_storage and test_storage.base_path then
                  local folder = test_storage.base_path
                  if vim.fn.isdirectory(folder) == 1 then
                      vim.fn.delete(folder, "rf")
                  end
              end
            ]])
        end,
        post_once = child.stop,
    },
})

-- Save Operations
T["ACP Session Save"] = new_set()

T["ACP Session Save"]["captures acp_session_id when ACP connection present"] = function()
    local result = child.lua([[
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_acp_save")

        test_storage:save_chat({
            opts = {
                save_id = chat_data.save_id,
                title = chat_data.title,
            },
            messages = chat_data.messages,
            settings = chat_data.settings,
            adapter = { name = "test_acp" },
            context_items = {},
            tool_registry = { schemas = {}, in_use = {} },
            cycle = 1,
            acp_connection = { session_id = "acp-test-session-123" },
        })

        local loaded = test_storage:load_chat("test_acp_save")

        return {
            has_session_id = loaded and loaded.acp_session_id ~= nil,
            session_id = loaded and loaded.acp_session_id,
        }
    ]])

    eq(true, result.has_session_id)
    eq("acp-test-session-123", result.session_id)
end

T["ACP Session Save"]["saves nil acp_session_id when no ACP connection"] = function()
    local result = child.lua([[
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_no_acp")

        test_storage:save_chat({
            opts = {
                save_id = chat_data.save_id,
                title = chat_data.title,
            },
            messages = chat_data.messages,
            settings = chat_data.settings,
            adapter = { name = "openai" },
            context_items = {},
            tool_registry = { schemas = {}, in_use = {} },
            cycle = 1,
        })

        local loaded = test_storage:load_chat("test_no_acp")

        return {
            loaded_ok = loaded ~= nil,
            has_session_id = loaded and loaded.acp_session_id ~= nil,
        }
    ]])

    eq(true, result.loaded_ok)
    eq(false, result.has_session_id)
end

T["ACP Session Save"]["saves nil when ACP connection has no session_id"] = function()
    local result = child.lua([[
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_acp_no_sid")

        test_storage:save_chat({
            opts = {
                save_id = chat_data.save_id,
                title = chat_data.title,
            },
            messages = chat_data.messages,
            settings = chat_data.settings,
            adapter = { name = "test_acp" },
            context_items = {},
            tool_registry = { schemas = {}, in_use = {} },
            cycle = 1,
            acp_connection = { session_id = nil },
        })

        local loaded = test_storage:load_chat("test_acp_no_sid")

        return {
            loaded_ok = loaded ~= nil,
            has_session_id = loaded and loaded.acp_session_id ~= nil,
        }
    ]])

    eq(true, result.loaded_ok)
    eq(false, result.has_session_id)
end

-- Backward Compatibility
T["ACP Session Backward Compat"] = new_set()

T["ACP Session Backward Compat"]["loads old chats without acp_session_id"] = function()
    local result = child.lua([[
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_old_format")
        test_storage:_save_chat_to_file(chat_data)
        test_storage:_update_index_entry(chat_data)

        local loaded = test_storage:load_chat("test_old_format")

        return {
            loaded_ok = loaded ~= nil,
            session_id = loaded and loaded.acp_session_id,
            title = loaded and loaded.title,
        }
    ]])

    eq(true, result.loaded_ok)
    eq(nil, result.session_id)
    eq("Test Chat test_old_format", result.title)
end

-- Data Integrity
T["ACP Session Data Integrity"] = new_set()

T["ACP Session Data Integrity"]["preserves acp_session_id through save/load cycle"] = function()
    local result = child.lua([[
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_roundtrip")

        test_storage:save_chat({
            opts = {
                save_id = chat_data.save_id,
                title = chat_data.title,
            },
            messages = chat_data.messages,
            settings = chat_data.settings,
            adapter = { name = "claude_code" },
            context_items = {},
            tool_registry = { schemas = {}, in_use = {} },
            cycle = 3,
            acp_connection = { session_id = "session-roundtrip-abc" },
        })

        local loaded = test_storage:load_chat("test_roundtrip")

        return {
            session_id = loaded and loaded.acp_session_id,
            adapter = loaded and loaded.adapter,
            cycle = loaded and loaded.cycle,
            title = loaded and loaded.title,
        }
    ]])

    eq("session-roundtrip-abc", result.session_id)
    eq("claude_code", result.adapter)
    eq(3, result.cycle)
    eq("Test Chat test_roundtrip", result.title)
end

T["ACP Session Data Integrity"]["preserves acp_session_id through duplication"] = function()
    local result = child.lua([[
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_dup_acp")
        chat_data.acp_session_id = "session-to-duplicate"

        test_storage:_save_chat_to_file(chat_data)
        test_storage:_update_index_entry(chat_data)

        local new_save_id = test_storage:duplicate_chat("test_dup_acp", "Duplicated ACP Chat")
        local duplicated = test_storage:load_chat(new_save_id)

        return {
            new_save_id = new_save_id,
            session_id = duplicated and duplicated.acp_session_id,
            title = duplicated and duplicated.title,
        }
    ]])

    eq(true, result.new_save_id ~= nil)
    eq("session-to-duplicate", result.session_id)
    eq("Duplicated ACP Chat", result.title)
end

return T
