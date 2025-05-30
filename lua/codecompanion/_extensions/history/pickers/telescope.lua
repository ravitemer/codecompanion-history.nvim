local DefaultPicker = require("codecompanion._extensions.history.pickers.default")
local utils = require("codecompanion._extensions.history.utils")

---@class TelescopePicker : DefaultPicker
local TelescopePicker = setmetatable({}, {
    __index = DefaultPicker,
})
TelescopePicker.__index = TelescopePicker

function TelescopePicker:browse()
    require("telescope.pickers")
        .new({}, {
            prompt_title = self.config.title,
            finder = require("telescope.finders").new_table({
                results = self.config.items,
                entry_maker = function(entry)
                    local display_title = self:format_entry(entry)

                    -- Create telescope entry with generic fields
                    return vim.tbl_extend("keep", {
                        value = entry,
                        display = display_title,
                        ordinal = self:get_item_title(entry),
                        name = self:get_item_title(entry),
                        item_id = self:get_item_id(entry),
                    }, entry)
                end,
            }),
            sorter = require("telescope.config").values.generic_sorter({}),
            previewer = require("telescope.previewers").new_buffer_previewer({
                title = self:get_item_name_singular():gsub("^%l", string.upper) .. " Preview",
                define_preview = function(preview_state, entry)
                    local lines = self.config.handlers.on_preview(entry)
                    if not lines then
                        return
                    end
                    vim.bo[preview_state.state.bufnr].filetype = "markdown"
                    vim.api.nvim_buf_set_lines(preview_state.state.bufnr, 0, -1, false, lines)
                end,
            }),
            attach_mappings = function(prompt_bufnr)
                local actions = require("telescope.actions")
                local action_state = require("telescope.actions.state")

                local delete_selections = function()
                    local picker = action_state.get_current_picker(prompt_bufnr)
                    local selections = picker:get_multi_selection()

                    if #selections == 0 then
                        -- If no multi-selection, use current selection
                        local selection = action_state.get_selected_entry()
                        if selection then
                            selections = { selection }
                        end
                    end

                    actions.close(prompt_bufnr)

                    -- Confirm deletion if multiple items selected
                    if #selections > 1 then
                        local confirm = vim.fn.confirm(
                            "Are you sure you want to delete "
                                .. #selections
                                .. " "
                                .. self:get_item_name_plural()
                                .. "? (y/n)",
                            "&Yes\n&No"
                        )
                        if confirm ~= 1 then
                            return
                        end
                    end
                    -- Delete all selected items
                    for _, selection in ipairs(selections) do
                        self.config.handlers.on_delete(selection.value)
                    end
                    self.config.handlers.on_open()
                end

                -- Function to handle renaming
                local rename_selection = function()
                    local selection = action_state.get_selected_entry()
                    if not selection then
                        return
                    end
                    actions.close(prompt_bufnr)

                    -- Prompt for new title
                    vim.ui.input({
                        prompt = "New title: ",
                        default = self:get_item_title(selection.value),
                    }, function(new_title)
                        if new_title and vim.trim(new_title) ~= "" then
                            self.config.handlers.on_rename(selection.value, new_title)
                            self.config.handlers.on_open()
                        end
                    end)
                end

                -- Select action
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    if selection then
                        actions.close(prompt_bufnr)
                        self.config.handlers.on_select(selection.value)
                    end
                end)

                -- Delete items (normal mode and insert mode)
                vim.keymap.set({ "n" }, self.config.keymaps.delete.n, delete_selections, {
                    buffer = prompt_bufnr,
                    silent = true,
                    nowait = true,
                })
                vim.keymap.set({ "i" }, self.config.keymaps.delete.i, delete_selections, {
                    buffer = prompt_bufnr,
                    silent = true,
                    nowait = true,
                })

                -- Rename items (normal mode and insert mode)
                vim.keymap.set({ "n" }, self.config.keymaps.rename.n, rename_selection, {
                    buffer = prompt_bufnr,
                    silent = true,
                    nowait = true,
                })
                vim.keymap.set({ "i" }, self.config.keymaps.rename.i, rename_selection, {
                    buffer = prompt_bufnr,
                    silent = true,
                    nowait = true,
                })

                return true
            end,
        })
        :find()
end

return TelescopePicker
