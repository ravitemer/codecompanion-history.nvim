local M = {}

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
---@return EditorInfo Information about current editor state
function M.get_editor_info()
    local buffers = vim.fn.getbufinfo({ buflisted = 1 })
    local valid_buffers = {}
    local last_active = nil
    local max_lastused = 0

    for _, buf in ipairs(buffers) do
        -- Only include valid files (non-empty name and empty buftype)
        local buftype = vim.api.nvim_buf_get_option(buf.bufnr, "buftype")
        if buf.name ~= "" and buftype == "" then
            ---@class BufferInfo
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
            }

            -- Add cursor info for currently visible buffers
            if buffer_info.is_visible then
                local win = buffer_info.winnr
                local cursor = vim.api.nvim_win_get_cursor(win)
                buffer_info.cursor_pos = cursor
            end

            -- Add additional buffer info
            buffer_info.filetype = vim.api.nvim_buf_get_option(buf.bufnr, "filetype")
            buffer_info.line_count = vim.api.nvim_buf_line_count(buf.bufnr)

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

return M
