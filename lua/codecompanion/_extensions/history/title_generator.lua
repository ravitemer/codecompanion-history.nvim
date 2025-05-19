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

---Generate title for chat
---@param chat Chat The chat object containing messages and ID
---@param callback fun(title: string|nil) Callback function to receive the generated title
function TitleGenerator:generate(chat, callback)
    if not self.opts.auto_generate_title then
        return
    end
    -- Early returns for existing title or disabled auto-generation
    if chat.opts.title then
        log:trace("Using existing chat title: %s", chat.opts.title)
        return callback(chat.opts.title)
    end
    callback("Deciding title...")

    -- Return early if no messages or messages is nil
    if not chat.messages or #chat.messages == 0 then
        log:trace("No messages found in chat, skipping title generation")
        return callback(nil)
    end

    -- Filter user messages and sort them by index
    local user_messages = vim.tbl_filter(function(msg)
        return msg.role == config.constants.USER_ROLE
    end, chat.messages)
    local non_tag_messages = vim.tbl_filter(function(msg)
        return not (msg.opts and msg.opts.tag) and not (msg.opts and msg.opts.reference)
    end, user_messages)

    local first_user_msg = non_tag_messages[1] or user_messages[1]
    if not first_user_msg then
        log:trace("No user message found in chat, skipping title generation")
        return callback(nil)
    end

    -- Truncate content and add ellipsis if needed
    local content = vim.trim(first_user_msg.content or "")
    if content == "" then
        return callback(nil)
    end
    local truncated_content = content:sub(1, 1000)
    if #content > 1000 then
        truncated_content = truncated_content .. "..."
    end
    log:trace("Generating title for chat with save_id: %s", chat.opts.save_id or "N/A")
    -- Create prompt for title generation
    local prompt = string.format(
        [[Generate a very short and concise title (max 5 words) for this chat based on the following user query:
Do not include any special characters or quotes. Your response shouldn't contain any other text, just the title. 

===
Examples: 
1. User: What is the capital of France?
   Title: Capital of France
2. User: How do I create a new file in Vim?
   Title: Vim File Creation
===

User: %s
Title:]],
        truncated_content
    )
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
