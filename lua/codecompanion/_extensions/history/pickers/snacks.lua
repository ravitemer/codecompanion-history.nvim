local DefaultPicker = require("codecompanion._extensions.history.pickers.default")
local utils = require("codecompanion._extensions.history.utils")

---@class SnacksPicker : DefaultPicker
local SnacksPicker = setmetatable({}, {
    __index = DefaultPicker,
})
SnacksPicker.__index = SnacksPicker

---@param current_save_id? string
function SnacksPicker:browse(current_save_id)
    require("snacks.picker").pick({
        title = "Saved Chats",
        items = self.chats,
        main = { file = false, float = true },
        format = function(item)
            return { { self:format_entry(item, (current_save_id and current_save_id) == item.save_id) } }
        end,
        transform = function(item)
            item.file = item.save_id
            item.text = item.name or "Untitled"
            return item
        end,
        preview = function(ctx)
            local item = ctx.item
            local lines = self.handlers.on_preview(item)
            if not lines then
                return
            end

            local buf_id = ctx.preview:scratch()
            vim.bo[buf_id].filetype = "codecompanion"
            vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
        end,
        confirm = function(picker, _)
            local items = picker:selected({ fallback = true })
            if items then
                vim.iter(items):each(function(item)
                    self.handlers.on_select(item)
                end)
            end
            picker:close()
        end,
        actions = {
            rename_chat = function(picker)
                local selections = picker:selected({ fallback = true })
                if #selections ~= 1 then
                    return vim.notify("Can rename only one chat at a time", vim.log.levels.WARN)
                end
                local selection = selections[1]
                picker:close()

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
            delete_chat = function(picker)
                local selections = picker:selected({ fallback = true })
                if #selections == 0 then
                    return
                end

                -- Confirm deletion for multiple items
                if #selections > 1 then
                    local choice = vim.fn.confirm(
                        "Are you sure you want to delete " .. #selections .. " items? (y/n)",
                        "&Yes\n&No"
                    )
                    if choice ~= 1 then
                        return
                    end
                end

                for _, selected in ipairs(selections) do
                    self.handlers.on_delete(selected)
                end
                picker:close()
                self.handlers.on_open()
            end,
        },

        win = {
            input = {
                keys = {
                    [self.keymaps.delete.n] = "delete_chat",
                    [self.keymaps.delete.i] = "delete_chat",
                    [self.keymaps.rename.n] = "rename_chat",
                    [self.keymaps.rename.i] = "rename_chat",
                },
            },
            list = {
                keys = {
                    [self.keymaps.delete.n] = "delete_chat",
                    [self.keymaps.delete.i] = "delete_chat",
                    [self.keymaps.rename.n] = "rename_chat",
                    [self.keymaps.rename.i] = "rename_chat",
                },
            },
        },
    })
end

return SnacksPicker
