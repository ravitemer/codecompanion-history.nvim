---@module "vectorcode"
---@module "codecompanion"

local log = require("codecompanion._extensions.history.log")

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
---@field opts CodeCompanion.History.MemoryOpts|{}
local M = {
    opts = {
        auto_create_memories_on_summary_generation = true,
        vectorcode_exe = "vectorcode",
        tool_opts = { default_num = 10 },
        notify = true,
    },
}

---@return boolean
function M.has_vectorcode()
    return vim.fn.executable(M.opts.vectorcode_exe) == 1
end

---@generic F: function
---@param f F
---@return F
local function check_vectorcode_wrap(f)
    return function(...)
        if not M.has_vectorcode() then
            local e =
                "VectorCode is not installed. See https://github.com/Davidyz/VectorCode/blob/main/docs/cli.md#installation"
            log:error(e)
            error(e)
        end
        return f(...)
    end
end

--- Vectorise the given file into the collection managed by VectorCode.
--- If `path` is empty, it'll attempt to index all existing memories.
---@param path string?
M.vectorise = check_vectorcode_wrap(function(path)
    local summary_dir = get_summary_dir()
    if summary_dir == nil then
        return
    end
    path = path or vim.fs.joinpath(summary_dir, "*.md")
    if M.opts.notify then
        vim.notify("Indexing summary for the memory tool.", vim.log.levels.INFO, { title = "CodeCompanion-History" })
    end
    vim.system({ M.opts.vectorcode_exe, "vectorise", "--project_root", summary_dir, "--pipe", path }, {}, function(out)
        if M.opts.notify then
            vim.notify("Indexing finished!", vim.log.levels.INFO, { title = "CodeCompanion-History" })
        end
        local ok, _ = pcall(vim.json.decode, out.stdout)
        if not ok and out.stderr then
            log:error(out.stderr)
        end
    end)
end)

---@param opts CodeCompanion.History.MemoryTool.Opts
---@return CodeCompanion.Agent.Tool|{}
M.make_memory_tool = check_vectorcode_wrap(function(opts)
    opts = vim.tbl_deep_extend("force", { default_num = 10 }, opts or {})
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
                            description = "A non-empty list of keywords used to search for relevant memories. Include words with similar meanings to improve the search.",
                        },
                        count = {
                            type = "integer",
                            description = string.format(
                                "Number of memories to fetch. If the user did not specify, use %d",
                                opts.default_num
                            ),
                        },
                    },
                    required = { "keywords" },
                    additionalProperties = false,
                },
            },
        },
        cmds = {
            ---@param agent CodeCompanion.Agent
            ---@param action CodeCompanion.History.MemoryTool.Args
            ---@return nil|{ status: string, data: string }
            function(agent, action, _, cb)
                if get_summary_dir() == nil then
                    return { status = "error", data = "Failed to find the path to the summaries." }
                end
                local args = {
                    M.opts.vectorcode_exe,
                    "query",
                    "--project_root",
                    get_summary_dir(),
                    "--pipe",
                    "-n",
                    tostring(action.count or 10),
                }
                if not vim.islist(action.keywords or {}) or #(action.keywords or {}) == 0 then
                    return cb({
                        status = "error",
                        data = "You must provide a non-empty list of keywords to search for memories.",
                    })
                end
                vim.list_extend(args, action.keywords or {})
                cb = vim.schedule_wrap(cb)
                vim.system(args, {}, function(out)
                    local ok, result = pcall(vim.json.decode, out.stdout)
                    if ok then
                        cb({ status = "success", data = result })
                    else
                        cb({ status = "error", data = out.stderr })
                    end
                end)
            end,
        },
        output = {
            error = function(self, agent, cmd, stderr, stdout)
                local chat = agent.chat
                local errors = vim.iter(stderr):flatten():join("\n")
                log:debug("[Memory Tool] Error output: %s", stderr)

                local error_output = string.format(
                    [[**Memory Tool**: Ran with an error:

````txt
%s
````]],
                    errors
                )
                chat:add_tool_output(self, error_output)
            end,
            ---@param agent CodeCompanion.Agent
            ---@param cmd table
            ---@param stdout table
            success = function(self, agent, cmd, stdout)
                ---@type VectorCode.Result[]
                stdout = stdout[1]

                if #stdout == 0 then
                    agent.chat:add_tool_output(self, "The memory tool found 0 memories.")
                    return
                end
                for i, result in ipairs(stdout) do
                    local user_message = ""
                    if i == 1 then
                        user_message = string.format("Retrieved %d memories.", #stdout)
                    end
                    agent.chat:add_tool_output(
                        self,
                        string.format("<memory>\n%s\n</memory>", result.document),
                        user_message
                    )
                end
            end,
        },
    }
end)

return M
