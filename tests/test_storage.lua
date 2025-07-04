---@brief [[
--- Storage Module Tests
---
--- This test suite verifies the functionality of the storage module in the CodeCompanion
--- history extension. It tests various aspects of chat history storage including:
---
--- 1. Storage Initialization:
---    - Directory creation and structure
---    - Index file initialization
---
--- 2. Save Operations:
---    - Basic chat saving
---    - Index updates
---    - Complete chat data persistence
---    - Large data handling
---    - Concurrent access
---
--- 3. Load Operations:
---    - Individual chat loading
---    - Bulk loading
---    - Non-existent chat handling
---
--- 4. Delete Operations:
---    - Chat and index deletion
---    - Non-existent chat handling
---    - Error cases
---
--- 5. Last Chat Operations:
---    - Most recent chat retrieval
---    - Empty storage handling
---
--- 6. Error Handling:
---    - Invalid data structures
---    - Missing files
---    - Corrupted data
---    - Permission issues
---    - UTF-8 validation
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
              -- Setup logging first
              local log = require("codecompanion._extensions.history.log")
              log.setup_logging(false) -- Disable logging for tests
              
              -- Create fresh storage instance with test dir
              local Storage = require("codecompanion._extensions.history.storage")
              test_storage = Storage.new({
                  dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history-temp-" .. os.time()
              })
            ]])
        end,
        post_case = function()
            -- Clean up test directory
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

-- Storage Initialization Tests
T["Storage Initialization"] = new_set()

T["Storage Initialization"]["creates required directories"] = function()
    local result = child.lua([[              
        local base_dir_exists = vim.fn.isdirectory(test_storage.base_path) == 1
        local chats_dir_exists = vim.fn.isdirectory(test_storage.chats_dir) == 1

        return {
            base_dir_exists = base_dir_exists,
            chats_dir_exists = chats_dir_exists,
            base_path = test_storage.base_path,
            chats_dir = test_storage.chats_dir,
            index_path = test_storage.index_path
        }
    ]])

    eq(true, result.base_dir_exists)
    eq(true, result.chats_dir_exists)
    eq(true, vim.endswith(result.base_path, "codecompanion-history-temp-" .. result.base_path:match("%d+$")))
    eq(true, vim.endswith(result.chats_dir, "chats"))
    eq(true, vim.endswith(result.index_path, "index.json"))
end

T["Storage Initialization"]["creates empty index file"] = function()
    local result = child.lua([[              
        local Path = require("plenary.path")
        local path = Path:new(test_storage.index_path)
        local content = path:read()
        return { index_content = content }
    ]])

    eq("{}", vim.trim(result.index_content))
end

T["Storage Initialization"]["provides storage location"] = function()
    local result = child.lua([[              
        local location = test_storage:get_location()
        return {
            location = location,
            has_test_suffix = vim.endswith(location, "codecompanion-history-temp-" .. location:match("%d+$"))
        }
    ]])

    eq(true, result.has_test_suffix)
end

-- Save Operations Tests
T["Save Operations"] = new_set()

T["Save Operations"]["saves chat to file"] = function()
    local result = child.lua([[              
        -- Create and save test chat
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_save_123")
        local save_result = test_storage:_save_chat_to_file(chat_data)
        
        -- Check if file exists and content is correct
        local chat_path = test_storage.chats_dir .. "/test_save_123.json"
        local Path = require("plenary.path")
        local path = Path:new(chat_path)
        local file_exists = path:exists()
        local content = file_exists and path:read()
        
        return {
            ok = save_result.ok,
            error = save_result.error,
            file_exists = file_exists,
            has_save_id = content and content:find('"save_id":"test_save_123"') ~= nil,
            has_title = content and content:find('"title":"Test Chat test_save_123"') ~= nil
        }
    ]])

    eq(true, result.ok)
    eq(nil, result.error)
    eq(true, result.file_exists)
    eq(true, result.has_save_id)
    eq(true, result.has_title)
end

T["Save Operations"]["updates index when saving chat"] = function()
    local result = child.lua([[              
        -- Create and save test chat
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_index_123")
        local update_result = test_storage:_update_index_entry(chat_data)
        
        -- Read index to verify
        local index = test_storage:get_chats()
        
        return {
            ok = update_result.ok,
            error = update_result.error,
            index_entry = index["test_index_123"],
            timestamp_type = type(index["test_index_123"].updated_at)
        }
    ]])

    eq(true, result.ok)
    eq(nil, result.error)
    eq("test_index_123", result.index_entry.save_id)
    eq("Test Chat test_index_123", result.index_entry.title)
    eq("number", result.timestamp_type)
end

T["Save Operations"]["handles large chat data"] = function()
    local result = child.lua([[              
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_large")
        
        -- Add large number of messages
        for i = 1, 1000 do
            table.insert(chat_data.messages, {
                role = "user",
                content = string.rep("test message " .. i .. " ", 100)
            })
        end
        
        local save_result = test_storage:_save_chat_to_file(chat_data)
        local loaded_chat = test_storage:load_chat("test_large")
        
        return {
            save_ok = save_result.ok,
            loaded_ok = loaded_chat ~= nil,
            message_count = loaded_chat and #loaded_chat.messages
        }
    ]])

    eq(true, result.save_ok)
    eq(true, result.loaded_ok)
    eq(1003, result.message_count) -- Original 3 + 1000 new messages
end

T["Save Operations"]["handles concurrent file access"] = function()
    local result = child.lua([[              
        -- Simulate concurrent access by creating multiple saves rapidly
        local h = require("tests.helpers")
        local chat = h.create_test_chat("test_concurrent")
        
        -- Create multiple saves in quick succession
        local results = {}
        for i = 1, 5 do
            local success = pcall(function()
                test_storage:save_chat({
                    opts = { 
                        save_id = chat.save_id,
                        title = chat.title .. "_" .. i
                    },
                    messages = chat.messages
                })
            end)
            table.insert(results, success)
        end
        
        -- Verify final state
        local final_chat = test_storage:load_chat("test_concurrent")
        
        return {
            all_attempts_succeeded = vim.tbl_contains(results, false) == false,
            chat_exists = final_chat ~= nil,
            is_valid = final_chat and final_chat.save_id == "test_concurrent"
        }
    ]])

    eq(true, result.all_attempts_succeeded)
    eq(true, result.chat_exists)
    eq(true, result.is_valid)
end

T["Save Operations"]["saves complete chat"] = function()
    local result = child.lua([[              
        -- Create and save complete chat
        local h = require("tests.helpers")
        local chat_data = h.create_test_chat("test_complete_123")
        test_storage:save_chat({ 
            opts = { 
                save_id = chat_data.save_id,
                title = chat_data.title
            },
            messages = chat_data.messages,
            settings = chat_data.settings,
            adapter = { name = chat_data.adapter },
            refs = chat_data.refs,
            tools = {
                schemas = chat_data.schemas,
                in_use = chat_data.in_use
            },
            cycle = chat_data.cycle
        })
        
        -- Load the chat back to verify
        local loaded_chat = test_storage:load_chat("test_complete_123")
        local index = test_storage:get_chats()
        
        return {
            loaded_chat = loaded_chat,
            index_entry = index["test_complete_123"],
            message_count = loaded_chat and #loaded_chat.messages
        }
    ]])

    eq("test_complete_123", result.loaded_chat.save_id)
    eq("Test Chat test_complete_123", result.loaded_chat.title)
    eq(3, result.message_count)
    eq("test_complete_123", result.index_entry.save_id)
    eq("Test Chat test_complete_123", result.index_entry.title)
end

-- Load Operations Tests
T["Load Operations"] = new_set()

T["Load Operations"]["loads chat by ID"] = function()
    local result = child.lua([[              
        -- Create and save test chat
        local h = require("tests.helpers")
        local original_chat = h.create_test_chat("test_load_123")
        test_storage:_save_chat_to_file(original_chat)
        test_storage:_update_index_entry(original_chat)
        
        -- Load the chat
        local loaded_chat = test_storage:load_chat("test_load_123")
        
        return {
            loaded_chat = loaded_chat,
            original_title = original_chat.title,
            loaded_title = loaded_chat.title,
            message_count = #loaded_chat.messages,
            first_message = loaded_chat.messages[1].content
        }
    ]])

    eq("Test Chat test_load_123", result.original_title)
    eq(result.original_title, result.loaded_title)
    eq(3, result.message_count)
    eq("Test system message", result.first_message)
end

T["Load Operations"]["returns nil for non-existent chat"] = function()
    local result = child.lua([[              
        -- Try to load non-existent chat
        local loaded_chat = test_storage:load_chat("does_not_exist")
        return { loaded_chat = loaded_chat }
    ]])

    eq(nil, result.loaded_chat)
end

T["Load Operations"]["loads all chats from index"] = function()
    local result = child.lua([[              
        local h = require("tests.helpers")
        -- Create and save multiple test chats
        local chats = {
            h.create_test_chat("test_all_1"),
            h.create_test_chat("test_all_2"),
            h.create_test_chat("test_all_3")
        }
        
        -- Save all test chats
        for _, chat in ipairs(chats) do
            test_storage:_save_chat_to_file(chat)
            test_storage:_update_index_entry(chat)
        end
        
        -- Get all chats
        local all_chats = test_storage:get_chats()
        
        return {
            chat_count = vim.tbl_count(all_chats),
            has_chat1 = all_chats["test_all_1"] ~= nil,
            has_chat2 = all_chats["test_all_2"] ~= nil,
            has_chat3 = all_chats["test_all_3"] ~= nil,
            title1 = all_chats["test_all_1"] and all_chats["test_all_1"].title,
            title2 = all_chats["test_all_2"] and all_chats["test_all_2"].title,
            title3 = all_chats["test_all_3"] and all_chats["test_all_3"].title
        }
    ]])

    eq(3, result.chat_count)
    eq(true, result.has_chat1)
    eq(true, result.has_chat2)
    eq(true, result.has_chat3)
    eq("Test Chat test_all_1", result.title1)
    eq("Test Chat test_all_2", result.title2)
    eq("Test Chat test_all_3", result.title3)
end

-- Delete Operations Tests
T["Delete Operations"] = new_set()

T["Delete Operations"]["deletes chat and index entry"] = function()
    local result = child.lua([[              
        local h = require("tests.helpers")
        -- Create and save test chat
        local chat = h.create_test_chat("test_delete_123")
        test_storage:_save_chat_to_file(chat)
        test_storage:_update_index_entry(chat)
        
        -- Verify chat exists
        local before_delete = test_storage:load_chat("test_delete_123") ~= nil
        local before_index = test_storage:get_chats()["test_delete_123"] ~= nil
        
        -- Delete the chat
        local delete_result = test_storage:delete_chat("test_delete_123")
        
        -- Check if chat is gone
        local after_delete = test_storage:load_chat("test_delete_123") ~= nil
        local after_index = test_storage:get_chats()["test_delete_123"] ~= nil
        
        return {
            delete_success = delete_result,
            before_delete = before_delete,
            before_index = before_index,
            after_delete = after_delete,
            after_index = after_index
        }
    ]])

    eq(true, result.delete_success)
    eq(true, result.before_delete)
    eq(true, result.before_index)
    eq(false, result.after_delete)
    eq(false, result.after_index)
end

T["Delete Operations"]["handles non-existent chat deletion gracefully"] = function()
    local result = child.lua([[              
        -- Try to delete non-existent chat
        local delete_result = test_storage:delete_chat("does_not_exist")
        return { delete_success = delete_result }
    ]])

    -- Should return true even if chat didn't exist (idempotent operation)
    eq(true, result.delete_success)
end

T["Delete Operations"]["handles missing save_id in deletion"] = function()
    local result = child.lua([[              
        -- Try to delete without an ID
        local delete_result = test_storage:delete_chat(nil)
        return { delete_success = delete_result }
    ]])

    eq(false, result.delete_success)
end

-- Last Chat Tests
T["Last Chat"] = new_set()

T["Last Chat"]["gets most recently updated chat"] = function()
    local result = child.lua([[              
        local h = require("tests.helpers")
        
        -- Create multiple chats with different timestamps
        local chat1 = h.create_test_chat("test_recent_1")
        chat1.updated_at = os.time() - 100 -- older
        
        local chat2 = h.create_test_chat("test_recent_2")
        chat2.updated_at = os.time() - 10  -- newest
        
        local chat3 = h.create_test_chat("test_recent_3")
        chat3.updated_at = os.time() - 50  -- in between
        
        -- Save all chats
        for _, chat in ipairs({chat1, chat2, chat3}) do
            test_storage:_save_chat_to_file(chat)
            test_storage:_update_index_entry(chat)
        end
        
        -- Get the most recent chat
        local last_chat = test_storage:get_last_chat()
        
        return {
            last_chat_id = last_chat and last_chat.save_id,
            last_chat_title = last_chat and last_chat.title,
            updated_at = last_chat and last_chat.updated_at
        }
    ]])

    -- The most recent chat should be chat2
    eq("test_recent_2", result.last_chat_id)
    eq("Test Chat test_recent_2", result.last_chat_title)
    -- Verify it's the newest timestamp
    eq(true, result.updated_at > os.time() - 20)
end

T["Last Chat"]["handles empty storage"] = function()
    local result = child.lua([[              
        -- Get the most recent chat from empty storage
        local last_chat = test_storage:get_last_chat()
        return { last_chat = last_chat }
    ]])

    eq(nil, result.last_chat)
end

-- Error Handling Tests
T["Error Handling"] = new_set()

T["Error Handling"]["handles save_chat without chat parameter"] = function()
    local result = child.lua([[              
        -- Mock codecompanion.last_chat() to return nil
        _G.codecompanion = { last_chat = function() return nil end }
        
        -- Try to save without chat parameter
        test_storage:save_chat()
        
        -- Check if any files were created
        local files = vim.fn.glob(test_storage.chats_dir .. "/*")
        
        return {
            files_created = files ~= ""
        }
    ]])

    eq(false, result.files_created)
end

T["Error Handling"]["handles invalid chat structure"] = function()
    local result = child.lua([[              
        -- Try to save invalid chat structure
        local invalid_chat = {
            opts = {} -- Missing save_id
        }
        test_storage:save_chat(invalid_chat)
        
        -- Check if any files were created
        local files = vim.fn.glob(test_storage.chats_dir .. "/*")
        
        return {
            files_created = files ~= ""
        }
    ]])

    eq(false, result.files_created)
end

T["Error Handling"]["handles missing index file"] = function()
    local result = child.lua([[              
        -- Delete index file
        vim.fn.delete(test_storage.index_path)
        
        -- Try to get chats
        local chats = test_storage:get_chats()
        
        -- Check if index was recreated
        local index_exists = vim.fn.filereadable(test_storage.index_path) == 1
        
        return {
            chats = chats,
            index_exists = index_exists
        }
    ]])

    eq({}, result.chats)
    eq(true, result.index_exists)
end

T["Error Handling"]["handles corrupted JSON in index"] = function()
    local result = child.lua([[              
        -- Write corrupt data to index
        local file = io.open(test_storage.index_path, "w")
        file:write("corrupted json{")
        file:close()
        
        -- Try to get chats
        local chats = test_storage:get_chats()
        
        return {
            chats = chats
        }
    ]])

    eq({}, result.chats)
end

T["Error Handling"]["validates nested message structure"] = function()
    local result = child.lua([[              
        -- Try to save chat with invalid message structure
        test_storage:save_chat({
            opts = {
                save_id = "test_invalid_msgs"
            },
            messages = {
                { role = 123 }, -- role should be string
                { content = {} }, -- content should be string
                "not a table"
            }
        })
        
        -- Check if file was created
        local chat_path = test_storage.chats_dir .. "/test_invalid_msgs.json"
        local file_exists = vim.fn.filereadable(chat_path) == 1
        
        return {
            file_exists = file_exists
        }
    ]])

    eq(false, result.file_exists)
end

T["Error Handling"]["handles permission errors"] = function()
    local result = child.lua([[              
        if vim.fn.has("win32") == 1 then
            return { skipped = true }
        end
        
        -- Make directory read-only
        vim.fn.system("chmod 444 " .. test_storage.chats_dir)
        
        -- Try to save a chat
        local h = require("tests.helpers")
        local chat = h.create_test_chat("test_perm")
        local save_result = test_storage:_save_chat_to_file(chat)
        
        -- Restore permissions for cleanup
        vim.fn.system("chmod 755 " .. test_storage.chats_dir)
        
        return {
            ok = save_result.ok,
            has_error = save_result.error ~= nil
        }
    ]])

    if result.skipped then
        return
    end
    eq(false, result.ok)
    eq(true, result.has_error)
end

T["Error Handling"]["handles invalid UTF-8 content"] = function()
    local result = child.lua([[              
        -- Create chat with invalid UTF-8 sequence
        local invalid_utf8 = string.char(0xFF, 0xFF)
        test_storage:save_chat({
            opts = {
                save_id = "test_utf8",
                title = "UTF-8 Test"
            },
            messages = {{
                role = "user",
                content = "Valid " .. invalid_utf8 .. " Invalid"
            }}
        })
        
        -- Try to load it back
        local loaded_chat = test_storage:load_chat("test_utf8")
        
        return {
            chat_saved = loaded_chat ~= nil,
            content_preserved = loaded_chat and loaded_chat.messages[1].content:find("Valid") ~= nil
        }
    ]])

    eq(true, result.chat_saved)
    eq(true, result.content_preserved)
end

-- Duplicate Operations Tests
T["Duplicate Operations"] = new_set()

T["Duplicate Operations"]["duplicates chat successfully"] = function()
    local result = child.lua([[              
        local h = require("tests.helpers")
        local original_chat = h.create_test_chat("test_original")
        test_storage:_save_chat_to_file(original_chat)
        test_storage:_update_index_entry(original_chat)
        
        -- Duplicate the chat with custom title
        local new_save_id = test_storage:duplicate_chat("test_original", "Duplicated Chat")
        local duplicated_chat = test_storage:load_chat(new_save_id)
        local index = test_storage:get_chats()
        
        return {
            new_save_id = new_save_id,
            duplicated_title = duplicated_chat and duplicated_chat.title,
            original_exists = index["test_original"] ~= nil,
            duplicate_exists = index[new_save_id] ~= nil,
            message_count_match = duplicated_chat and #duplicated_chat.messages == 3,
            different_save_ids = duplicated_chat and duplicated_chat.save_id ~= "test_original",
            title_refresh_count_reset = duplicated_chat and duplicated_chat.title_refresh_count == 0
        }
    ]])

    eq(true, result.new_save_id ~= nil)
    eq("Duplicated Chat", result.duplicated_title)
    eq(true, result.original_exists)
    eq(true, result.duplicate_exists)
    eq(true, result.message_count_match)
    eq(true, result.different_save_ids)
    eq(true, result.title_refresh_count_reset)
end

T["Duplicate Operations"]["duplicates chat with auto-generated title"] = function()
    local result = child.lua([[              
        local h = require("tests.helpers")
        local original_chat = h.create_test_chat("test_auto_title")
        original_chat.title = "Original Title"
        test_storage:_save_chat_to_file(original_chat)
        test_storage:_update_index_entry(original_chat)
        
        -- Duplicate without providing custom title
        local new_save_id = test_storage:duplicate_chat("test_auto_title")
        local duplicated_chat = test_storage:load_chat(new_save_id)
        
        return {
            duplicated_title = duplicated_chat and duplicated_chat.title,
            has_copy_suffix = duplicated_chat and duplicated_chat.title:find("%(1%)") ~= nil
        }
    ]])

    eq("Original Title (1)", result.duplicated_title)
    eq(true, result.has_copy_suffix)
end

T["Duplicate Operations"]["handles non-existent chat duplication"] = function()
    local result = child.lua([[              
        -- Try to duplicate non-existent chat
        local new_save_id = test_storage:duplicate_chat("does_not_exist")
        return { new_save_id = new_save_id }
    ]])

    eq(nil, result.new_save_id)
end

T["Duplicate Operations"]["preserves all chat data"] = function()
    local result = child.lua([[              
        local h = require("tests.helpers")
        local original_chat = h.create_test_chat("test_preserve")
        original_chat.refs = {{ id = "test_ref", content = "test content" }}
        original_chat.schemas = { test_schema = "schema_data" }
        original_chat.in_use = { test_tool = true }
        original_chat.cycle = 5
        
        test_storage:_save_chat_to_file(original_chat)
        test_storage:_update_index_entry(original_chat)
        
        -- Duplicate the chat
        local new_save_id = test_storage:duplicate_chat("test_preserve", "Preserved Data")
        local duplicated_chat = test_storage:load_chat(new_save_id)
        
        return {
            refs_preserved = duplicated_chat and #duplicated_chat.refs == 1,
            schemas_preserved = duplicated_chat and duplicated_chat.schemas.test_schema == "schema_data",
            in_use_preserved = duplicated_chat and duplicated_chat.in_use.test_tool == true,
            cycle_preserved = duplicated_chat and duplicated_chat.cycle == 5,
            messages_preserved = duplicated_chat and #duplicated_chat.messages == 3
        }
    ]])

    eq(true, result.refs_preserved)
    eq(true, result.schemas_preserved)
    eq(true, result.in_use_preserved)
    eq(true, result.cycle_preserved)
    eq(true, result.messages_preserved)
end

T["Duplicate Operations"]["handles duplicate with untitled chat"] = function()
    local result = child.lua([[              
        local h = require("tests.helpers")
        local original_chat = h.create_test_chat("test_untitled")
        original_chat.title = nil -- Remove title
        test_storage:_save_chat_to_file(original_chat)
        test_storage:_update_index_entry(original_chat)
        
        -- Duplicate chat without title
        local new_save_id = test_storage:duplicate_chat("test_untitled")
        local duplicated_chat = test_storage:load_chat(new_save_id)
        
        return {
            duplicated_title = duplicated_chat and duplicated_chat.title
        }
    ]])

    eq("Untitled (1)", result.duplicated_title)
end

return T
