local DefaultPicker = require("codecompanion._extensions.history.pickers.default")

---@class FzfluaPicker : DefaultPicker
local FzfluaPicker = setmetatable({}, {
    __index = DefaultPicker,
})

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
---@param current_save_id? string
function FzfluaPicker:browse(current_save_id)
    local cache = {}
    local nbsp = require("fzf-lua.utils").nbsp
    local format = function(item)
        cache[item.save_id] = item
        return item.save_id .. nbsp .. self:format_entry(item, (current_save_id and current_save_id) == item.save_id)
    end
    local decode = function(entry_str)
        return cache[entry_str:match("^(.*)" .. nbsp)]
    end
    require("fzf-lua").fzf_exec(function(fzf_cb)
        vim.iter(self.chats):map(format):each(fzf_cb)
        fzf_cb(nil)
    end, {
        fzf_opts = { ["--with-nth"] = "2..", ["--delimiter"] = string.format("[%s]", nbsp) },
        winopts = { title = "Saved Chats" },
        actions = {
            enter = function(selections)
                if #selections == 0 then
                    return
                end
                vim.iter(selections):map(decode):each(self.handlers.on_select)
            end,
            -- Rename chat
            [conv(self.keymaps.rename.i)] = function(selections)
                if #selections == 0 then
                    return
                end
                if #selections > 1 then
                    return vim.notify("Can rename only one chat at a time", vim.log.levels.WARN)
                end

                local selection = decode(selections[1])
                -- Prompt for new title
                vim.ui.input({
                    prompt = "New title: ",
                    default = selection.title or "",
                }, function(new_title)
                    if new_title and vim.trim(new_title) ~= "" then
                        self.handlers.on_rename(selection, new_title)
                        self.handlers.on_open()
                    end
                end)
            end,
            -- Delete chat
            [conv(self.keymaps.delete.i)] = function(selections)
                if #selections == 0 then
                    return
                end
                -- Confirm deletion if multiple items selected
                if #selections > 1 then
                    local confirm = vim.fn.confirm(
                        "Are you sure you want to delete " .. #selections .. " items? (y/n)",
                        "&Yes\n&No"
                    )
                    if confirm ~= 1 then
                        return
                    end
                end
                -- Delete all selected items
                for _, selection in ipairs(selections) do
                    self.handlers.on_delete(decode(selection))
                end
                self.handlers.on_open()
            end,
            -- Duplicate chat
            [conv(self.keymaps.duplicate.i)] = function(selections)
                if #selections == 0 then
                    return
                end
                if #selections > 1 then
                    return vim.notify("Can duplicate only one chat at a time", vim.log.levels.WARN)
                end

                local selection = decode(selections[1])
                self.handlers.on_duplicate(selection)
            end,
        },
        previewer = {
            _ctor = function()
                local previewer = require("fzf-lua.previewer.builtin").base:extend()
                previewer.populate_preview_buf = function(_, entry_str)
                    local item = decode(entry_str)
                    local lines = self.handlers.on_preview(item)
                    if not lines then
                        return
                    end
                    local buf_id = previewer:get_tmp_buffer()
                    vim.bo[buf_id].filetype = "codecompanion"
                    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
                    _:set_preview_buf(buf_id)
                end
                return previewer
            end,
        },
    })
end

return FzfluaPicker
