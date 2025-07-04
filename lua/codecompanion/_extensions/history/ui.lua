local config = require("codecompanion.config")
local log = require("codecompanion._extensions.history.log")
local utils = require("codecompanion._extensions.history.utils")

---@class CodeCompanion.History.UI
---@field storage CodeCompanion.History.Storage
---@field title_generator CodeCompanion.History.TitleGenerator
---@field default_buf_title string
---@field picker CodeCompanion.History.Pickers
---@field picker_keymaps table
local UI = {}

---@param opts CodeCompanion.History.Opts
---@param storage CodeCompanion.History.Storage
---@param title_generator CodeCompanion.History.TitleGenerator
---@return CodeCompanion.History.UI
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
    return self --[[@as CodeCompanion.History.UI]]
end

---Update chat title with optional suffix
---@param chat CodeCompanion.History.Chat
---@param suffix? string Optional suffix to append to title
---@param force? boolean
function UI:update_chat_title(chat, suffix, force)
    log:trace("Updating chat title for: %s", chat.opts.save_id or "N/A")

    local base_title = chat.opts.title or (self.default_buf_title .. tostring(chat.id))

    if suffix then
        local full_title = force and suffix or (base_title .. " " .. suffix)
        self:_set_buf_title(chat.bufnr, full_title)
    else
        self:_set_buf_title(chat.bufnr, base_title)
    end
end

---Check and update summary indicator for existing chat
---@param chat CodeCompanion.History.Chat
function UI:check_and_update_summary_indicator(chat)
    if not chat.opts.save_id then
        return
    end

    local summaries = self.storage:get_summaries()
    if summaries[chat.opts.save_id] then
        self:update_chat_title(chat, "(📝)")
    else
        self:update_chat_title(chat) -- just base title
    end
end

---Method for setting buffer title with retry
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

---Format items for display based on type
---@param items_data table<string,CodeCompanion.History.ChatIndexData> | table<string,CodeCompanion.History.SummaryIndexData> Raw items from storage
---@param item_type "chat" | "summary"
---@param storage CodeCompanion.History.Storage Storage instance for getting summaries
---@return CodeCompanion.History.EntryItem[] Formatted items
local function format_items(items_data, item_type, storage)
    local items = {}

    if item_type == "chat" then
        -- Get summaries to check which chats have summaries
        local summaries = storage:get_summaries()

        for _, chat_item in pairs(items_data) do
            local save_id = chat_item.save_id
            table.insert(
                items,
                vim.tbl_extend("keep", {
                    save_id = save_id,
                    name = chat_item.title or save_id,
                    title = chat_item.title or save_id,
                    updated_at = chat_item.updated_at or 0,
                    has_summary = summaries[save_id] ~= nil, -- Add summary flag
                }, chat_item)
            )
        end
        -- Sort items by updated_at in descending order
        table.sort(items, function(a, b)
            return a.updated_at > b.updated_at
        end)
    elseif item_type == "summary" then
        for _, summary_item in pairs(items_data) do
            table.insert(items, summary_item)
        end
        -- Sort items by generated_at in descending order
        table.sort(items, function(a, b)
            return a.generated_at > b.generated_at
        end)
    end

    return items
end

---Generic method to open items (chats or summaries)
---@param item_type "chat" | "summary"
---@param items_data table<string,CodeCompanion.History.ChatIndexData> | table<string,CodeCompanion.History.SummaryIndexData> Raw items from storage
---@param handlers CodeCompanion.History.UIHandlers Handlers for item actions
---@param current_item_id? string Current item ID for highlighting
function UI:_open_items(item_type, items_data, handlers, current_item_id)
    local item_name = item_type == "chat" and "chats" or "summaries"
    local item_name_title = item_type == "chat" and "Saved Chats" or "Saved Summaries"

    log:trace("Opening %s browser", item_name)

    if vim.tbl_isempty(items_data) then
        log:trace("No %s found", item_name)
        vim.notify("No " .. item_name .. " found", vim.log.levels.INFO)
        return
    end

    -- Format the items for display
    local items = format_items(items_data, item_type, self.storage)
    log:trace("Loaded %d %s", #items, item_name)

    -- Load the configured picker module
    log:trace("Using picker: %s", self.picker)

    local resolved_picker
    local is_picker_available, picker_module =
        pcall(require, "codecompanion._extensions.history.pickers." .. self.picker)
    if not is_picker_available then
        log:warn("Failed to load picker module '%s', falling back to default", self.picker)
        resolved_picker = require("codecompanion._extensions.history.pickers.default")
    else
        resolved_picker = picker_module
    end

    resolved_picker
        :new({
            item_type = item_type,
            items = items,
            handlers = handlers,
            keymaps = self.picker_keymaps,
            current_item_id = current_item_id,
            title = item_name_title,
        })
        :browse()
end

---@param filter_fn? fun(chat_data: CodeCompanion.History.ChatIndexData): boolean Optional filter function
function UI:open_saved_chats(filter_fn)
    local codecompanion = require("codecompanion")
    local last_chat = codecompanion.last_chat() --[[@as CodeCompanion.History.Chat?]]

    self:_open_items("chat", self.storage:get_chats(filter_fn), {
        on_open = function()
            log:trace("Opening saved chats picker")
            self:open_saved_chats(filter_fn)
        end,
        ---@param chat_data CodeCompanion.History.ChatData
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
        ---@param chat_data CodeCompanion.History.ChatData
        on_select = function(chat_data)
            self:_handle_on_select(chat_data.save_id)
        end,
        ---@param chat_data CodeCompanion.History.ChatData|CodeCompanion.History.ChatData[]
        on_delete = function(chat_data)
            -- Handle both single chat and array of chats
            local chats_to_delete = {}
            if type(chat_data) == "table" and chat_data.save_id then
                -- Single chat
                chats_to_delete = { chat_data }
            elseif type(chat_data) == "table" and #chat_data > 0 then
                -- Array of chats
                chats_to_delete = chat_data
            else
                vim.notify("Invalid chat data for deletion", vim.log.levels.ERROR)
                return
            end

            log:trace("Deleting %d chat(s)", #chats_to_delete)

            -- Always ask for confirmation
            local chat_count = #chats_to_delete
            local confirmation_message
            if chat_count == 1 then
                confirmation_message = string.format('Delete chat "%s"?', chats_to_delete[1].title or "Untitled")
            else
                confirmation_message = string.format("Delete %d chats?", chat_count)
            end

            local choice = vim.fn.confirm(confirmation_message, "&Yes\n&No", 2)
            if choice ~= 1 then
                return -- User cancelled
            end

            -- Delete all selected chats
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

            -- Prompt for new title with current title as default
            vim.ui.input({
                prompt = "Rename to: ",
                default = chat_data.title or "",
            }, function(new_title)
                if not new_title or vim.trim(new_title) == "" then
                    return -- User cancelled or entered empty title
                end

                local success = self.storage:rename_chat(chat_data.save_id, new_title)
                if success then
                    -- Update any open chat buffers with this save_id
                    local found_bufnr = nil
                    for _, bufnr in ipairs(_G.codecompanion_buffers or {}) do
                        local chat = codecompanion.buf_get_chat(bufnr) --[[@as CodeCompanion.History.Chat?]]
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

            -- Prompt for new title with current title as default
            vim.ui.input({
                prompt = "Duplicate as: ",
                default = chat_data.title or "",
            }, function(new_title)
                -- If cancelled or empty, append (1) to original title
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

---Handle summary selection from the picker
---@param summary_data CodeCompanion.History.SummaryIndexData
function UI:_handle_summary_select(summary_data)
    local codecompanion = require("codecompanion")
    local active_chat = codecompanion.last_chat()
    local current_chat = active_chat or codecompanion.chat()
    local save_id = summary_data.summary_id
    local chat_title = summary_data.chat_title or "Untitled"
    if current_chat then
        local summary_content = self.storage:load_summary(save_id)
        if not summary_content then
            return vim.notify("Summary not found: " .. save_id, vim.log.levels.ERROR)
        end
        local ref_id = "<summary>" .. chat_title .. "</summary>"
        local content = string.format(
            [[<summary>
Chat Title: %s
Summary:

%s
</summary>]],
            chat_title,
            summary_content
        )
        current_chat:add_message({
            role = config.constants.USER_ROLE,
            content = content,
        }, {
            reference = ref_id,
            visible = false,
        })
        current_chat.references:add({
            id = ref_id,
        })
        vim.notify("Summary added to chat")
    else
        vim.notify("No active chat to attach summary to", vim.log.levels.ERROR)
    end
end

---@param save_id string
function UI:_handle_on_select(save_id)
    local codecompanion = require("codecompanion")
    log:trace("Selected chat: %s", save_id)
    local chat_module = require("codecompanion.strategies.chat")
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

    -- Load full chat data when selecting
    local full_chat = self.storage:load_chat(save_id)
    if full_chat then
        self:create_chat(full_chat)
    else
        log:error("Failed to load chat: %s", save_id)
        vim.notify("Failed to load chat", vim.log.levels.ERROR)
    end
end

function UI:open_summaries()
    self:_open_items("summary", self.storage:get_summaries(), {
        on_open = function()
            log:trace("Opening summaries picker")
            self:open_summaries()
        end,
        ---@param summary_data CodeCompanion.History.SummaryIndexData
        ---@return string[] lines
        on_preview = function(summary_data)
            -- Load full summary content for preview
            local summary_content = self.storage:load_summary(summary_data.summary_id)
            if summary_content then
                return vim.split(summary_content, "\n", { plain = true })
            else
                log:warn("Failed to load summary for preview: %s", summary_data.summary_id)
                return { "Summary content not available" }
            end
        end,
        ---@param summary_data CodeCompanion.History.SummaryIndexData|CodeCompanion.History.SummaryIndexData[]
        on_delete = function(summary_data)
            -- Handle both single summary and array of summaries
            local summaries_to_delete = {}
            if type(summary_data) == "table" and summary_data.summary_id then
                -- Single summary
                summaries_to_delete = { summary_data }
            elseif type(summary_data) == "table" and #summary_data > 0 then
                -- Array of summaries
                summaries_to_delete = summary_data
            else
                vim.notify("Invalid summary data for deletion", vim.log.levels.ERROR)
                return
            end

            log:trace("Deleting %d summary(s)", #summaries_to_delete)

            -- Always ask for confirmation
            local summary_count = #summaries_to_delete
            local confirmation_message
            if summary_count == 1 then
                confirmation_message =
                    string.format('Delete summary for "%s"?', summaries_to_delete[1].chat_title or "Untitled")
            else
                confirmation_message = string.format("Delete %d summaries?", summary_count)
            end

            local choice = vim.fn.confirm(confirmation_message, "&Yes\n&No", 2)
            if choice ~= 1 then
                return -- User cancelled
            end

            -- Delete all selected summaries
            local deleted_count = 0
            for _, summary in ipairs(summaries_to_delete) do
                if self.storage:delete_summary(summary.summary_id) then
                    deleted_count = deleted_count + 1
                end
            end

            if deleted_count > 0 then
                local message = deleted_count == 1 and "Summary deleted successfully"
                    or string.format("%d summaries deleted successfully", deleted_count)
                vim.notify(message, vim.log.levels.INFO)
                self:open_summaries()
            else
                vim.notify("Failed to delete summaries", vim.log.levels.ERROR)
            end
        end,
        ---@param summary_data CodeCompanion.History.SummaryIndexData
        on_rename = function(summary_data)
            -- Renaming summaries is not supported
            vim.notify("Renaming summaries is not supported", vim.log.levels.INFO)
        end,
        ---@param summary_data CodeCompanion.History.SummaryIndexData
        on_duplicate = function(summary_data)
            -- Duplicating summaries is not supported
            vim.notify("Duplicating summaries is not supported", vim.log.levels.INFO)
        end,
        ---@param summary_data CodeCompanion.History.SummaryIndexData
        on_select = function(summary_data)
            log:trace("Selected summary: %s", summary_data.summary_id)
            self:_handle_summary_select(summary_data)
        end,
    })
end

---Creates a new chat from the given chat data restoring what it can along with the adapter, settings. If adapter is not found, ask user to select another adapter. If adapter is found but model is not available, uses the adapter's default model.
---@param chat_data? CodeCompanion.History.ChatData
---@return CodeCompanion.History.Chat?
function UI:create_chat(chat_data)
    log:trace("Creating new chat from saved data")
    chat_data = chat_data or {}
    local messages = chat_data.messages or {}
    local save_id = chat_data.save_id
    local title = chat_data.title

    messages = messages or {}
    local last_msg = messages[#messages]

    --HACK: Ensure last message is from user to show header
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
    ---@param adapter string
    ---@param settings table?
    local function _create_chat(adapter, settings)
        local chat = require("codecompanion.strategies.chat").new({
            save_id = save_id,
            messages = messages,
            context = context,
            settings = settings,
            adapter = adapter --[[@as CodeCompanion.Adapter]],
            title = title,
            --INFO: No need to ignore system prompt here, thanks to oli we don't add system messages with same tag (`from_config`) twice.
            -- This also fixes `gx` removing the system prompt from the chat if we pass `ignore_system_prompt = true`
            -- ignore_system_prompt = true,
        }) --[[@as CodeCompanion.History.Chat]]
        for _, ref in ipairs(chat_data.refs or {}) do
            chat.references:add(ref)
        end
        chat.tools.schemas = chat_data.schemas or {}
        chat.tools.in_use = chat_data.in_use or {}
        chat.cycle = chat_data.cycle or 1
        chat.opts.title_refresh_count = chat_data.title_refresh_count or 0
        log:trace("Successfully created chat with save_id: %s", save_id or "N/A")
        return chat
    end
    local adapter = chat_data.adapter
    local settings = chat_data.settings or {}
    if adapter then
        local found, resolved_adapter = pcall(require("codecompanion.adapters").resolve, adapter)
        -- If the adapter is not found, we need to change it. If found, we need to check if the model is available
        if not found then
            vim.notify(
                string.format("Adapter '%s' not available, please select another adapter", adapter),
                vim.log.levels.WARN
            )
            return self:_change_adapter(_create_chat)
        else
            local saved_model = settings.model
            if saved_model then
                local available_models = resolved_adapter.schema.model.choices
                --INFO:Skipping if models is a function
                -- if type(available_models) == "function" then
                --     vim.notify("Please wait while we fetch the avaiable models in " .. adapter)
                --     available_models = available_models(resolved_adapter)
                -- end
                if type(available_models) == "table" then
                    available_models = vim.iter(available_models)
                        :map(function(model, value)
                            if type(model) == "string" then
                                return model
                            else
                                return value -- This is for the table entry case
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
                        --INFO: this results in rare errors where the model opts differ from one model to another model.
                        -- return self:_change_model(available_models, function(model)
                        --     settings.model = model
                        --     create_chat(adapter, nil)
                        -- end)
                    end
                end
            end
        end
    end
    return _create_chat(adapter, settings)
end

---[[Most of the code is copied from codecompanion/strategies/chat/ui.lua]]
---Retrieve the lines to be displayed in the preview window
---@param chat_data CodeCompanion.History.ChatData
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

---@param chat CodeCompanion.History.Chat
---@param saved_at number
function UI:update_last_saved(chat, saved_at)
    log:trace("Updating last saved time for chat: %s", chat.opts.save_id or "N/A")
    --saved at icon
    local icon = " "
    self:update_chat_title(chat, icon .. utils.format_time(saved_at))
end

local function select_opts(prompt, conditional)
    return {
        prompt = prompt,
        kind = "codecompanion.nvim",
        format_item = function(item)
            if conditional == item then
                return "* " .. item
            end
            return "  " .. item
        end,
    }
end

---@param on_select fun(adapter: string, settings: table?):nil
function UI:_change_adapter(on_select)
    local adapters = vim.deepcopy(config.adapters)

    local adapters_list = vim.iter(adapters)
        :filter(function(adapter)
            return adapter ~= "opts" and adapter ~= "non_llms"
        end)
        :map(function(adapter, _)
            return adapter
        end)
        :totable()
    table.sort(adapters_list)
    -- table.insert(adapters_list, 1, current_adapter)
    vim.ui.select(adapters_list, select_opts("Select Adapter"), function(selected)
        if not selected then
            return
        end
        local found, adapter = pcall(require("codecompanion.adapters").resolve, selected)
        if found and adapter then
            --set chat settings to nil, so that old adapter's settings are not used
            on_select(selected, nil)
        end
    end)
end

---@param available_models string[]
---@param on_select fun(model: string):nil
function UI:_change_model(available_models, on_select)
    local models = vim.deepcopy(available_models)
    table.sort(models)
    vim.ui.select(models, select_opts("Select Model"), function(selected)
        if not selected then
            return
        end
        on_select(selected)
    end)
end

return UI
