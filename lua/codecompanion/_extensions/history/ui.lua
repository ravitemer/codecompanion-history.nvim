local config = require("codecompanion.config")
local log = require("codecompanion._extensions.history.log")
local utils = require("codecompanion._extensions.history.utils")

---@class CodeCompanion.History.UI
---@field storage CodeCompanion.History.Storage
---@field default_buf_title string
---@field picker CodeCompanion.History.Pickers
---@field picker_keymaps table
local UI = {}

---@param opts CodeCompanion.History.Opts
---@param storage CodeCompanion.History.Storage
---@return CodeCompanion.History.UI
function UI.new(opts, storage)
    local self = setmetatable({}, {
        __index = UI,
    })

    self.storage = storage
    self.default_buf_title = opts.default_buf_title
    self.picker = opts.picker
    self.picker_keymaps = opts.picker_keymaps

    log:trace("Initialized UI with picker: %s", opts.picker)
    return self --[[@as CodeCompanion.History.UI]]
end

---Update chat title
---@param chat CodeCompanion.History.Chat
function UI:update_chat_title(chat)
    log:trace("Updating chat title for: %s", chat.opts.save_id or "N/A")
    local base_title = chat.opts.title or (self.default_buf_title .. tostring(chat.id))
    self:_set_buf_title(chat.bufnr, base_title)
end

---Method for setting buffer title
---@param bufnr number
---@param title string|string[]
function UI:_set_buf_title(bufnr, title)
    vim.schedule(function()
        if type(title) == "table" then
            title = table.concat(title, " ")
        end
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_set_name(bufnr, title)
        end
    end)
end

---Open saved chats browser
---@param filter_fn? fun(chat_data: CodeCompanion.History.ChatIndexData): boolean Optional filter function
function UI:open_saved_chats(filter_fn)
    local codecompanion = require("codecompanion")
    local pickers = require("codecompanion._extensions.history.pickers")
    local last_chat = codecompanion.last_chat() --[[@as CodeCompanion.History.Chat?]]

    -- Convert chat dictionary to array for picker
    local chats_dict = self.storage:get_chats(filter_fn)
    local chats_array = {}
    for _, chat_data in pairs(chats_dict) do
        table.insert(chats_array, chat_data)
    end
    self:_open_items("chat", chats_array, {
        on_open = function()
            log:trace("Opening saved chats picker")
            self:open_saved_chats(filter_fn)
        end,
        ---@param chat_data CodeCompanion.History.ChatData
        ---@return string[] lines
        on_preview = function(chat_data)
            local full_chat = self.storage:load_chat(chat_data.save_id)
            if full_chat then
                return self:_get_preview_lines(full_chat)
            else
                log:warn("Failed to load chat data for preview: %s", chat_data.save_id)
                return { "Chat data not available" }
            end
        end,
        ---@param chat_data CodeCompanion.History.ChatData
        on_select = function(chat_data)
            self:_handle_on_select(chat_data.save_id)
        end,
        ---@param chat_data CodeCompanion.History.ChatData|CodeCompanion.History.ChatData[]
        on_delete = function(chat_data)
            local chats_to_delete = {}
            if type(chat_data) == "table" and chat_data.save_id then
                chats_to_delete = { chat_data }
            elseif type(chat_data) == "table" and #chat_data > 0 then
                chats_to_delete = chat_data
            else
                vim.notify("Invalid chat data for deletion", vim.log.levels.ERROR)
                return
            end

            log:trace("Deleting %d chat(s)", #chats_to_delete)

            local chat_count = #chats_to_delete
            local confirmation_message
            if chat_count == 1 then
                confirmation_message = string.format('Delete chat "%s"?', chats_to_delete[1].title or "Untitled")
            else
                confirmation_message = string.format("Delete %d chats?", chat_count)
            end

            local choice = vim.fn.confirm(confirmation_message, "&Yes\n&No", 2)
            if choice ~= 1 then
                return
            end

            local deleted_count = 0
            for _, chat in ipairs(chats_to_delete) do
                if self.storage:delete_chat(chat.save_id) then
                    deleted_count = deleted_count + 1
                end
            end

            if deleted_count > 0 then
                local message = deleted_count == 1 and "Chat deleted successfully"
                    or string.format("%d chats deleted successfully", deleted_count)
                vim.notify(message, vim.log.levels.INFO)
                self:open_saved_chats(filter_fn)
            else
                vim.notify("Failed to delete chats", vim.log.levels.ERROR)
            end
        end,
        ---@param chat_data CodeCompanion.History.ChatData
        on_rename = function(chat_data)
            log:trace("Renaming chat: %s", chat_data.save_id)

            vim.ui.input({
                prompt = "Rename to: ",
                default = chat_data.title or "",
            }, function(new_title)
                if not new_title or vim.trim(new_title) == "" then
                    return
                end

                local success = self.storage:rename_chat(chat_data.save_id, new_title)
                if success then
                    vim.notify("Chat renamed successfully", vim.log.levels.INFO)
                    self:open_saved_chats(filter_fn)
                else
                    vim.notify("Failed to rename chat", vim.log.levels.ERROR)
                end
            end)
        end,
        ---@param chat_data CodeCompanion.History.ChatData
        on_duplicate = function(chat_data)
            log:trace("Duplicating chat: %s", chat_data.save_id)

            vim.ui.input({
                prompt = "Duplicate as: ",
                default = chat_data.title or "",
            }, function(new_title)
                if not new_title or vim.trim(new_title) == "" then
                    local original_title = chat_data.title or "Untitled"
                    new_title = original_title .. " (1)"
                end

                local new_save_id = self.storage:duplicate_chat(chat_data.save_id, new_title)
                if new_save_id then
                    vim.notify("Chat duplicated successfully", vim.log.levels.INFO)
                    self:open_saved_chats(filter_fn)
                else
                    vim.notify("Failed to duplicate chat", vim.log.levels.ERROR)
                end
            end)
        end,
    }, last_chat and last_chat.opts.save_id)
end

---@param save_id string
function UI:_handle_on_select(save_id)
    local codecompanion = require("codecompanion")
    log:trace("Selected chat: %s", save_id)
    local chat_module = require("codecompanion.interactions.chat")
    local opened_chats = chat_module.buf_get_chat()
    local active_chat = codecompanion.last_chat()

    for _, data in ipairs(opened_chats) do
        if data.chat.opts.save_id == save_id then
            if (active_chat and not active_chat.ui:is_active()) or active_chat ~= data.chat then
                if active_chat and active_chat.ui:is_active() then
                    active_chat.ui:hide()
                end
                data.chat.ui:open()
            else
                log:trace("Chat already open: %s", save_id)
                vim.notify("Chat already open", vim.log.levels.INFO)
            end
            return
        end
    end

    local full_chat = self.storage:load_chat(save_id)
    if full_chat then
        self:create_chat(full_chat)
    else
        log:error("Failed to load chat: %s", save_id)
        vim.notify("Failed to load chat", vim.log.levels.ERROR)
    end
end

---Creates a new chat from saved data
---@param chat_data? CodeCompanion.History.ChatData
---@return CodeCompanion.History.Chat?
function UI:create_chat(chat_data)
    log:trace("Creating new chat from saved data")
    chat_data = chat_data or {}
    local messages = chat_data.messages or {}
    local save_id = chat_data.save_id
    local title = chat_data.title

    local last_msg = messages[#messages]

    if
        last_msg and (last_msg.role ~= "user" or (last_msg.role == "user" and (last_msg.opts or {}).visible == false))
    then
        log:trace("Adding empty user message to ensure header visibility")
        table.insert(messages, {
            role = "user",
            content = "",
            opts = { visible = true },
        })
    end

    local context_utils = require("codecompanion.utils.context")
    local last_active_buffer = require("codecompanion._extensions.history.utils").get_editor_info().last_active
    local context = context_utils.get(last_active_buffer and last_active_buffer.bufnr or nil)

    local function _create_chat(adapter, settings)
        local chat = require("codecompanion.interactions.chat").new({
            save_id = save_id,
            messages = messages,
            buffer_context = context,
            settings = settings,
            adapter = adapter --[[@as CodeCompanion.Adapter]],
            title = title,
        }) --[[@as CodeCompanion.History.Chat]]

        local stored_context_items = chat_data.context_items or chat_data.refs or {}
        local chat_context_items = chat.context_items or {}
        for _, item in ipairs(stored_context_items) do
            local is_duplicate = vim.tbl_contains(chat_context_items, function(chat_item)
                return chat_item.id == item.id
            end, { predicate = true })
            if not is_duplicate then
                chat.context:add(item)
            end
        end

        chat.tool_registry.schemas = chat_data.schemas or {}
        chat.tool_registry.in_use = chat_data.in_use or {}
        chat.cycle = chat_data.cycle or 1
        log:trace("Successfully created chat with save_id: %s", save_id or "N/A")
        return chat
    end

    local adapter = chat_data.adapter
    local settings = chat_data.settings or {}

    if adapter then
        local found, resolved_adapter = pcall(require("codecompanion.adapters").resolve, adapter)
        if not found then
            vim.notify(
                string.format("Adapter '%s' not available, please select another adapter", adapter),
                vim.log.levels.WARN
            )
            return self:_change_adapter(_create_chat)
        else
            if resolved_adapter.type ~= "acp" then
                local saved_model = settings.model
                if saved_model then
                    local available_models = resolved_adapter.schema.model.choices
                    if type(available_models) == "table" then
                        available_models = vim.iter(available_models)
                            :map(function(model, value)
                                if type(model) == "string" then
                                    return model
                                else
                                    return value
                                end
                            end)
                            :totable()
                        local has_model = vim.tbl_contains(available_models, saved_model)
                        if not has_model then
                            vim.notify(
                                string.format(
                                    "Model '%s' is not available in '%s' adapter, using default model.",
                                    saved_model,
                                    adapter
                                )
                            )
                            return _create_chat(adapter, nil)
                        end
                    end
                end
            end
        end
    end

    return _create_chat(adapter, settings)
end

---Get preview lines for a chat
---@param chat_data CodeCompanion.History.ChatData
---@return string[]
function UI:_get_preview_lines(chat_data)
    local lines = {}

    table.insert(lines, "Title: " .. (chat_data.title or "Untitled"))
    table.insert(lines, "Adapter: " .. (chat_data.adapter or "unknown"))
    table.insert(lines, "Messages: " .. tostring(#(chat_data.messages or {})))
    table.insert(lines, "Updated: " .. os.date("%Y-%m-%d %H:%M:%S", chat_data.updated_at or 0))
    table.insert(lines, "")
    table.insert(lines, "Preview:")
    table.insert(lines, "---")

    for i, msg in ipairs(chat_data.messages or {}) do
        if (msg.opts or {}).visible ~= false then
            local role = msg.role:upper()
            table.insert(lines, "")
            table.insert(lines, string.format("[%s]", role))
            local content_lines = vim.split(msg.content, "\n", { plain = true })
            for _, line in ipairs(content_lines) do
                if #lines >= 50 then
                    table.insert(lines, "... (truncated)")
                    break
                end
                table.insert(lines, line)
            end
        end
    end

    return lines
end

---Open items picker with handlers
---@param item_type string "chat" or "summary"
---@param items_data table
---@param handlers table
---@param current_item_id? string
function UI:_open_items(item_type, items_data, handlers, current_item_id)
    local pickers = require("codecompanion._extensions.history.pickers")
    local item_name_title = item_type == "chat" and "Saved Chats" or "Summaries"

    pickers.resolve(self.picker)
        :new({
            items = items_data,
            handlers = handlers,
            picker_keymaps = self.picker_keymaps,
            item_type = item_type,
            current_item_id = current_item_id,
            title = item_name_title,
        })
        :browse()
end

---Change adapter
---@param on_select function
function UI:_change_adapter(on_select)
    local adapters = require("codecompanion.adapters")
    local adapter_names = {}

    for name, _ in pairs(adapters.list()) do
        table.insert(adapter_names, name)
    end

    vim.ui.select(adapter_names, {
        prompt = "Select adapter: ",
    }, function(selected_adapter)
        if selected_adapter then
            on_select(selected_adapter)
        end
    end)
end

---Change model
---@param available_models table
---@param on_select function
function UI:_change_model(available_models, on_select)
    vim.ui.select(available_models, {
        prompt = "Select model: ",
    }, function(selected_model)
        if selected_model then
            on_select(selected_model)
        end
    end)
end

return UI
