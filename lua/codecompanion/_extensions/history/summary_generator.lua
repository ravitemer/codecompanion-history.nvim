local client = require("codecompanion.http")
local log = require("codecompanion._extensions.history.log")
local schema = require("codecompanion.schema")

local CONSTANTS = {
    STATUS_ERROR = "error",
    STATUS_SUCCESS = "success",
    DEFAULT_CONTEXT_SIZE = 90000, -- tokens
    MIN_MESSAGES_FOR_SUMMARY = 3,
}

---@class CodeCompanion.History.SummaryGenerator
---@field opts CodeCompanion.History.Opts
---@field generation_opts CodeCompanion.History.SummaryGenerationOpts
local SummaryGenerator = {}

---@param opts CodeCompanion.History.Opts
---@return CodeCompanion.History.SummaryGenerator
function SummaryGenerator.new(opts)
    local self = setmetatable({}, {
        __index = SummaryGenerator,
    })
    self.opts = opts
    self.generation_opts = vim.tbl_deep_extend("force", {
        context_size = CONSTANTS.DEFAULT_CONTEXT_SIZE,
        include_references = true,
        include_tool_outputs = true,
    }, (opts.summary and opts.summary.generation_opts) or {})

    return self --[[@as CodeCompanion.History.SummaryGenerator]]
end

---Generate summary for chat
---@param chat CodeCompanion.History.Chat The chat object containing messages and ID
---@param callback fun(summary: CodeCompanion.History.SummaryData|nil, error: string|nil) Callback function to receive the generated summary
function SummaryGenerator:generate(chat, callback)
    -- Validate chat has enough content
    if not chat.messages or #chat.messages < CONSTANTS.MIN_MESSAGES_FOR_SUMMARY then
        return callback(
            nil,
            "Not enough content for summary (minimum " .. CONSTANTS.MIN_MESSAGES_FOR_SUMMARY .. " messages)"
        )
    end

    log:trace("Starting summary generation for chat: %s", chat.opts.save_id or "N/A")

    -- Extract and prepare conversation content inline
    local formatted_messages = {}
    local project_root = self:_detect_project_root(chat)

    -- Filter and process messages
    for _, msg in ipairs(chat.messages) do
        local formatted = self:_format_message_for_summary(msg)
        if formatted then
            table.insert(formatted_messages, formatted)
        end
    end

    if #formatted_messages == 0 then
        return callback(nil, "No meaningful content found for summarization")
    end

    -- Start recursive summarization process
    self:_make_summary_request(chat, formatted_messages, nil, function(final_summary, error)
        if error then
            return callback(nil, error)
        end

        if not final_summary or final_summary == "" then
            return callback(nil, "Empty summary generated")
        end

        if type(self.generation_opts.format_summary) == "function" then
            final_summary = self.generation_opts.format_summary(final_summary)
            if not final_summary or final_summary == "" then
                return callback(nil, "Formatted summary is empty")
            end
        end
        -- Create complete summary object
        local summary = self:_create_summary_object(chat, project_root, final_summary)
        callback(summary, nil)
    end)
end

---Format a single message for inclusion in summary context
---@param msg table The message object
---@return string|nil Formatted message or nil if should be excluded
function SummaryGenerator:_format_message_for_summary(msg)
    -- Skip system messages from config
    if msg.role == "system" and msg.opts and msg.opts.tag == "from_config" then
        return nil
    end

    -- Skip tool system prompts
    if msg.role == "system" and msg.opts and msg.opts.tag == "tool" then
        return nil
    end

    -- Handle user messages
    if msg.role == "user" then
        -- Include regular user messages
        if msg.opts and msg.opts.visible == true then
            return "User: " .. (msg.content or "")
        end

        -- Include references if enabled
        if self.generation_opts.include_references and msg.opts and msg.opts.reference then
            return "Context: " .. (msg.opts.reference or "") .. "\n" .. (msg.content or "")
        end

        return nil
    end

    -- Handle LLM responses
    if msg.role == "llm" or msg.role == "assistant" then
        if msg.opts and msg.opts.visible == true then
            -- Handle tool calls
            if msg.tool_calls then
                local tool_names = {}
                for _, tool_call in ipairs(msg.tool_calls) do
                    if tool_call["function"] and tool_call["function"].name then
                        table.insert(tool_names, tool_call["function"].name)
                    end
                end
                local tools_text = #tool_names > 0 and (" [Called tools: " .. table.concat(tool_names, ", ") .. "]")
                    or ""
                return "Assistant: " .. (msg.content or "") .. tools_text
            else
                return "Assistant: " .. (msg.content or "")
            end
        end
        return nil
    end

    -- Handle tool outputs
    if msg.role == "tool" and msg.opts and msg.opts.tag == "tool_output" then
        if self.generation_opts.include_tool_outputs then
            -- Truncate very long tool outputs
            local content = msg.content or ""
            if #content > 500 then
                content = content:sub(1, 500) .. "... [truncated]"
            end
            return "Tool Result: " .. content
        end
        return nil
    end

    return nil
end

---Recursive method to handle summarization with context limits
---@param chat CodeCompanion.History.Chat The chat object containing messages and ID
---@param remaining_messages string[] Messages still to be processed
---@param previous_summary string|nil Summary from previous chunks
---@param callback fun(summary: string|nil, error: string|nil)
function SummaryGenerator:_make_summary_request(chat, remaining_messages, previous_summary, callback)
    if #remaining_messages == 0 then
        return callback(previous_summary, nil)
    end

    -- Calculate how many messages we can include in this request
    local messages_for_this_request = {}
    local current_tokens = 0
    local max_tokens = math.floor(self.generation_opts.context_size * 0.7) -- Leave room for system prompt

    -- Add messages until we hit token limit
    for i, message in ipairs(remaining_messages) do
        local message_tokens = self:_estimate_tokens(message)
        if current_tokens + message_tokens > max_tokens and #messages_for_this_request > 0 then
            -- We've hit the limit, stop here
            break
        end
        table.insert(messages_for_this_request, message)
        current_tokens = current_tokens + message_tokens
    end

    -- If we couldn't fit even one message, there's a problem
    if #messages_for_this_request == 0 then
        return callback(nil, "Message too large to fit in context window")
    end

    -- Prepare the prompt
    local system_prompt = self:_get_system_prompt()
    local user_prompt = self:_create_user_prompt(messages_for_this_request, chat, previous_summary)

    -- Make the request
    self:_make_adapter_request(chat, system_prompt, user_prompt, function(chunk_summary, error)
        if error then
            return callback(nil, error)
        end

        -- Calculate remaining messages for next iteration
        local messages_processed = #messages_for_this_request
        local remaining = {}
        for i = messages_processed + 1, #remaining_messages do
            table.insert(remaining, remaining_messages[i])
        end

        -- Continue with remaining messages
        self:_make_summary_request(chat, remaining, chunk_summary, callback)
    end)
end

---Create the system prompt for summarization
---@return string
function SummaryGenerator:_get_system_prompt()
    local system_prompt = self.generation_opts.system_prompt

    if type(system_prompt) == "function" then
        return system_prompt()
    elseif type(system_prompt) == "string" then
        return system_prompt
    else
        return [[You are an expert coding assistant and conversation summarizer. Your goal is to create comprehensive, structured summaries of technical conversations that will be used for future reference and semantic search.

Your summaries should:
1. Capture key technical concepts, decisions, and solutions
2. Include specific library names, function names, and technical terms
3. Focus on reusable knowledge and patterns
4. Maintain consistent structure for searchability
5. Be concise but informative

SUMMARY FORMAT:
For new conversations, generate a structured summary in this EXACT format:

# [Descriptive Title]

## Overview
[2-3 sentence high-level description of what was accomplished or discussed]

## Key Achievements
- [Specific accomplishments, features implemented, bugs fixed]
- [Focus on actionable outcomes]

## Technical Patterns
- [Code patterns, architectural decisions, methodologies used]
- [Libraries, frameworks, tools effectively utilized]

## Important Decisions
- [Key technical decisions made and why]
- [Trade-offs considered]
- [Alternative approaches discussed]

## Code Context
**Files Modified**: [list of files worked on]
**Dependencies**: [new packages/libraries added]
**Commands Used**: [important terminal commands or scripts]

GUIDELINES:
- Focus on technical knowledge useful for future similar conversations
- Include specific names of libraries, functions, and technical terms
- Capture the "why" behind decisions, not just the "what"
- Keep sections concise but informative
- Use bullet points for readability

For conversations that are continuations of previous summaries, update and extend the previous summary while maintaining the same structure and incorporating new information, decisions, and technical details.]]
    end
end

---Create the user prompt for summarization
---@param messages string[] Messages to summarize
---@param chat CodeCompanion.History.Chat The chat object containing messages and ID
---@param previous_summary string|nil For chunked summarization
---@return string
function SummaryGenerator:_create_user_prompt(messages, chat, previous_summary)
    local prompt_parts = {}

    -- Add previous summary if this is chunked summarization
    if previous_summary then
        table.insert(prompt_parts, "PREVIOUS SUMMARY:")
        table.insert(prompt_parts, previous_summary)
        table.insert(prompt_parts, "")
        table.insert(prompt_parts, "ADDITIONAL CONVERSATION:")
    else
        table.insert(prompt_parts, "CONVERSATION:")
    end

    -- Add the messages
    table.insert(prompt_parts, table.concat(messages, "\n\n"))

    -- Add simple instruction
    if previous_summary then
        table.insert(prompt_parts, "")
        table.insert(
            prompt_parts,
            "Please update and extend the previous summary with the additional conversation content above."
        )
    else
        table.insert(prompt_parts, "")
        table.insert(prompt_parts, "Please generate a structured summary of this technical conversation.")
    end

    return table.concat(prompt_parts, "\n")
end

---Make adapter request for summary generation
---@param chat CodeCompanion.History.Chat
---@param system_prompt string
---@param user_prompt string
---@param callback fun(content: string|nil, error: string|nil)
function SummaryGenerator:_make_adapter_request(chat, system_prompt, user_prompt, callback)
    log:trace("Making adapter request for summary generation")

    local opts = self.generation_opts
    local adapter = vim.deepcopy(chat.adapter) --[[@as CodeCompanion.Adapter]]
    local settings = vim.deepcopy(chat.settings)

    -- Use custom adapter/model if specified
    if opts.adapter then
        adapter = require("codecompanion.adapters").resolve(opts.adapter)
    end
    if opts.model then
        settings = schema.get_default(adapter, { model = opts.model })
    end

    settings = vim.deepcopy(adapter:map_schema_to_params(settings))
    settings.opts.stream = false

    local payload = {
        messages = adapter:map_roles({
            { role = "system", content = system_prompt },
            { role = "user", content = user_prompt },
        }),
    }

    client.new({ adapter = settings }):request(payload, {
        callback = function(err, data, _adapter)
            if err and err.stderr ~= "{}" then
                log:error("Summary generation error: %s", err.stderr)
                return callback(nil, "Error while generating summary: " .. err.stderr)
            end

            if data then
                local result = _adapter.handlers.chat_output(_adapter, data)
                if result and result.status then
                    if result.status == CONSTANTS.STATUS_SUCCESS then
                        local content = vim.trim(result.output.content or "")
                        log:trace("Successfully generated summary")
                        return callback(content, nil)
                    elseif result.status == CONSTANTS.STATUS_ERROR then
                        log:error("Summary generation error: %s", result.output)
                        return callback(nil, "Error while generating summary: " .. result.output)
                    end
                end
            end

            callback(nil, "Unknown error during summary generation")
        end,
    }, {
        silent = true,
    })
end

---Create complete summary object with metadata
---@param chat CodeCompanion.History.Chat
---@param project_root string
---@param summary_content string
---@return CodeCompanion.History.SummaryData
function SummaryGenerator:_create_summary_object(chat, project_root, summary_content)
    return {
        summary_id = chat.opts.save_id,
        chat_id = chat.opts.save_id,
        chat_title = chat.opts.title, -- Add chat title
        generated_at = os.time(),
        content = summary_content,
        -- Basic metadata
        project_root = project_root,
    } --[[@as CodeCompanion.History.SummaryData]]
end

-- Helper methods
function SummaryGenerator:_detect_project_root(chat)
    return vim.fs.root(0, { ".git", "package.json", "Cargo.toml", "go.mod" }) or vim.fn.getcwd()
end

function SummaryGenerator:_estimate_tokens(text)
    -- Simple estimation: ~4 characters per token
    return math.ceil(#text / 4)
end

return SummaryGenerator
