---@class CodeCompanion.History.FzfluaPicker : CodeCompanion.History.DefaultPicker
local FzfluaPicker = setmetatable({}, {
    __index = require("codecompanion._extensions.history.pickers.default"),
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
            [conv(self.config.keymaps.rename.i)] = function(selections)
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
            [conv(self.config.keymaps.delete.i)] = function(selections)
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
            [conv(self.config.keymaps.duplicate.i)] = function(selections)
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
