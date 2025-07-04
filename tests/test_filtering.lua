local h = require("tests.helpers")
local eq, new_set = MiniTest.expect.equality, MiniTest.new_set
local T = new_set()

local child = h.new_child_neovim()

T = new_set({
    hooks = {
        pre_case = function()
            child.setup()
            child.lua([[
                -- Setup logging
                local log = require("codecompanion._extensions.history.log")
                log.setup_logging(false) -- Disable logging for tests
                
                -- Setup codecompanion with history extension
                h = require('tests.helpers')
                cc_h = require('tests.cc_helpers')
                codecompanion = cc_h.setup_plugin({
                    extensions = {
                        history = {
                            enabled = true,
                            opts = {
                                auto_generate_title = false, -- Disable to avoid async issues in tests
                                continue_last_chat = false,
                                delete_on_clearing_chat = false,
                                picker = "default",
                                enable_logging = false,
                                dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history-filter-test-" .. os.time(),
                            }
                        }
                    }
                })
                
                -- Get history instance for testing
                history_ext = require("codecompanion._extensions.history")
                local History = history_ext.History
                test_history = History.new({
                    auto_generate_title = false,
                    continue_last_chat = false,
                    delete_on_clearing_chat = false,
                    picker = "default",
                    enable_logging = false,
                    dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history-filter-test-" .. os.time(),
                })
            ]])
        end,
        post_case = function()
            -- Clean up test directory
            child.lua([[
                if test_history and test_history.storage and test_history.storage.base_path then
                    local folder = test_history.storage.base_path
                    if vim.fn.isdirectory(folder) == 1 then
                        vim.fn.delete(folder, "rf")
                    end
                end
            ]])
        end,
        post_once = child.stop,
    },
})

-- Project Root Detection Tests
T["Project Root Detection"] = new_set()

T["Project Root Detection"]["finds git project root"] = function()
    local result = child.lua([[
        local utils = require("codecompanion._extensions.history.utils")
        
        -- Create a temporary directory structure with .git
        local test_dir = vim.fn.tempname()
        vim.fn.mkdir(test_dir, "p")
        vim.fn.mkdir(test_dir .. "/.git", "p")
        vim.fn.mkdir(test_dir .. "/subdir", "p")
        
        -- Test from subdirectory
        local project_root = utils.find_project_root(test_dir .. "/subdir")
        
        -- Cleanup
        vim.fn.delete(test_dir, "rf")
        
        return {
            project_root = project_root,
            matches_test_dir = project_root == test_dir
        }
    ]])

    eq(true, result.matches_test_dir)
end

T["Project Root Detection"]["falls back to provided path when no markers found"] = function()
    local result = child.lua([[
        local utils = require("codecompanion._extensions.history.utils")
        
        -- Create a temporary directory without any project markers
        local test_dir = vim.fn.tempname()
        vim.fn.mkdir(test_dir, "p")
        
        local project_root = utils.find_project_root(test_dir)
        
        -- Cleanup
        vim.fn.delete(test_dir, "rf")
        
        return {
            project_root = project_root,
            matches_test_dir = project_root == test_dir
        }
    ]])

    eq(true, result.matches_test_dir)
end

T["Project Root Detection"]["defaults to cwd when no path provided"] = function()
    local result = child.lua([[
        local utils = require("codecompanion._extensions.history.utils")
        local current_cwd = vim.fn.getcwd()
        local project_root = utils.find_project_root()
        
        return {
            project_root = project_root,
            current_cwd = current_cwd,
            has_fallback = project_root:find(current_cwd, 1, true) ~= nil
        }
    ]])

    eq(true, result.has_fallback)
end

-- Chat Data Enhancement Tests
T["Chat Data Enhancement"] = new_set()

T["Chat Data Enhancement"]["captures cwd and project_root on save"] = function()
    local result = child.lua([[
        local h = require("tests.helpers")
        
        -- Create a test chat
        local chat_data = h.create_test_chat("test_context_save")
        
        -- Mock a chat object for saving
        local mock_chat = {
            opts = {
                save_id = chat_data.save_id,
                title = chat_data.title
            },
            messages = chat_data.messages,
            settings = chat_data.settings,
            adapter = { name = chat_data.adapter },
            refs = {},
            tools = { schemas = {}, in_use = {} },
            cycle = 1
        }
        
        -- Save the chat
        test_history.storage:save_chat(mock_chat)
        
        -- Load it back to check context
        local loaded_chat = test_history.storage:load_chat(chat_data.save_id)
        local index = test_history.storage:get_chats()
        local index_entry = index[chat_data.save_id]
        
        return {
            loaded_has_cwd = loaded_chat.cwd ~= nil,
            loaded_has_project_root = loaded_chat.project_root ~= nil,
            index_has_cwd = index_entry.cwd ~= nil,
            index_has_project_root = index_entry.project_root ~= nil,
            cwd_is_string = type(loaded_chat.cwd) == "string",
            project_root_is_string = type(loaded_chat.project_root) == "string"
        }
    ]])

    eq(true, result.loaded_has_cwd)
    eq(true, result.loaded_has_project_root)
    eq(true, result.index_has_cwd)
    eq(true, result.index_has_project_root)
    eq(true, result.cwd_is_string)
    eq(true, result.project_root_is_string)
end

-- Filter Function Application Tests
T["Filter Function Application"] = new_set()

T["Filter Function Application"]["get_chats with filter applies filtering"] = function()
    local result = child.lua([[
        local h = require("tests.helpers")
        
        -- Create chats with different titles
        local chats = {
            { id = "keep_this_1", title = "Keep This Chat 1" },
            { id = "filter_out_1", title = "Filter Out Chat 1" },
            { id = "keep_this_2", title = "Keep This Chat 2" },
        }
        
        for _, chat in ipairs(chats) do
            local mock_chat = {
                opts = { save_id = chat.id, title = chat.title },
                messages = h.create_test_chat(chat.id).messages,
                settings = {},
                adapter = { name = "test" },
                refs = {}, tools = { schemas = {}, in_use = {} },
                cycle = 1
            }
            test_history.storage:save_chat(mock_chat)
        end
        
        -- Filter to only include chats with "Keep This" in title
        local filtered_chats = test_history.storage:get_chats(function(chat_data)
            return chat_data.title:find("Keep This") ~= nil
        end)
        
        return {
            filtered_count = vim.tbl_count(filtered_chats),
            has_keep1 = filtered_chats["keep_this_1"] ~= nil,
            has_keep2 = filtered_chats["keep_this_2"] ~= nil,
            has_filter_out = filtered_chats["filter_out_1"] ~= nil
        }
    ]])

    eq(2, result.filtered_count)
    eq(true, result.has_keep1)
    eq(true, result.has_keep2)
    eq(false, result.has_filter_out)
end

T["Filter Function Application"]["get_last_chat with filter finds filtered last chat"] = function()
    local result = child.lua([[
        local h = require("tests.helpers")
        local base_time = os.time()
        
        -- Create chats with different timestamps and adapters
        local chats = {
            { id = "old_openai", adapter = "openai", time_offset = -100 },
            { id = "recent_test", adapter = "test", time_offset = -10 },
            { id = "newest_openai", adapter = "openai", time_offset = -5 },
        }
        
        for _, chat in ipairs(chats) do
            local chat_data = h.create_test_chat(chat.id)
            chat_data.updated_at = base_time + chat.time_offset
            chat_data.adapter = chat.adapter
            
            local mock_chat = {
                opts = { save_id = chat.id, title = chat_data.title },
                messages = chat_data.messages,
                settings = {},
                adapter = { name = chat.adapter },
                refs = {}, tools = { schemas = {}, in_use = {} },
                cycle = 1
            }
            test_history.storage:save_chat(mock_chat)
            
            -- Update the saved chat's timestamp and adapter
            local saved_chat = test_history.storage:load_chat(chat.id)
            saved_chat.updated_at = base_time + chat.time_offset
            saved_chat.adapter = chat.adapter
            test_history.storage:_save_chat_to_file(saved_chat)
            test_history.storage:_update_index_entry(saved_chat)
        end
        
        -- Get last chat filtered by adapter
        local last_openai_chat = test_history.storage:get_last_chat(function(chat_data)
            return chat_data.adapter == "openai"
        end)
        
        local last_any_chat = test_history.storage:get_last_chat()
        
        return {
            last_openai_id = last_openai_chat and last_openai_chat.save_id,
            last_any_id = last_any_chat and last_any_chat.save_id,
            openai_is_newest_filtered = last_openai_chat and last_openai_chat.save_id == "newest_openai",
            any_is_newest_overall = last_any_chat and last_any_chat.save_id == "newest_openai"
        }
    ]])

    eq("newest_openai", result.last_openai_id)
    eq("newest_openai", result.last_any_id)
    eq(true, result.openai_is_newest_filtered)
    eq(true, result.any_is_newest_overall)
end

return T
