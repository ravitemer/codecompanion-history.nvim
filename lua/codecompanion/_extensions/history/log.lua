local M = {}

---Wrap codecompanion log  with prefix that respects enable_logging
---@param enable_logging boolean
function M.setup_logging(enable_logging)
    local codecompanion_log = require("codecompanion.utils.log")
    M.log = setmetatable({}, {
        __index = function(_, method)
            return function(_, msg, ...)
                if enable_logging then
                    codecompanion_log[method](codecompanion_log, "[History] " .. msg, ...)
                end
            end
        end,
    })
end

return setmetatable(M, {
    __index = function(_, key)
        if key == "setup_logging" then
            return M.setup_logging
        end
        return M.log[key]
    end,
})
