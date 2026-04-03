---Picker auto-resolution for codecompanion-history extension
---Simplified to only use fzf-lua

---Get the best available history picker
---@return CodeCompanion.History.Pickers resolved picker name
local function get_history_picker()
    -- Only use fzf-lua picker
    return "fzf-lua"
end

---Resolve a picker name to its module
---@param picker_name CodeCompanion.History.Pickers
---@return table picker module
local function resolve_picker(picker_name)
    if picker_name == "fzf-lua" then
        return require("codecompanion._extensions.history.pickers.fzf-lua")
    else
        error("Only fzf-lua picker is supported in this simplified version")
    end
end

return {
    history = get_history_picker(),
    resolve = resolve_picker,
}
