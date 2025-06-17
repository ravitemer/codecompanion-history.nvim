---@class Storage
---@field base_path string Base directory path
---@field index_path string Path to index file
---@field chats_dir string Path to chats directory
---@field expiration_days number Number of days after which chats are deleted
local Storage = {}

-- File I/O utility functions
local FileUtils = {}
local log = require("codecompanion._extensions.history.log")
local utils = require("codecompanion._extensions.history.utils")

---Read and decode a JSON file
---@param file_path string Path to the file
---@return {ok: boolean, data: table|nil, error: string|nil} Result
function FileUtils.read_json(file_path)
    local Path = require("plenary.path")
    local path = Path:new(file_path)

    if not path:exists() then
        log:trace("File does not exist: %s", file_path)
        return { ok = false, data = nil, error = "File does not exist: " .. file_path }
    end

    local content, read_error = path:read()
    if not content then
        log:error("Failed to read file: %s - %s", file_path, read_error or "unknown error")
        return { ok = false, data = nil, error = "Failed to read file: " .. (read_error or "unknown error") }
    end

    local success, data = pcall(vim.json.decode, content)
    if not success then
        log:error("Failed to parse JSON from file: %s - %s", file_path, data)
        return { ok = false, data = nil, error = "Failed to parse JSON: " .. tostring(data) }
    end

    return { ok = true, data = data, error = nil }
end

---Write data to a JSON file
---@param file_path string Path to the file
---@param data table Data to write
---@return {ok: boolean, error: string|nil} Result
function FileUtils.write_json(file_path, data)
    local Path = require("plenary.path")
    local path = Path:new(file_path)

    -- Ensure parent directory exists
    local parent = path:parent()
    if not parent:exists() then
        log:trace("Creating parent directory: %s", parent:absolute())
        parent:mkdir({ parents = true })
    end

    -- Fix: Ensure data is a table
    if type(data) ~= "table" then
        log:error("Cannot encode non-table data for file: %s", file_path)
        return { ok = false, error = "Cannot encode non-table data" }
    end

    local encoded, encode_error = vim.json.encode(data)
    if not encoded then
        log:error("Failed to encode JSON for file: %s - %s", file_path, encode_error or "unknown error")
        return { ok = false, error = "Failed to encode JSON: " .. (encode_error or "unknown error") }
    end

    local success, write_error = pcall(function()
        return path:write(encoded, "w")
    end)
    if not success then
        log:error("Failed to write file: %s - %s", file_path, write_error or "unknown error")
        return { ok = false, error = "Failed to write file: " .. (write_error or "unknown error") }
    end

    return { ok = true, error = nil }
end

---Delete a file
---@param file_path string Path to the file
---@return {ok: boolean, error: string|nil} Result
function FileUtils.delete_file(file_path)
    local Path = require("plenary.path")
    local path = Path:new(file_path)

    if not path:exists() then
        log:trace("File to delete does not exist: %s", file_path)
        return { ok = true, error = nil }
    end

    local success, err = pcall(function()
        return path:rm()
    end)
    if not success then
        log:trace("Failed to delete file: %s - %s", file_path, err or "unknown error")
        return { ok = false, error = "Failed to delete file: " .. (err or "unknown error") }
    end

    log:trace("Successfully deleted file: %s", file_path)
    return { ok = true, error = nil }
end

function Storage.new(opts)
    local self = setmetatable({}, {
        __index = Storage,
    })

    self.base_path = opts.dir_to_save:gsub("/+$", "")
    self.index_path = self.base_path .. "/index.json"
    self.chats_dir = self.base_path .. "/chats"
    self.expiration_days = opts.expiration_days or 0
    log:trace("Initializing storage with base path: %s, expiration: %d days", self.base_path, self.expiration_days)
    -- Ensure storage directories exist
    self:_ensure_storage_dirs()
    -- Clean expired chats on startup
    self:clean_expired_chats()

    return self --[[@as Storage]]
end

---Clean expired chats based on expiration_days setting
---@private
function Storage:clean_expired_chats()
    -- Skip if expiration is disabled
    if self.expiration_days <= 0 then
        log:trace("Chat expiration disabled, skipping cleanup")
        return
    end

    log:trace("Checking for expired chats (older than %d days)", self.expiration_days)
    local index = self:get_chats()
    local now = os.time()
    local expired_count = 0

    -- Calculate expiration threshold in seconds
    local expiration_threshold = now - (self.expiration_days * 24 * 60 * 60)

    -- Check each chat
    for id, chat_meta in pairs(index) do
        if chat_meta.updated_at and chat_meta.updated_at < expiration_threshold then
            log:trace("Deleting expired chat: %s (last updated: %s)", id, os.date("%Y-%m-%d", chat_meta.updated_at))
            if self:delete_chat(id) then
                expired_count = expired_count + 1
            end
        end
    end

    if expired_count > 0 then
        log:debug("Cleaned up %d expired chats", expired_count)
    end
end

---Get the base path of the storage
---@return string
function Storage:get_location()
    return self.base_path
end

function Storage:_ensure_storage_dirs()
    local Path = require("plenary.path")

    -- Create base directory
    local base_dir = Path:new(self.base_path)
    if not base_dir:exists() then
        log:trace("Creating base directory: %s", self.base_path)
        base_dir:mkdir({ parents = true })
    end

    -- Create chats directory
    local chats_dir = Path:new(self.chats_dir)
    if not chats_dir:exists() then
        log:trace("Creating chats directory: %s", self.chats_dir)
        chats_dir:mkdir({ parents = true })
    end

    -- Initialize index file if it doesn't exist
    local index_path = Path:new(self.index_path)
    if not index_path:exists() then
        log:trace("Initializing empty index file: %s", self.index_path)
        -- Initialize with empty object, not array, since we use it as a key-value store
        local empty_index = vim.empty_dict()
        local result = FileUtils.write_json(self.index_path, empty_index)
        if not result.ok then
            log:error("Failed to initialize index file: %s", result.error)
        end
    end
end

---@param chat_data ChatData
---@return {ok: boolean, error: string|nil}
function Storage:_save_chat_to_file(chat_data)
    local chat_path = self.chats_dir .. "/" .. chat_data.save_id .. ".json"
    log:trace("Saving chat to file: %s", chat_path)
    return FileUtils.write_json(chat_path, chat_data)
end

---@param chat_data ChatData
---@return {ok: boolean, error: string|nil}
function Storage:_update_index_entry(chat_data)
    log:trace("Updating index entry for chat: %s", chat_data.save_id)
    -- Read current index
    local index_result = FileUtils.read_json(self.index_path)
    if not index_result.ok then
        return { ok = false, error = "Failed to read index: " .. index_result.error }
    end

    -- Ensure we have a table to work with
    local index = index_result.data or {}

    -- Calculate message count and token estimate
    local message_count = #(chat_data.messages or {})
    local total_chars = 0
    for _, msg in ipairs(chat_data.messages or {}) do
        total_chars = total_chars + #(msg.content or "")
    end
    local token_estimate = math.floor(total_chars / 4)

    -- Update index with enhanced metadata
    index[chat_data.save_id] = {
        save_id = chat_data.save_id,
        title = chat_data.title,
        updated_at = chat_data.updated_at,
        model = chat_data.settings and chat_data.settings.model or "unknown",
        adapter = chat_data.adapter or "unknown",
        message_count = message_count,
        token_estimate = token_estimate,
        cwd = chat_data.cwd,
        project_root = chat_data.project_root,
    }

    -- Write updated index
    return FileUtils.write_json(self.index_path, utils.remove_functions(index))
end

---Load all chats from storage (index only) with optional filtering
---@param filter_fn? fun(chat_data: ChatIndexData): boolean Optional filter function
---@return table<string, ChatIndexData>
function Storage:get_chats(filter_fn)
    log:trace("Loading chat index")
    local result = FileUtils.read_json(self.index_path)
    if not result.ok then
        if result.error:match("does not exist") then
            log:trace("Index file does not exist, initializing storage")
            self:_ensure_storage_dirs()
            return {}
        else
            log:error("Failed to read chat index: %s", result.error)
            return {}
        end
    end

    local all_chats = result.data or {}

    -- If no filter provided, return all chats
    if not filter_fn then
        return all_chats
    end

    -- Apply filter and return filtered chats
    local filtered_chats = {}
    for id, chat_data in pairs(all_chats) do
        if filter_fn(chat_data) then
            filtered_chats[id] = chat_data
        end
    end

    return filtered_chats
end

---Load a specific chat by ID
---@param id string
---@return ChatData|nil
function Storage:load_chat(id)
    local chat_path = self.chats_dir .. "/" .. id .. ".json"
    log:trace("Loading chat from: %s", chat_path)
    local result = FileUtils.read_json(chat_path)

    if not result.ok then
        if not result.error:match("does not exist") then
            log:error("Failed to load chat: %s", result.error)
        end
        return nil
    end

    return result.data --[[@as ChatData]]
end

---Validate chat object for required fields and structure
---@param chat table
---@return boolean, string?
local function validate_chat_object(chat)
    if not chat then
        return false, "chat object is nil"
    end
    if type(chat) ~= "table" then
        return false, "chat must be a table"
    end
    if type(chat.opts) ~= "table" then
        return false, "chat.opts must be a table"
    end
    if type(chat.opts.save_id) ~= "string" then
        return false, "chat.opts.save_id must be a string"
    end
    -- Check for path traversal characters in save_id
    if chat.opts.save_id:match("[/\\]") then
        return false, "invalid characters in save_id"
    end
    -- Validate messages structure if present
    if chat.messages ~= nil then
        if type(chat.messages) ~= "table" then
            return false, "messages must be a table"
        end
        for i, msg in ipairs(chat.messages) do
            if type(msg) ~= "table" then
                return false, string.format("message %d must be a table", i)
            end
            if msg.role ~= nil and type(msg.role) ~= "string" then
                return false, string.format("message %d role must be a string", i)
            end
            if msg.content ~= nil and type(msg.content) ~= "string" then
                return false, string.format("message %d content must be a string", i)
            end
        end
    end
    return true
end

---Save a chat to storage falling back to the last chat if none is provided
---@param chat? Chat
function Storage:save_chat(chat)
    if not chat then
        chat = require("codecompanion").last_chat()
        if not chat then
            return
        end
    end

    -- Validate chat object structure
    local valid, err = validate_chat_object(chat)
    if not valid then
        log:error("Cannot save chat: %s", err)
        return
    end

    log:trace("Saving chat: %s", chat.opts.save_id)
    -- Create chat data object requiring valid types
    local cwd = vim.fn.getcwd()
    ---@type ChatData
    local chat_data = {
        save_id = chat.opts.save_id,
        title = chat.opts.title,
        messages = chat.messages or {},
        settings = chat.settings or {},
        adapter = chat.adapter and chat.adapter.name or "unknown",
        updated_at = os.time(),
        refs = chat.refs or {},
        schemas = (chat.tools and chat.tools.schemas) or {},
        in_use = (chat.tools and chat.tools.in_use) or {},
        cycle = chat.cycle or 1,
        title_refresh_count = chat.opts.title_refresh_count or 0,
        cwd = cwd,
        project_root = utils.find_project_root(cwd),
    }

    -- Save chat to file
    local save_result = self:_save_chat_to_file(utils.remove_functions(chat_data))
    if not save_result.ok then
        log:error("Failed to save chat: %s", save_result.error)
        return
    end

    -- Update index
    local index_result = self:_update_index_entry(chat_data)
    if not index_result.ok then
        log:error("Failed to update index: %s", index_result.error)
    end
end

---Delete a chat from storage
---@param id string
---@return boolean
function Storage:delete_chat(id)
    if not id then
        log:error("Cannot delete chat: missing id")
        return false
    end

    log:debug("Deleting chat: %s", id)
    -- Delete the chat file
    local chat_path = self.chats_dir .. "/" .. id .. ".json"
    local delete_result = FileUtils.delete_file(chat_path)
    if not delete_result.ok then
        log:error("Failed to delete chat file: %s", delete_result.error)
    end

    -- Remove from index
    local index_result = FileUtils.read_json(self.index_path)
    if not index_result.ok then
        log:error("Failed to read index for deletion: %s", index_result.error)
        return false
    end

    -- Ensure we have a table to work with
    local index = index_result.data or {}

    -- Remove entry from index
    index[id] = nil

    -- Save updated index
    local write_result = FileUtils.write_json(self.index_path, index)
    if not write_result.ok then
        log:error("Failed to update index after deletion: %s", write_result.error)
        return false
    end
    return true
end

---Get the most recently updated chat from storage with optional filtering
---@param filter_fn? fun(chat_data: ChatIndexData): boolean Optional filter function
---@return ChatData|nil
function Storage:get_last_chat(filter_fn)
    log:debug("Getting most recent chat")
    local index = self:get_chats(filter_fn)
    if vim.tbl_isempty(index) then
        return nil
    end

    -- Find the most recently updated chat
    local most_recent = nil
    local most_recent_time = 0

    for id, chat_meta in pairs(index) do
        if chat_meta.updated_at and chat_meta.updated_at > most_recent_time then
            most_recent = id
            most_recent_time = chat_meta.updated_at
        end
    end

    -- If we found a recent chat, load and return it
    if most_recent then
        log:trace("Found most recent chat: %s", most_recent)
        return self:load_chat(most_recent)
    end

    return nil
end

---Rename a chat in storage
---@param save_id string The chat ID to rename
---@param new_title string The new title for the chat
---@return boolean success
function Storage:rename_chat(save_id, new_title)
    log:trace("Renaming chat %s to: %s", save_id, new_title)
    local index = self:get_chats()
    if not index[save_id] then
        log:error("Chat %s not found in index", save_id)
        return false
    end

    -- Update index
    index[save_id].title = new_title
    index[save_id].updated_at = os.time()
    local result = FileUtils.write_json(self.index_path, index)
    if not result.ok then
        log:error("Failed to update index with new title: %s", result.error)
        return false
    end

    -- Update chat data
    local chat_path = self.chats_dir .. "/" .. save_id .. ".json"
    local chat_result = FileUtils.read_json(chat_path)
    if chat_result.ok then
        chat_result.data.title = new_title
        chat_result.data.updated_at = os.time()
        result = FileUtils.write_json(chat_path, chat_result.data)
        if not result.ok then
            log:error("Failed to update chat file with new title: %s", result.error)
            return false
        end
    end

    log:debug("Successfully renamed chat %s to: %s", save_id, new_title)
    return true
end

---Duplicate a chat in storage with a new title
---@param original_id string The original chat ID to duplicate
---@param new_title? string Optional new title (defaults to "Title (1)")
---@return string|nil new_save_id The new chat's save_id if successful
function Storage:duplicate_chat(original_id, new_title)
    log:trace("Duplicating chat: %s", original_id)

    -- Load original chat
    local original_chat = self:load_chat(original_id)
    if not original_chat then
        log:error("Cannot duplicate: original chat not found: %s", original_id)
        return nil
    end

    -- Generate new save_id
    local new_save_id = tostring(os.time() * 1000 + math.random(1000))

    -- Generate appropriate title if not provided
    if not new_title then
        local original_title = original_chat.title or "Untitled"
        new_title = original_title .. " (1)"
    end

    -- Create duplicated chat data
    local duplicated_chat = vim.deepcopy(original_chat)
    duplicated_chat.save_id = new_save_id
    duplicated_chat.title = new_title
    duplicated_chat.updated_at = os.time()
    duplicated_chat.title_refresh_count = 0 -- Reset refresh count for new chat

    -- Save duplicated chat
    local save_result = self:_save_chat_to_file(duplicated_chat)
    if not save_result.ok then
        log:error("Failed to save duplicated chat: %s", save_result.error)
        return nil
    end

    -- Update index
    local index_result = self:_update_index_entry(duplicated_chat)
    if not index_result.ok then
        log:error("Failed to update index for duplicated chat: %s", index_result.error)
        return nil
    end

    log:debug("Successfully duplicated chat %s -> %s", original_id, new_save_id)
    return new_save_id
end

return Storage
