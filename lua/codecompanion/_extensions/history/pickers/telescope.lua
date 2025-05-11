local DefaultPicker = require("codecompanion._extensions.history.pickers.default")
local utils = require("codecompanion._extensions.history.utils")

---@class TelescopePicker : DefaultPicker
local TelescopePicker = setmetatable({}, {
    __index = DefaultPicker,
})
TelescopePicker.__index = TelescopePicker

---@param current_save_id? string
function TelescopePicker:browse(current_save_id)
    require("telescope.pickers")
        .new({}, {
            prompt_title = "Saved Chats",
            finder = require("telescope.finders").new_table({
                results = self.chats,
                entry_maker = function(entry)
                    local display_title =
                        self:format_entry(entry, (current_save_id and current_save_id) == entry.save_id)

                    return vim.tbl_extend("keep", {
                        value = entry,
                        display = display_title,
                        ordinal = entry.title or "",
                        name = entry.title,
                        save_id = entry.save_id,
                        title = entry.title,
                        messages = entry.messages,
                    }, entry)
                end,
            }),
            sorter = require("telescope.config").values.generic_sorter({}),
            previewer = require("telescope.previewers").new_buffer_previewer({
                title = "Chat Preview",
                define_preview = function(preview_state, entry)
                    local lines = self.handlers.on_preview(entry)
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
                            "Are you sure you want to delete " .. #selections .. " items? (y/n)",
                            "&Yes\n&No"
                        )
                        if confirm ~= 1 then
                            return
                        end
                    end
                    -- Delete all selected items
                    for _, selection in ipairs(selections) do
                        self.handlers.on_delete(selection.value)
                    end
                    self.handlers.on_open()
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
                        default = selection.value.title or "",
                    }, function(new_title)
                        if new_title and vim.trim(new_title) ~= "" then
                            self.handlers.on_rename(selection.value, new_title)
                            self.handlers.on_open()
                        end
                    end)
                end

                -- Multi-select toggle with <Tab>
                actions.select_default:replace(function()
                    local selection = action_state.get_selected_entry()
                    if selection then
                        actions.close(prompt_bufnr)
                        self.handlers.on_select(selection.value)
                    end
                end)
                -- Delete chats
                -- Delete chats (normal mode and <M-d> in insert mode)
                vim.keymap.set({ "n" }, self.keymaps.delete.n, delete_selections, {
                    buffer = prompt_bufnr,
                    silent = true,
                    nowait = true,
                })
                vim.keymap.set({ "i" }, self.keymaps.delete.i, delete_selections, {
                    buffer = prompt_bufnr,
                    silent = true,
                    nowait = true,
                })

                -- Rename chat (normal mode and <C-r> in insert mode)
                vim.keymap.set({ "n" }, self.keymaps.rename.n, rename_selection, {
                    buffer = prompt_bufnr,
                    silent = true,
                    nowait = true,
                })
                vim.keymap.set({ "i" }, self.keymaps.rename.i, rename_selection, {
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
