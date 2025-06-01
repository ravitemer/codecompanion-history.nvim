local client = require("codecompanion.http")
local config = require("codecompanion.config")
local log = require("codecompanion._extensions.history.log")
local schema = require("codecompanion.schema")

local CONSTANTS = {
    STATUS_ERROR = "error",
    STATUS_SUCCESS = "success",
}

---@class TitleGenerator
---@field opts HistoryOpts
local TitleGenerator = {}

---@param opts HistoryOpts
---@return TitleGenerator
function TitleGenerator.new(opts)
    local self = setmetatable({}, {
        __index = TitleGenerator,
    })
    self.opts = opts
    return self --[[@as TitleGenerator]]
end

---Count user messages in chat (excluding tagged/reference messages)
---@param chat Chat
---@return number
function TitleGenerator:_count_user_messages(chat)
    if not chat.messages or #chat.messages == 0 then
        return 0
    end

    local user_messages = vim.tbl_filter(function(msg)
        return msg.role == config.constants.USER_ROLE
    end, chat.messages)

    local actual_user_messages = vim.tbl_filter(function(msg)
        local has_content = msg.content and vim.trim(msg.content) ~= ""
        return has_content and not (msg.opts and msg.opts.tag) and not (msg.opts and msg.opts.reference)
    end, user_messages)

    return #actual_user_messages
end

---Check if title should be generated or refreshed
---@param chat Chat
---@return boolean should_generate, boolean is_refresh
function TitleGenerator:should_generate(chat)
    if not self.opts.auto_generate_title then
        return false, false
    end

    if not chat.opts.title then
        return true, false
    end

    local refresh_opts = self.opts.title_generation_opts or {}
    if refresh_opts.refresh_every_n_prompts and refresh_opts.refresh_every_n_prompts > 0 then
        local user_message_count = self:_count_user_messages(chat)
        local refresh_count = chat.opts.title_refresh_count or 0
        local max_refreshes = refresh_opts.max_refreshes or 3

        if
            user_message_count > 0
            and user_message_count % refresh_opts.refresh_every_n_prompts == 0
            and refresh_count < max_refreshes
        then
            return true, true
        end
    end

    return false, false
end

---Generate title for chat
---@param chat Chat The chat object containing messages and ID
---@param callback fun(title: string|nil) Callback function to receive the generated title
---@param is_refresh? boolean Whether this is a title refresh (default: false)
function TitleGenerator:generate(chat, callback, is_refresh)
    if not self.opts.auto_generate_title then
        return
    end

    is_refresh = is_refresh or false

    -- Early return for disabled auto-generation, but allow refresh if explicitly requested
    if not is_refresh and chat.opts.title then
        log:trace("Using existing chat title: %s", chat.opts.title)
        return callback(chat.opts.title)
    end

    -- Return early if no messages or messages is nil
    if not chat.messages or #chat.messages == 0 then
        log:trace("No messages found in chat, skipping title generation")
        return callback(nil)
    end

    -- Filter relevant messages (both user and assistant, excluding tagged/reference messages)
    local relevant_messages = vim.tbl_filter(function(msg)
        -- Include user and assistant messages with actual content
        local has_content = msg.content and vim.trim(msg.content) ~= ""
        local is_relevant_role = msg.role == config.constants.USER_ROLE or msg.role == config.constants.LLM_ROLE
        local not_tagged = not (msg.opts and (msg.opts.tag or msg.opts.reference))
        return has_content and is_relevant_role and not_tagged
    end, chat.messages)

    if #relevant_messages == 0 then
        log:trace("No relevant messages found in chat, skipping title generation")
        return callback(nil)
    end

    -- Show appropriate feedback only after validation
    if is_refresh then
        callback("Refreshing title...")
    else
        callback("Deciding title...")
    end

    -- Extract conversation content based on whether this is a refresh or initial generation
    local conversation_context = ""

    if is_refresh then
        -- For refreshes, use recent conversation (last 6 messages or all if fewer)
        local recent_count = math.min(6, #relevant_messages)
        local start_index = math.max(1, #relevant_messages - recent_count + 1)
        local recent_messages = {}

        for i = start_index, #relevant_messages do
            local msg = relevant_messages[i]
            local role_prefix = msg.role == config.constants.USER_ROLE and "User" or "Assistant"
            local content = vim.trim(msg.content)

            -- Truncate individual message if too long
            if #content > 1000 then
                content = content:sub(1, 1000) .. " [truncated]"
            end

            table.insert(recent_messages, role_prefix .. ": " .. content)
        end

        conversation_context = table.concat(recent_messages, "\n")
    else
        -- For initial generation, use the first user message
        local first_user_msg = nil
        for _, msg in ipairs(relevant_messages) do
            if msg.role == config.constants.USER_ROLE then
                first_user_msg = msg
                break
            end
        end

        if not first_user_msg then
            log:trace("No user message found in chat, skipping title generation")
            return callback(nil)
        end

        local content = vim.trim(first_user_msg.content)

        -- Truncate individual message if too long
        if #content > 1000 then
            content = content:sub(1, 1000) .. " [truncated]"
        end

        conversation_context = "User: " .. content
    end

    -- Truncate total content if too long
    if #conversation_context > 10000 then
        conversation_context = conversation_context:sub(1, 10000) .. "\n[conversation truncated]"
    end

    log:trace(
        "Generating title for chat with save_id: %s (refresh: %s)",
        chat.opts.save_id or "N/A",
        tostring(is_refresh)
    )

    -- Create prompt for title generation
    local prompt
    if is_refresh then
        local original_title = chat.opts.title or "Unknown"
        prompt = string.format(
            [[The conversation has evolved since the original title was generated. Based on the recent conversation below, generate a new concise title (max 5 words) that better reflects the current topic.

Original title: "%s"

Recent conversation:
%s

Generate a new title that captures the main topic of the recent conversation. Do not include any special characters or quotes. Your response should contain only the new title.

New Title:]],
            original_title,
            conversation_context
        )
    else
        prompt = string.format(
            [[Generate a very short and concise title (max 5 words) for this chat based on the following conversation:
Do not include any special characters or quotes. Your response shouldn't contain any other text, just the title.

===
Examples:
1. User: What is the capital of France?
   Title: Capital of France
2. User: How do I create a new file in Vim?
   Title: Vim File Creation
===

Conversation:
%s
Title:]],
            conversation_context
        )
    end

    self:_make_adapter_request(chat, prompt, callback)
end

---@param chat Chat
---@param prompt string
---@param callback fun(title: string|nil)
function TitleGenerator:_make_adapter_request(chat, prompt, callback)
    log:trace("Making adapter request for title generation")
    local opts = self.opts.title_generation_opts or {}
    local adapter = chat.adapter
    local settings = chat.settings
    if opts.adapter then
        adapter = require("codecompanion.adapters").resolve(opts.adapter)
    end
    if opts.model then
        settings = schema.get_default(adapter, { model = opts.model })
    end
    settings = adapter:map_schema_to_params(settings)
    settings.opts.stream = false
    local payload = {
        messages = adapter:map_roles({
            { role = "user", content = prompt },
        }),
    }
    client.new({ adapter = settings }):request(payload, {
        callback = function(err, data, _adapter)
            if err and err.stderr ~= "{}" then
                log:error("Title generation error: %s", err.stderr)
                vim.notify("Error while generating title: " .. err.stderr)
                return callback(nil)
            end
            if data then
                local result = _adapter.handlers.chat_output(_adapter, data)
                if result and result.status then
                    if result.status == CONSTANTS.STATUS_SUCCESS then
                        local title = vim.trim(result.output.content or "")
                        log:trace("Successfully generated title: %s", title)
                        return callback(title)
                    elseif result.status == CONSTANTS.STATUS_ERROR then
                        log:error("Title generation error: %s", result.output)
                        vim.notify("Error while generating title: " .. result.output)
                        return callback(nil)
                    end
                end
            end
        end,
    }, {
        silent = true,
    })
end

-- ---Make request to Groq API
-- ---@private
-- ---@param prompt string The prompt for title generation
-- ---@param callback function Callback to receive the title
-- function TitleGenerator:_make_groq_request(prompt, callback)
-- 	-- Check for API key
-- 	local api_key = os.getenv("GROQ_API_KEY")
-- 	if not api_key then
-- 		vim.notify("GROQ_API_KEY environment variable not set", vim.log.levels.ERROR)
-- 		return callback(nil)
-- 	end
-- 	client.static.opts.post.default({
-- 		url = "https://api.groq.com/openai/v1/chat/completions",
-- 		headers = {
-- 			["Authorization"] = "Bearer " .. os.getenv("GROQ_API_KEY"),
-- 			["Content-Type"] = "application/json",
-- 		},
-- 		body = vim.json.encode({
-- 			messages = {
-- 				{ role = "user", content = prompt },
-- 			},
-- 			model = "llama-3.3-70b-versatile",
-- 		}),
-- 		callback = function(response)
-- 			vim.schedule(function()
-- 				if not response then
-- 					return callback(nil)
-- 				end

-- 				-- Handle HTTP errors
-- 				if response.status < 200 or response.status >= 300 then
-- 					vim.notify("Failed to generate title: " .. response.body, vim.log.levels.ERROR)
-- 					return callback(nil)
-- 				end

-- 				-- Parse response
-- 				local ok, data = pcall(vim.json.decode, response.body)
-- 				if not ok or not data or not data.choices or not data.choices[1] or not data.choices[1].message then
-- 					vim.notify("Failed to generate title: Invalid response", vim.log.levels.ERROR)
-- 					return callback(nil)
-- 				end

-- 				-- Clean up title
-- 				local title = data.choices[1].message.content
-- 				title = title:gsub('"', ""):gsub("^%s*(.-)%s*$", "%1")
-- 				callback(title)
-- 			end)
-- 		end,
-- 		error = function(err)
-- 			vim.schedule(function()
-- 				vim.notify("Failed to generate title: " .. err, vim.log.levels.ERROR)
-- 				callback(nil)
-- 			end)
-- 		end,
-- 	})
-- end

return TitleGenerator
