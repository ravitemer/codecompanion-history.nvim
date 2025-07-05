---@class History
---@field opts HistoryOpts
---@field storage Storage
---@field title_generator TitleGenerator
---@field ui UI
---@field should_load_last_chat boolean
---@field new fun(opts: HistoryOpts): History

local History = {}
local log = require("codecompanion._extensions.history.log")
local pickers = require("codecompanion._extensions.history.pickers")

---@type HistoryOpts
local default_opts = {
    ---A name for the chat buffer that tells that this is a auto saving chat
    default_buf_title = "[CodeCompanion] " .. " ",

    ---Keymap to open history from chat buffer (default: gh)
    keymap = "gh",
    ---Description for the history keymap (for which-key integration)
    keymap_description = "Browse saved chats",
    ---Keymap to save the current chat manually (when auto_save is disabled)
    save_chat_keymap = "sc",
    ---Description for the save chat keymap (for which-key integration)
    save_chat_keymap_description = "Save current chat",
    ---Save all chats by default (disable to save only manually using 'sc')
    auto_save = true,
    ---Number of days after which chats are automatically deleted (0 to disable)
    expiration_days = 0,
    ---Valid Picker interface ("telescope", "snacks", "fzf-lua", or "default")
    ---@type Pickers
    picker = pickers.history,
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
    ---Automatically generate titles for new chats
    auto_generate_title = true,
    title_generation_opts = {
        ---Adapter for generating titles (defaults to current chat adapter)
        adapter = nil,
        ---Model for generating titles (defaults to current chat model)
        model = nil,
        ---Number of user prompts after which to refresh the title (0 to disable)
        refresh_every_n_prompts = 0,
        ---Maximum number of times to refresh the title (default: 3)
        max_refreshes = 3,
        format_title = nil,
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

---@type History|nil
local history_instance

---@param opts HistoryOpts
---@return History
function History.new(opts)
    local history = setmetatable({}, {
        __index = History,
    })
    history.opts = opts
    history.storage = require("codecompanion._extensions.history.storage").new(opts)
    history.title_generator = require("codecompanion._extensions.history.title_generator").new(opts)
    history.ui = require("codecompanion._extensions.history.ui").new(opts, history.storage, history.title_generator)
    history.should_load_last_chat = opts.continue_last_chat

    -- Setup commands
    history:_create_commands()
    history:_setup_autocommands()
    history:_setup_keymaps()
    return history --[[@as History]]
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
    -- util.fire("ChatCreated", { bufnr = self.bufnr, from_prompt_library = self.from_prompt_library, id = self.id })
    vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionChatCreated",
        group = group,
        callback = vim.schedule_wrap(function(opts)
            -- data = {
            --   bufnr = 5,
            --   from_prompt_library = false,
            --   id = 7463137
            -- },
            log:trace("Chat created event received")
            local chat_module = require("codecompanion.strategies.chat")
            local bufnr = opts.data.bufnr
            local chat = chat_module.buf_get_chat(bufnr)

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
            -- Set initial buffer title if present that we passed while creating a chat from history

            -- Set initial buffer title
            if chat.opts.title then
                log:trace("Setting existing chat title: %s", chat.opts.title)
                self.ui:_set_buf_title(chat.bufnr, chat.opts.title)
            else
                --set title to tell that this is a auto saving chat
                local title = self:_get_title(chat)
                log:trace("Setting default chat title: %s", title)
                self.ui:_set_buf_title(chat.bufnr, title)
            end

            --Check if custom save_id exists, else generate
            if not chat.opts.save_id then
                chat.opts.save_id = tostring(os.time())
                log:trace("Generated new save_id: %s", chat.opts.save_id)
            end

            -- self:_subscribe_to_chat(chat)
        end),
    })
    vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanion*Finished",
        group = group,
        callback = vim.schedule_wrap(function(opts)
            if not self.opts.auto_save then
                return
            end
            if opts.match == "CodeCompanionRequestFinished" or opts.match == "CodeCompanionAgentFinished" then
                log:trace("Chat %s event received for %s", opts.match, opts.data.strategy)
                if opts.match == "CodeCompanionRequestFinished" and opts.data.strategy ~= "chat" then
                    return log:trace("Skipping RequestFinished event received for non-chat strategy")
                end
                local chat_module = require("codecompanion.strategies.chat")
                local bufnr = opts.data.bufnr
                if not bufnr then
                    return log:trace("No bufnr found in event data")
                end
                local chat = chat_module.buf_get_chat(bufnr)
                if chat then
                    self.storage:save_chat(chat)
                end
            end
        end),
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionChatSubmitted",
        group = group,
        callback = vim.schedule_wrap(function(opts)
            log:trace("Chat submitted event received")
            local chat_module = require("codecompanion.strategies.chat")
            local bufnr = opts.data.bufnr
            local chat = chat_module.buf_get_chat(bufnr)
            if not chat then
                return
            end

            -- Handle title generation/refresh
            local should_generate, is_refresh = self.title_generator:should_generate(chat)
            if should_generate then
                self.title_generator:generate(chat, function(generated_title)
                    if type(self.opts.title_generation_opts.format_title) == "function" then
                        generated_title = self.opts.title_generation_opts.format_title(generated_title)
                    end
                    if generated_title and generated_title ~= "" then
                        -- Always update buffer title for feedback
                        self.ui:_set_buf_title(chat.bufnr, generated_title)

                        -- Only update chat.opts.title and save for real titles (not feedback)
                        if generated_title ~= "Deciding title..." and generated_title ~= "Refreshing title..." then
                            if is_refresh then
                                chat.opts.title_refresh_count = (chat.opts.title_refresh_count or 0) + 1
                            end

                            chat.opts.title = generated_title

                            if self.opts.auto_save then
                                self.storage:save_chat(chat)
                            end
                        end
                    else
                        -- Fallback to default title when generation fails
                        local default_title = self:_get_title(chat)
                        self.ui:_set_buf_title(chat.bufnr, default_title)
                    end
                end, is_refresh)
            end

            if self.opts.auto_save then
                self.storage:save_chat(chat)
            end
        end),
    })

    vim.api.nvim_create_autocmd("User", {
        pattern = "CodeCompanionChatCleared",
        group = group,
        callback = vim.schedule_wrap(function(opts)
            log:trace("Chat cleared event received")

            local chat_module = require("codecompanion.strategies.chat")
            local bufnr = opts.data.bufnr
            local chat = chat_module.buf_get_chat(bufnr)
            if not chat then
                return
            end
            if self.opts.delete_on_clearing_chat then
                log:trace("Deleting cleared chat from storage: %s", chat.opts.save_id)
                self.storage:delete_chat(chat.opts.save_id)
            end

            log:trace("Current title: %s", chat.opts.title)
            local title = self:_get_title(chat)
            log:trace("Resetting chat title: %s", title)
            self.ui:_set_buf_title(chat.bufnr, title)

            -- Reset chat state
            chat.opts.title = nil
            chat.opts.save_id = tostring(os.time())
            log:trace("Generated new save_id after clear: %s", chat.opts.save_id)
        end),
    })
end

---@param chat Chat
---@param title? string
---@return string
function History:_get_title(chat, title)
    return title and title or (self.opts.default_buf_title .. " " .. chat.id)
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
            keymap = self.opts.keymap,
            description = self.opts.keymap_description,
            callback = function(_)
                self.ui:open_saved_chats(self.opts.chat_filter)
            end,
        },
        ["Save Current Chat"] = {
            keymap = self.opts.save_chat_keymap,
            description = self.opts.save_chat_keymap_description,
            callback = function(chat)
                if not chat then
                    return
                end
                self.storage:save_chat(chat)
                log:debug("Saved current chat")
            end,
        },
    }

    for name, keymap_config in pairs(keymaps) do
        if keymap_config.keymap then
            require("codecompanion.config").strategies.chat.keymaps[name] = {
                modes = form_modes(keymap_config.keymap),
                description = keymap_config.description,
                callback = keymap_config.callback,
            }
        end
    end
end

-- ---@param chat Chat
-- function History:_subscribe_to_chat(chat)
--     -- Add subscription to save chat on every response from llm
--     chat.subscribers:subscribe({
--         --INFO:data field is needed
--         data = {
--             name = "save_messages_and_generate_title",
--         },
--         callback = function(chat_instance)
--             self.storage:save_chat(chat_instance)
--         end,
--     })
-- end

---@type CodeCompanion.Extension
return {
    ---@param opts HistoryOpts
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
        ---@param chat? Chat
        save_chat = function(chat)
            if not history_instance then
                return
            end
            history_instance.storage:save_chat(chat)
        end,

        ---Browse chats with custom filter function
        ---@param filter_fn? fun(chat_data: ChatIndexData): boolean Optional filter function
        browse_chats = function(filter_fn)
            if not history_instance then
                return
            end
            history_instance.ui:open_saved_chats(filter_fn)
        end,

        --- Loads chats metadata from the index with optional filtering
        ---@param filter_fn? fun(chat_data: ChatIndexData): boolean Optional filter function
        ---@return table<string, ChatIndexData>
        get_chats = function(filter_fn)
            if not history_instance then
                return {}
            end
            return history_instance.storage:get_chats(filter_fn)
        end,

        --- Load a specific chat
        ---@param save_id string ID from chat.opts.save_id to retreive the chat
        ---@return ChatData?
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
