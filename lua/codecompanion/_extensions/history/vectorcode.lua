---@module "vectorcode"
---@module "codecompanion"

local ok, vectorcode_jobrunner = pcall(require, "vectorcode.jobrunner.cmd")
local log = require("codecompanion._extensions.history.log")
if not ok then
    log:error("VectorCode is not installed.")
    return
end

---@return string?
local function get_summary_dir()
    local history_dir = require("codecompanion._extensions.history").exports.get_location()
    if history_dir == nil then
        log:error("codecompanion-history not fully initialised.")
        return
    end
    return vim.fs.joinpath(history_dir, "summaries")
end

---@class CodeCompanion.History.VectorCode
local M = {}

---@param path string?
function M.vectorise(path)
    local summary_dir = get_summary_dir()
    if summary_dir == nil then
        return
    end
    path = path or vim.fs.joinpath(summary_dir, "*.md")
    vectorcode_jobrunner.run_async(
        { "vectorise", "--project_root", summary_dir, "--pipe", path },
        function(result, error, code, signal)
            log:info(vim.inspect(result))
            if error and not vim.tbl_isempty(error) then
                log:error(error)
            end
        end,
        0
    )
end

---@class CodeCompanion.History.MemoryTool.Args
---@field keywords string[]
---@field count integer

---@param opts VectorCode.CodeCompanion.ToolOpts?
---@return CodeCompanion.Agent.Tool|{}
function M.make_memory_tool(opts)
    opts = opts or {}
    ---@type CodeCompanion.Agent.Tool|{}
    return {
        name = "memory",
        schema = {
            type = "function",
            ["function"] = {
                name = "memory",
                description = [[
This tool gives you access to previous conversations.
Use this tool when users mentioned a previous conversation, or when you feel like you can make use of previous chats.
]],
                parameters = {
                    type = "object",
                    properties = {
                        keywords = {
                            type = "array",
                            items = { type = "string" },
                            description = "Keywords used to search for relevant memories. Include words with similar meanings to improve the search.",
                        },
                        count = {
                            type = "integer",
                            description = string.format(
                                "Number of memories to fetch. If the user did not specify, use %d",
                                opts.default_num or 10
                            ),
                        },
                    },
                },
            },
        },
        system_prompt = function(schema)
            return ""
        end,
        cmds = {
            ---@param agent CodeCompanion.Agent
            ---@param action CodeCompanion.History.MemoryTool.Args
            ---@return nil|{ status: string, data: string }
            function(agent, action, _, cb)
                if get_summary_dir() == nil then
                    return { status = "error", data = "Failed to find the path to the summaries." }
                end
                local args = {
                    "query",
                    "--project_root",
                    get_summary_dir(),
                    "--pipe",
                    "-n",
                    tostring(action.count or 10),
                }
                vim.list_extend(args, action.keywords)
                vectorcode_jobrunner.run_async(args, function(result, error, code, signal)
                    if not vim.tbl_isempty(result) then
                        cb({ status = "success", data = result })
                    else
                        cb({ status = "error", data = error })
                    end
                end, 0)
            end,
        },
        output = {
            ---@param agent CodeCompanion.Agent
            ---@param cmd table
            ---@param stdout table
            success = function(self, agent, cmd, stdout)
                ---@type VectorCode.Result[]
                stdout = stdout[1]

                for i, result in ipairs(stdout) do
                    local user_message = ""
                    if i == 1 then
                        user_message = string.format("Retrieved %d memories.", #stdout)
                    end
                    agent.chat:add_tool_output(
                        self,
                        string.format("<memory>%s</memory>", result.document),
                        user_message
                    )
                end
            end,
        },
    }
end

return M
