---@class CodeCompanion.History.FzfluaPicker
---@field config CodeCompanion.History.PickerConfig
local FzfluaPicker = {}
FzfluaPicker.__index = FzfluaPicker

---@param config CodeCompanion.History.PickerConfig
---@return CodeCompanion.History.FzfluaPicker
function FzfluaPicker:new(config)
    local base = setmetatable({}, self)
    self.config = config
    return base
end

-- Convert neovim bind to fzf bind

---Get the unique ID for an item
---@param item table
---@return string
function FzfluaPicker:get_item_id(item)
    if self.config.item_type == "chat" then
        return item.save_id
    else -- summary
        return item.summary_id
    end
end

---Get the display title for an item
---@param item table
---@return string
function FzfluaPicker:get_item_title(item)
    if self.config.item_type == "chat" then
        return item.title or "Untitled"
    else -- summary
        return item.chat_title or item.chat_id or "Untitled"
    end
end

---Check if an item is the current item
---@param item table
---@return boolean
function FzfluaPicker:is_current_item(item)
    return self.config.current_item_id == self:get_item_id(item)
end

---Get the item name for user messages (singular)
---@return string
function FzfluaPicker:get_item_name_singular()
    return self.config.item_type == "chat" and "chat" or "summary"
end

---Format a chat entry for display
---@param entry table Entry from the index
---@return string formatted_display
function FzfluaPicker:format_entry(entry)
    local utils = require("codecompanion._extensions.history.utils")
    local parts = {}

    -- Current chat indicator
    local is_current = self:is_current_item(entry)
    local chevron = ""
    table.insert(parts, is_current and chevron or " ")

    -- Title
    table.insert(parts, self:get_item_title(entry))

    -- Summary indicator
    if entry.has_summary then
        table.insert(parts, "📝")
    end

    if entry.token_estimate then
        local tokens = entry.token_estimate
        table.insert(parts, string.format("(~%.1fk)", tokens / 1000))
    end

    -- Relative time
    local icon = " "
    table.insert(parts, icon .. utils.format_relative_time(entry.updated_at) .. "")

    return table.concat(parts, " ")
end

-- Convert neovim bind to fzf bind
local conv = function(key)
    local conv_map = {
        ["m"] = "alt",
        ["a"] = "alt",
        ["c"] = "ctrl",
        ["s"] = "shift",
    }
    key = key:lower():gsub("[<>]", "")
    for k, v in pairs(conv_map) do
        key = key:gsub(k .. "%-", v .. "-")
    end
    return key
end

FzfluaPicker.__index = FzfluaPicker

function FzfluaPicker:browse()
    local cache = {}
    local nbsp = require("fzf-lua.utils").nbsp

    local format = function(item)
        local item_id = self:get_item_id(item)
        cache[item_id] = item
        return item_id .. nbsp .. self:format_entry(item)
    end

    local decode = function(entry_str)
        return cache[entry_str:match("^(.*)" .. nbsp)]
    end

    require("fzf-lua").fzf_exec(function(fzf_cb)
        vim.iter(self.config.items):map(format):each(fzf_cb)
        fzf_cb(nil)
    end, {
        fzf_opts = { ["--with-nth"] = "2..", ["--delimiter"] = string.format("[%s]", nbsp) },
        winopts = { title = self.config.title },
        actions = {
            enter = function(selections)
                if #selections == 0 then
                    return
                end
                vim.iter(selections):map(decode):each(self.config.handlers.on_select)
            end,
            -- Rename item
             [conv(self.config.picker_keymaps.rename.i)] = function(selections)
                if #selections == 0 then
                    return
                end
                if #selections > 1 then
                    return vim.notify(
                        "Can rename only one " .. self:get_item_name_singular() .. " at a time",
                        vim.log.levels.WARN
                    )
                end

                local selection = decode(selections[1])
                self.config.handlers.on_rename(selection)
            end,
            -- Delete item
             [conv(self.config.picker_keymaps.delete.i)] = function(selections)
                if #selections == 0 then
                    return
                end

                -- Extract chat data from selections
                local chats_to_delete = {}
                for _, selection in ipairs(selections) do
                    table.insert(chats_to_delete, decode(selection))
                end

                self.config.handlers.on_delete(chats_to_delete)
            end,
            -- Duplicate chat
             [conv(self.config.picker_keymaps.duplicate.i)] = function(selections)
                if #selections == 0 then
                    return
                end
                if #selections > 1 then
                    return vim.notify("Can duplicate only one chat at a time", vim.log.levels.WARN)
                end

                local selection = decode(selections[1])
                self.config.handlers.on_duplicate(selection)
            end,
        },
        previewer = {
            _ctor = function()
                local previewer = require("fzf-lua.previewer.builtin").base:extend()
                previewer.populate_preview_buf = function(_, entry_str)
                    local item = decode(entry_str)
                    local lines = self.config.handlers.on_preview(item)
                    if not lines then
                        return
                    end
                    local buf_id = previewer:get_tmp_buffer()
                    vim.bo[buf_id].filetype = "markdown"
                    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
                    _:set_preview_buf(buf_id)
                end
                return previewer
            end,
        },
    })
end

return FzfluaPicker
