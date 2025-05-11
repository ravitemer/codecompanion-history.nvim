local utils = require("codecompanion._extensions.history.utils")

---@alias Pickers "telescope" | "snacks" | "default"

---@class DefaultPicker
---@field chats ChatData[]
---@field handlers UIHandlers
local DefaultPicker = {}
DefaultPicker.__index = DefaultPicker

---Format a chat entry for display
---@param entry ChatIndexData Entry from the index
---@param is_current boolean Whether this is the current chat
---@return string formatted_display
function DefaultPicker:format_entry(entry, is_current)
    local parts = {}

    -- Current chat indicator
    local chevron = ""
    table.insert(parts, is_current and chevron or " ")

    -- Title
    table.insert(parts, entry.title or "Untitled")

    -- -- Model (compact format)
    -- if entry.model then
    --     local model_short = entry.model:match("([^/]+)$") or entry.model
    --     if #model_short > 15 then
    --         model_short = model_short:sub(1, 12) .. "..."
    --     end
    --     table.insert(parts, "(" .. model_short .. ")")
    -- end

    if entry.token_estimate then
        local tokens = entry.token_estimate
        tokens = string.format("%.1fk", tokens / 1000)
        table.insert(parts, "(~" .. tokens .. ")")
    end
    -- Relative time
    local icon = " "
    table.insert(parts, icon .. utils.format_relative_time(entry.updated_at) .. "")

    return table.concat(parts, " ")
end

---@param chats ChatData[]
---@param handlers UIHandlers
---@return DefaultPicker
function DefaultPicker:new(chats, handlers, keymaps)
    local base = setmetatable({}, self)
    self.chats = chats
    self.handlers = handlers
    self.keymaps = keymaps

    return base
end

---@param current_save_id? string
function DefaultPicker:browse(current_save_id)
    vim.ui.select(self.chats, {
        prompt = "Saved Chats",
        format_item = function(item)
            return self:format_entry(item, (current_save_id and current_save_id) == item.save_id)
        end,
    }, function(selected)
        if selected then
            self.handlers.on_select(selected)
        end
    end)
end

return DefaultPicker
