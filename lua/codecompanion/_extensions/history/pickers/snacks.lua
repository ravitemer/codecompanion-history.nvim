---@class CodeCompanion.History.SnacksPicker : CodeCompanion.History.DefaultPicker
local SnacksPicker = setmetatable({}, {
    __index = require("codecompanion._extensions.history.pickers.default"),
})
SnacksPicker.__index = SnacksPicker

function SnacksPicker:browse()
    require("snacks.picker").pick({
        title = self.config.title,
        items = self.config.items,
        main = { file = false, float = true },
        format = function(item)
            return { { self:format_entry(item) } }
        end,
        transform = function(item)
            item.file = self:get_item_id(item)
            item.text = self:get_item_title(item)
            return item
        end,
        preview = function(ctx)
            local item = ctx.item
            local lines = self.config.handlers.on_preview(item)
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
                    self.config.handlers.on_select(item)
                end)
            end
            picker:close()
        end,
        actions = {
            rename_item = function(picker)
                local selections = picker:selected({ fallback = true })
                if #selections ~= 1 then
                    return vim.notify(
                        "Can rename only one " .. self:get_item_name_singular() .. " at a time",
                        vim.log.levels.WARN
                    )
                end
                local selection = selections[1]
                picker:close()
                self.config.handlers.on_rename(selection)
            end,
            delete_item = function(picker)
                local selections = picker:selected({ fallback = true })
                if #selections == 0 then
                    return
                end
                picker:close()
                self.config.handlers.on_delete(selections)
            end,
            duplicate_chat = function(picker)
                local selections = picker:selected({ fallback = true })
                if #selections ~= 1 then
                    return vim.notify("Can duplicate only one chat at a time", vim.log.levels.WARN)
                end
                local selection = selections[1]
                picker:close()
                self.config.handlers.on_duplicate(selection)
            end,
        },

        win = {
            input = {
                keys = {
                    [self.config.keymaps.delete.n] = "delete_item",
                    [self.config.keymaps.delete.i] = "delete_item",
                    [self.config.keymaps.rename.n] = "rename_item",
                    [self.config.keymaps.rename.i] = "rename_item",
                    [self.config.keymaps.duplicate.n] = "duplicate_chat",
                    [self.config.keymaps.duplicate.i] = "duplicate_chat",
                },
            },
            list = {
                keys = {
                    [self.config.keymaps.delete.n] = "delete_item",
                    [self.config.keymaps.delete.i] = "delete_item",
                    [self.config.keymaps.rename.n] = "rename_item",
                    [self.config.keymaps.rename.i] = "rename_item",
                    [self.config.keymaps.duplicate.n] = "duplicate_chat",
                    [self.config.keymaps.duplicate.i] = "duplicate_chat",
                },
            },
        },
    })
end

return SnacksPicker
