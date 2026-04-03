---@class CodeCompanion.History
---@field opts CodeCompanion.History.Opts
---@field storage CodeCompanion.History.Storage
---@field ui CodeCompanion.History.UI
---@field should_load_last_chat boolean
---@field new fun(opts: CodeCompanion.History.Opts): CodeCompanion.History
local History = {}
local log = require("codecompanion._extensions.history.log")
local pickers = require("codecompanion._extensions.history.pickers")

---Monkey patch to save some extra fields in the Chat instance
---@class CodeCompanion.History.ChatArgs : CodeCompanion.ChatArgs
---@field save_id string?
---@field title string?
---@field cwd string? Current working directory when chat was saved

---@class CodeCompanion.History.Chat : CodeCompanion.Chat
---@field opts CodeCompanion.History.ChatArgs

---@type CodeCompanion.History|nil
local history_instance

---@type CodeCompanion.History.Opts
local default_opts = {
    ---A name for the chat buffer that tells that this is a auto saving chat
    default_buf_title = "[CodeCompanion] " .. " ",

    ---Keymap to open history from chat buffer (default: gh)
    keymap = "gh",
    ---Description for the history keymap (for which-key integration)
    keymap_description = "Browse saved chats",
    ---Keymap to save the current chat manually
    save_chat_keymap = "sc",
    ---Description for the save chat keymap (for which-key integration)
    save_chat_keymap_description = "Save current chat",
    ---Number of days after which chats are automatically deleted (0 to disable)
    expiration_days = 0,
    ---Valid Picker interface (only "fzf-lua" is supported in simplified version)
    ---@type CodeCompanion.History.Pickers
    picker = "fzf-lua",
    picker_keymaps = {
        rename = {
            n = "r",
            i = "<M-r>",
        },
        delete = {
            n = "d",
            i = "<M-d>",
        },
        duplicate = {
            n = "<C-y>",
            i = "<C-y>",
        },
    },
    ---On exiting and entering neovim, loads the last chat on opening chat
    continue_last_chat = false,
    ---When chat is cleared with `gx` delete the chat from history
    delete_on_clearing_chat = false,
    ---Directory path to save the chats
    dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history",
    ---Enable detailed logging for history extension
    enable_logging = false,
    ---Filter function for browsing chats (defaults to show all chats)
    chat_filter = nil,
}

---@type CodeCompanion.History|nil
local history_instance

---@class CodeCompanion.History
---@param opts CodeCompanion.History.Opts
---@return CodeCompanion.History
function History.new(opts)
    local history = setmetatable({}, {
        __index = History,
    })
    history.opts = opts
    history.storage = require("codecompanion._extensions.history.storage").new(opts)
    history.ui = require("codecompanion._extensions.history.ui").new(opts, history.storage)
    history.should_load_last_chat = opts.continue_last_chat

    -- Setup commands
    history:_create_commands()
    history:_setup_autocommands()
    history:_setup_keymaps()
    return history --[[@as CodeCompanion.History]]
end

function History:_create_commands()
    vim.api.nvim_create_user_command("CodeCompanionHistory", function()
        self.ui:open_saved_chats(self.opts.chat_filter)
    end, {
        desc = "Open saved chats",
    })
end

function History:_setup_autocommands()
    local group = vim.api.nvim_create_augroup("CodeCompanionHistory", { clear = true })
    vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionChatCreated",
        group = group,
        callback = vim.schedule_wrap(function(opts)
            log:trace("Chat created event received")
            local chat_module = require("codecompanion.interactions.chat")
            local bufnr = opts.data.bufnr
            local chat = chat_module.buf_get_chat(bufnr) --[[@as CodeCompanion.History.Chat]]

            if self.should_load_last_chat then
                log:trace("Attempting to load last chat")
                self.should_load_last_chat = false
                local last_saved_chat = self.storage:get_last_chat(self.opts.chat_filter)
                if last_saved_chat then
                    log:trace("Restoring last saved chat")
                    chat:close()
                    self.ui:create_chat(last_saved_chat)
                    return
                end
            end

            -- Set initial buffer title with random ID
            if not chat.opts.title then
                chat.opts.title = self:_generate_random_title()
                log:trace("Generated random title: %s", chat.opts.title)
            end
            self.ui:update_chat_title(chat)

            --Check if custom save_id exists, else generate
            if not chat.opts.save_id then
                chat.opts.save_id = tostring(os.time())
                log:trace("Generated new save_id: %s", chat.opts.save_id)
            end
        end),
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionChatCleared",
        group = group,
        callback = vim.schedule_wrap(function(opts)
            log:trace("Chat cleared event received")

            local chat_module = require("codecompanion.interactions.chat")
            local bufnr = opts.data.bufnr
            local chat = chat_module.buf_get_chat(bufnr) --[[@as CodeCompanion.History.Chat]]
            if not chat then
                return
            end
            if self.opts.delete_on_clearing_chat then
                log:trace("Deleting cleared chat from storage: %s", chat.opts.save_id)
                self.storage:delete_chat(chat.opts.save_id)
            end

            -- Reset chat state
            chat.opts.title = nil
            chat.opts.save_id = tostring(os.time())
            log:trace("Generated new save_id after clear: %s", chat.opts.save_id)

            -- Update title
            self.ui:update_chat_title(chat)
        end),
    })
end

---@param chat? CodeCompanion.History.Chat
local function generate_summary(chat)
    -- This function is no longer supported in simplified version
    vim.notify("Summary generation is not available in this simplified version", vim.log.levels.WARN)
end

function History:_generate_random_title()
    local random_strings = {
        "Chat " .. math.random(1000, 9999),
        "Conversation " .. os.date("%H:%M"),
        "Session " .. string.sub(tostring(os.time()), -5),
        "Talk " .. math.random(100, 999),
        "Dialog " .. os.date("%H:%M:%S"):gsub(":", ""),
    }
    return random_strings[math.random(#random_strings)]
end

function History:_setup_keymaps()
    local function form_modes(v)
        if type(v) == "string" then
            return {
                n = v,
            }
        end
        return v
    end

    local keymaps = {
        ["Saved Chats"] = {
            modes = form_modes(self.opts.keymap),
            description = self.opts.keymap_description,
            callback = function(_)
                self.ui:open_saved_chats(self.opts.chat_filter)
            end,
        },
        ["Save Current Chat"] = {
            modes = form_modes(self.opts.save_chat_keymap),
            description = self.opts.save_chat_keymap_description,
            callback = function(chat)
                if not chat then
                    return
                end
                self.storage:save_chat(chat)
                vim.notify("Chat saved successfully", vim.log.levels.INFO)
                log:debug("Saved current chat")
            end,
        },
    }

    local cc_config = require("codecompanion.config")
    -- Add all keymaps to codecompanion
    for name, keymap in pairs(keymaps) do
        cc_config.interactions.chat.keymaps[name] = keymap
    end
end

---@type CodeCompanion.Extension
return {
    ---@param opts CodeCompanion.History.Opts
    setup = function(opts)
        if not history_instance then
            -- Initialize logging first
            opts = vim.tbl_deep_extend("force", default_opts, opts or {})
            log.setup_logging(opts.enable_logging)
            history_instance = History.new(opts)
            log:debug("History extension setup successfully")
        end
    end,
    exports = {
        ---Get the base path of the storage
        ---@return string?
        get_location = function()
            if not history_instance then
                return
            end
            return history_instance.storage:get_location()
        end,
        ---Save a chat to storage falling back to the last chat if none is provided
        ---@param chat? CodeCompanion.History.Chat
        save_chat = function(chat)
            if not history_instance then
                return
            end
            history_instance.storage:save_chat(chat)
        end,

        ---Browse chats with custom filter function
        ---@param filter_fn? fun(chat_data: CodeCompanion.History.ChatIndexData): boolean Optional filter function
        browse_chats = function(filter_fn)
            if not history_instance then
                return
            end
            history_instance.ui:open_saved_chats(filter_fn)
        end,

        --- Loads chats metadata from the index with optional filtering
        ---@param filter_fn? fun(chat_data: CodeCompanion.History.ChatIndexData): boolean Optional filter function
        ---@return table<string, CodeCompanion.History.ChatIndexData>
        get_chats = function(filter_fn)
            if not history_instance then
                return {}
            end
            return history_instance.storage:get_chats(filter_fn)
        end,

        --- Load a specific chat
        ---@param save_id string ID from chat.opts.save_id to retreive the chat
        ---@return CodeCompanion.History.ChatData?
        load_chat = function(save_id)
            if not history_instance then
                return
            end
            return history_instance.storage:load_chat(save_id)
        end,

        ---Delete a chat
        ---@param save_id string ID from chat.opts.save_id to retreive the chat
        ---@return boolean
        delete_chat = function(save_id)
            if not history_instance then
                return false
            end
            return history_instance.storage:delete_chat(save_id)
        end,

        ---Duplicate a chat
        ---@param save_id string ID from chat.opts.save_id to duplicate
        ---@param new_title? string Optional new title (defaults to "Title (1)")
        ---@return string|nil new_save_id The new chat's save_id if successful
        duplicate_chat = function(save_id, new_title)
            if not history_instance then
                return nil
            end
            return history_instance.storage:duplicate_chat(save_id, new_title)
        end,
    },
    --for testing
    History = History,
}
