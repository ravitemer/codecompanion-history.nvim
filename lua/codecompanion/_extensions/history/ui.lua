local config = require("codecompanion.config")
local log = require("codecompanion._extensions.history.log")
local utils = require("codecompanion._extensions.history.utils")

---@class UI
---@field storage Storage
---@field title_generator TitleGenerator
---@field default_buf_title string
---@field picker Pickers
---@field picker_keymaps table
local UI = {}

---@param opts HistoryOpts
---@param storage Storage
---@param title_generator TitleGenerator
---@return UI
function UI.new(opts, storage, title_generator)
    local self = setmetatable({}, {
        __index = UI,
    })

    self.storage = storage
    self.title_generator = title_generator
    self.default_buf_title = opts.default_buf_title
    self.picker = opts.picker
    self.picker_keymaps = opts.picker_keymaps

    log:trace("Initialized UI with picker: %s", opts.picker)
    return self --[[@as UI]]
end

-- Private method for setting buffer title with retry
---@param bufnr number
---@param title string|string[]
---@param attempt? number
function UI:_set_buf_title(bufnr, title, attempt)
    attempt = attempt or 0
    log:trace("Setting buffer title (attempt %d) for buffer %d", attempt, bufnr)

    vim.schedule(function()
        ---Takes a array of strings and justifies them to fit the available width
        ---@param str_array string[]
        ---@return string
        local function justify_strings(str_array)
            -- Validate input
            if #str_array == 0 then
                return ""
            end
            if #str_array == 1 then
                return str_array[1]
            end

            -- Get the window ID for this buffer
            local win_id = vim.fn.bufwinid(bufnr)
            if win_id == -1 then
                log:trace("No window found for buffer %d, falling back to simple concat", bufnr)
                return table.concat(str_array, " ")
            end

            -- Get available width (subtract 10 for the sparkle and some padding, any file icons in winbar)
            local width = vim.api.nvim_win_get_width(win_id) - 10

            -- Calculate total string length
            local total_len = 0
            for _, str in ipairs(str_array) do
                if type(str) ~= "string" then
                    log:warn("Non-string value in title array, falling back to simple concat")
                    return table.concat(str_array, " ")
                end
                total_len = total_len + vim.api.nvim_strwidth(str)
            end

            -- Calculate remaining space and gaps
            local remaining_space = math.max(0, width - total_len)
            local num_gaps = #str_array - 1
            if num_gaps <= 0 or remaining_space <= 0 then
                return table.concat(str_array, " ")
            end

            -- Calculate even gap size and extra spaces to distribute
            local gap_size = math.floor(remaining_space / num_gaps)
            local extra_spaces = remaining_space % num_gaps

            -- Construct the justified string
            local result = {}
            for i, str in ipairs(str_array) do
                table.insert(result, str)
                if i < #str_array then
                    -- Add gap and distribute extra spaces
                    table.insert(result, string.rep(" ", gap_size + (i <= extra_spaces and 1 or 0)))
                end
            end

            -- Combine and truncate if necessary
            local final_result = table.concat(result)
            if vim.api.nvim_strwidth(final_result) > width then
                final_result = vim.fn.strcharpart(final_result, 0, width - 1) .. "…"
            end

            return final_result
        end

        -- Process title based on type
        local final_title
        if type(title) == "table" then
            final_title = justify_strings(title)
        else
            final_title = tostring(title)
        end

        local icon = "✨ "
        -- throws error if buffer with same name already exists so we add a counter to the title
        local success, err = pcall(function()
            local _title = final_title .. (attempt > 0 and " (" .. tostring(attempt) .. ")" or "")
            vim.api.nvim_buf_set_name(bufnr, icon .. _title)
            utils.fire("TitleSet", {
                bufnr = bufnr,
                title = _title,
            })
        end)

        if not success then
            if attempt > 10 then
                log:trace("Failed to set buffer title after 10 attempts: %s", err)
                vim.notify("Failed to set buffer title: " .. err, vim.log.levels.ERROR)
                return
            end
            log:trace("Title collision, retrying with attempt %d", attempt + 1)
            self:_set_buf_title(bufnr, final_title, attempt + 1)
        else
            log:trace("Successfully set buffer title for buffer %d, %s", bufnr, final_title)
        end
    end)
end

---Format chat data for display
---@param chats table<string, ChatIndexData>
---@return ChatData[]
local function format_chat_items(chats)
    local items = {}
    for _, chat_item in pairs(chats) do
        local save_id = chat_item.save_id
        table.insert(
            items,
            vim.tbl_extend("keep", {
                save_id = save_id,
                name = chat_item.title or save_id,
                title = chat_item.title or save_id,
                updated_at = chat_item.updated_at or 0,
            }, chat_item)
        )
    end
    -- Sort items by updated_at in descending order
    table.sort(items, function(a, b)
        return a.updated_at > b.updated_at
    end)
    return items
end

function UI:open_saved_chats()
    log:trace("Opening saved chats browser")
    local index = self.storage:get_chats()
    if vim.tbl_isempty(index) then
        log:trace("No saved chats found")
        vim.notify("No chat history found", vim.log.levels.INFO)
        return
    end

    -- Format the index for display
    local items = format_chat_items(index)
    log:trace("Loaded %d saved chats", #items)

    -- Get picker
    local is_picker_available, resolved_picker =
        pcall(require, "codecompanion._extensions.history.pickers." .. self.picker)
    if not is_picker_available then
        log:trace("Requested picker '%s' not available, falling back to default", self.picker)
        resolved_picker = require("codecompanion._extensions.history.pickers.default")
    elseif self.picker ~= "default" then
        local available, _ = pcall(require, self.picker)
        if not available then
            vim.notify(
                string.format("'%s' module not available. Using default picker", self.picker),
                vim.log.levels.WARN
            )
            resolved_picker = require("codecompanion._extensions.history.pickers.default")
        end
    end
    ---@diagnostic disable-next-line: different-requires
    local codecompanion = require("codecompanion")
    local last_chat = codecompanion.last_chat()

    resolved_picker
        :new(items, {
            on_open = function()
                log:trace("Opening saved chats picker")
                self:open_saved_chats()
            end,
            ---@param chat_data ChatData
            ---@return string[] lines
            on_preview = function(chat_data)
                -- Load full chat data for preview
                local full_chat = self.storage:load_chat(chat_data.save_id)
                if full_chat then
                    return self:_get_preview_lines(full_chat)
                else
                    log:warn("Failed to load chat data for preview: %s", chat_data.save_id)
                    return { "Chat data not available" }
                end
            end,
            ---@param chat_data ChatData
            on_delete = function(chat_data)
                log:trace("Deleting chat: %s", chat_data.save_id)
                self.storage:delete_chat(chat_data.save_id)
            end,
            ---@param chat_data ChatData
            ---@param new_title string
            on_rename = function(chat_data, new_title)
                log:trace("Renaming chat: %s -> %s", chat_data.save_id, new_title)
                self.storage:rename_chat(chat_data.save_id, new_title)
                local found_bufnr = nil
                for _, bufnr in ipairs(_G.codecompanion_buffers or {}) do
                    local chat = codecompanion.buf_get_chat(bufnr)
                    if chat and chat.opts.save_id == chat_data.save_id then
                        found_bufnr = bufnr
                        chat.opts.title = new_title
                        self:_set_buf_title(bufnr, new_title)
                        break
                    end
                end
                utils.fire("TitleRenamed", {
                    bufnr = found_bufnr,
                    title = new_title,
                })
            end,
            ---@param chat_data ChatData
            on_select = function(chat_data)
                log:trace("Selected chat: %s", chat_data.save_id)
                local chat_module = require("codecompanion.strategies.chat")
                local opened_chats = chat_module.buf_get_chat()
                local active_chat = codecompanion.last_chat()

                for _, data in ipairs(opened_chats) do
                    if data.chat.opts.save_id == chat_data.save_id then
                        if (active_chat and not active_chat.ui:is_active()) or active_chat ~= data.chat then
                            if active_chat and active_chat.ui:is_active() then
                                active_chat.ui:hide()
                            end
                            data.chat.ui:open()
                        else
                            log:trace("Chat already open: %s", chat_data.save_id)
                            vim.notify("Chat already open", vim.log.levels.INFO)
                        end
                        return
                    end
                end

                -- Load full chat data when selecting
                local full_chat = self.storage:load_chat(chat_data.save_id)
                if full_chat then
                    self:create_chat(full_chat)
                else
                    log:error("Failed to load chat: %s", chat_data.save_id)
                    vim.notify("Failed to load chat", vim.log.levels.ERROR)
                end
            end,
        }, self.picker_keymaps)
        :browse(last_chat and last_chat.opts.save_id)
end

---Creates a new chat from the given chat data restoring what it can
---@param chat_data? ChatData
---@return Chat
function UI:create_chat(chat_data)
    log:trace("Creating new chat from saved data")
    chat_data = chat_data or {}
    local messages = chat_data.messages or {}
    local save_id = chat_data.save_id
    local title = chat_data.title

    messages = messages or {}

    --HACK: Ensure last message is from user to show header
    if #messages > 0 and messages[#messages].role ~= "user" then
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
    local chat = require("codecompanion.strategies.chat").new({
        save_id = save_id,
        messages = messages,
        context = context,
        settings = chat_data.settings,
        adapter = chat_data.adapter,
        title = title,
        --INFO: No need to ignore system prompt here, thanks to oli we don't add system messages with same tag (`from_config`) twice.
        -- This also fixes `gx` removing the system prompt from the chat if we pass `ignore_system_prompt = true`
        -- ignore_system_prompt = true,
    })
    chat.refs = chat_data.refs or {}
    chat.references:render()
    chat.tools.schemas = chat_data.schemas or {}
    chat.tools.in_use = chat_data.in_use or {}
    chat.cycle = chat_data.cycle or 1
    log:trace("Successfully created chat with save_id: %s", save_id or "N/A")
    return chat
end

---[[Most of the code is copied from codecompanion/strategies/chat/ui.lua]]
---Retrieve the lines to be displayed in the preview window
---@param chat_data ChatData
function UI:_get_preview_lines(chat_data)
    local lines = {}
    local function spacer()
        table.insert(lines, "")
    end
    local function set_header(tbl, role)
        local header = "## " .. role
        table.insert(tbl, header)
        table.insert(tbl, "")
    end
    local system_role = config.constants.SYSTEM_ROLE
    local user_role = config.constants.USER_ROLE
    local assistant_role = config.constants.LLM_ROLE
    local last_role
    local last_set_role
    local function render_references(refs)
        if vim.tbl_isempty(refs) then
            return
        end
        table.insert(lines, "> Context:")
        local icons_path = config.display.chat.icons
        local icons = {
            pinned = icons_path.pinned_buffer,
            watched = icons_path.watched_buffer,
        }
        for _, ref in pairs(refs) do
            if not ref or (ref.opts and ref.opts.visible == false) then
                goto continue
            end
            if ref.opts and ref.opts.pinned then
                table.insert(lines, string.format("> - %s%s", icons.pinned, ref.id))
            elseif ref.opts and ref.opts.watched then
                table.insert(lines, string.format("> - %s%s", icons.watched, ref.id))
            else
                table.insert(lines, string.format("> - %s", ref.id))
            end
            ::continue::
        end
        if #lines == 1 then
            -- no ref added
            return
        end
        table.insert(lines, "")
    end
    local function add_messages_to_buf(msgs)
        for i, msg in ipairs(msgs) do
            if (msg.role ~= system_role) and not (msg.opts and msg.opts.visible == false) then
                -- For workflow prompts: Ensure main user role doesn't get spaced
                if i > 1 and last_role ~= msg.role and msg.role ~= user_role then
                    spacer()
                end

                if msg.role == user_role and last_set_role ~= user_role then
                    if last_set_role ~= nil then
                        spacer()
                    end
                    set_header(lines, "  User")
                end
                if msg.role == assistant_role and last_set_role ~= assistant_role then
                    set_header(lines, "  Assistant")
                end

                if msg.opts and msg.opts.tag == "tool_output" then
                    table.insert(lines, "### Tool Output")
                    table.insert(lines, "")
                end

                local trimempty = not (msg.role == "user" and msg.content == "")
                for _, text in ipairs(vim.split(msg.content or "", "\n", { plain = true, trimempty = trimempty })) do
                    table.insert(lines, text)
                end

                last_set_role = msg.role
                last_role = msg.role

                -- The Chat:Submit method will parse the last message and it to the messages table
                if i == #msgs then
                    table.remove(msgs, i)
                end
            end
        end
    end

    if chat_data.settings then
        lines = { "---" }
        table.insert(lines, string.format("adapter: %s", vim.inspect(chat_data.adapter)))
        table.insert(lines, string.format("model: %s", vim.inspect(chat_data.settings.model)))
        -- Sort keys alphabetically
        local sorted_keys = {}
        for key in pairs(chat_data.settings) do
            table.insert(sorted_keys, key)
        end
        table.sort(sorted_keys)
        for _, key in ipairs(sorted_keys) do
            if key ~= "model" then
                table.insert(lines, string.format("%s: %s", key, vim.inspect(chat_data.settings[key])))
            end
        end
        table.insert(lines, "---")
        spacer()
    end
    render_references(chat_data.refs)
    if vim.tbl_isempty(chat_data.messages) then
        set_header(lines, user_role)
        spacer()
    else
        add_messages_to_buf(chat_data.messages)
    end
    return lines
end

---@param chat Chat
---@param saved_at number
function UI:update_last_saved(chat, saved_at)
    log:trace("Updating last saved time for chat: %s", chat.opts.save_id or "N/A")
    --saved at icon
    local icon = " "
    self:_set_buf_title(chat.bufnr, { chat.opts.title or self.default_buf_title, icon .. utils.format_time(saved_at) })
end

return UI
