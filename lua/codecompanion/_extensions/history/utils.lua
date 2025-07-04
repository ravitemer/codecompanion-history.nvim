---@diagnostic disable: deprecated
local M = {}

function M.remove_duplicates(list)
    local seen = {}
    local result = {}
    for _, item in ipairs(list) do
        if not seen[item] then
            seen[item] = true
            table.insert(result, item)
        end
    end
    return result
end
--- Format a Unix timestamp into a time string (HH:MM:SS).
---@param timestamp number Unix timestamp
---@return string Formatted time string in HH:MM:SS format
function M.format_time(timestamp)
    if type(timestamp) ~= "number" then
        error("Invalid timestamp: expected a number")
    end

    local formatted_time = os.date("%H:%M:%S", timestamp)
    return tostring(formatted_time) -- Ensure the return type is explicitly a string
end

-- Format timestamp to human readable relative time
---@param timestamp number Unix timestamp
---@return string Relative time string (e.g. "5m ago", "2h ago")
function M.format_relative_time(timestamp)
    local now = os.time()
    local diff = now - timestamp

    if diff < 60 then
        return diff .. "s"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. "h"
    else
        return math.floor(diff / 86400) .. "d"
    end
end

--This function is pasted from ravitemer/mcphub.nvim plugin
---@return CodeCompanion.History.EditorInfo Information about current editor state
function M.get_editor_info()
    local buffers = vim.fn.getbufinfo({ buflisted = 1 })
    local valid_buffers = {}
    local last_active = nil
    local max_lastused = 0

    for _, buf in ipairs(buffers) do
        -- Only include valid files (non-empty name and empty buftype)
        local buftype = vim.api.nvim_buf_get_option(buf.bufnr, "buftype")
        if buf.name ~= "" and buftype == "" then
            ---@type CodeCompanion.History.BufferInfo
            local buffer_info = {
                bufnr = buf.bufnr,
                name = buf.name,
                filename = buf.name,
                is_visible = #buf.windows > 0,
                is_modified = buf.changed == 1,
                is_loaded = buf.loaded == 1,
                lastused = buf.lastused,
                windows = buf.windows,
                winnr = buf.windows[1], -- Primary window showing this buffer
                filetype = vim.api.nvim_buf_get_option(buf.bufnr, "filetype"),
                line_count = vim.api.nvim_buf_line_count(buf.bufnr),
            }

            -- Add cursor info for currently visible buffers
            if buffer_info.is_visible then
                local win = buffer_info.winnr
                local cursor = vim.api.nvim_win_get_cursor(win)
                buffer_info.cursor_pos = cursor
            end

            table.insert(valid_buffers, buffer_info)

            -- Track the most recently used buffer
            if buf.lastused > max_lastused then
                max_lastused = buf.lastused
                last_active = buffer_info
            end
        end
    end

    -- If no valid buffers found, provide default last_active
    if not last_active and #valid_buffers > 0 then
        last_active = valid_buffers[1]
    end

    return {
        last_active = last_active,
        buffers = valid_buffers,
    }
end

---@param obj any The object to process
---@return any The object with functions removed
function M.remove_functions(obj)
    if type(obj) ~= "table" then
        return obj
    end
    local new_obj = {}
    for k, v in pairs(obj) do
        if type(v) ~= "function" then
            new_obj[k] = M.remove_functions(v)
        end
    end
    return new_obj
end

---Fire an event
---@param event string
---@param opts? table
function M.fire(event, opts)
    opts = opts or {}
    vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionHistory" .. event, data = opts })
end

-- File I/O utility functions
---Read and decode a JSON file
---@param file_path string Path to the file
---@return {ok: boolean, data: table|nil, error: string|nil} Result
function M.read_json(file_path)
    -- Use read_file to get the content
    local file_result = M.read_file(file_path)
    if not file_result.ok then
        return { ok = false, data = nil, error = file_result.error }
    end

    -- Parse JSON content
    local success, data = pcall(vim.json.decode, file_result.data)
    if not success then
        return { ok = false, data = nil, error = "Failed to parse JSON: " .. tostring(data) }
    end

    return { ok = true, data = data, error = nil }
end

---Read content from a file
---@param file_path string Path to the file
---@return {ok: boolean, data: string|nil, error: string|nil} Result
function M.read_file(file_path)
    local Path = require("plenary.path")
    local path = Path:new(file_path)

    if not path:exists() then
        return { ok = false, data = nil, error = "File does not exist: " .. file_path }
    end

    local content, read_error = path:read()
    if not content then
        return { ok = false, data = nil, error = "Failed to read file: " .. (read_error or "unknown error") }
    end

    return { ok = true, data = content, error = nil }
end

---Write content to a file
---@param file_path string Path to the file
---@param content string Content to write
---@return {ok: boolean, error: string|nil} Result
function M.write_file(file_path, content)
    local Path = require("plenary.path")
    local path = Path:new(file_path)

    -- Ensure parent directory exists
    local parent = path:parent()
    if not parent:exists() then
        parent:mkdir({ parents = true })
    end

    local success, write_error = pcall(function()
        return path:write(content, "w")
    end)
    if not success then
        return { ok = false, error = "Failed to write file: " .. (write_error or "unknown error") }
    end

    return { ok = true, error = nil }
end

---Write data to a JSON file
---@param file_path string Path to the file
---@param data table Data to write
---@return {ok: boolean, error: string|nil} Result
function M.write_json(file_path, data)
    -- Ensure data is a table
    if type(data) ~= "table" then
        return { ok = false, error = "Cannot encode non-table data" }
    end

    local encoded, encode_error = vim.json.encode(data)
    if not encoded then
        return { ok = false, error = "Failed to encode JSON: " .. (encode_error or "unknown error") }
    end

    return M.write_file(file_path, encoded)
end

---Delete a file
---@param file_path string Path to the file
---@return {ok: boolean, error: string|nil} Result
function M.delete_file(file_path)
    local Path = require("plenary.path")
    local path = Path:new(file_path)

    if not path:exists() then
        return { ok = true, error = nil }
    end

    local success, err = pcall(function()
        return path:rm()
    end)
    if not success then
        return { ok = false, error = "Failed to delete file: " .. (err or "unknown error") }
    end

    return { ok = true, error = nil }
end
---Find project root by looking for common project markers
---@param start_path? string Starting path (defaults to cwd)
---@return string project_root
function M.find_project_root(start_path)
    start_path = start_path or vim.fn.getcwd()

    local markers = {
        ".git",
        "package.json",
        "Cargo.toml",
        "pyproject.toml",
        "go.mod",
        "pom.xml",
        ".gitignore",
        "README.md",
    }

    local root = vim.fs.root(start_path, markers)
    return root or start_path -- fallback to start_path if no root found
end

return M
