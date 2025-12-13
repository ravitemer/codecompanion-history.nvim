return {
    constants = {
        LLM_ROLE = "llm",
        USER_ROLE = "user",
        SYSTEM_ROLE = "system",
    },

    adapters = {
        http = {
            test_adapter = {
                name = "test_adapter",
                url = "https://api.openai.com/v1/chat/completions",
                roles = {
                    llm = "assistant",
                    user = "user",
                },
                opts = {
                    stream = true,
                },
                headers = {
                    content_type = "application/json",
                },
                parameters = {
                    stream = true,
                },
                handlers = {
                    form_parameters = function()
                        return {}
                    end,
                    form_messages = function()
                        return {}
                    end,
                    is_complete = function()
                        return false
                    end,
                    tools = {
                        format_tool_calls = function(self, tools)
                            return tools
                        end,
                        output_response = function(self, tool_call, output)
                            return {
                                role = "tool",
                                tool_call_id = tool_call.id,
                                content = output,
                                opts = { tag = tool_call.id, visible = false },
                            }
                        end,
                    },
                },
                schema = {
                    model = {
                        default = "gpt-3.5-turbo",
                    },
                },
            },
            opts = {
                allow_insecure = false,
                proxy = nil,
            },
        },
        acp = {
            test_acp = {
                name = "test_acp",
                type = "acp",
                command = { "node", "test-agent.js" },
                roles = { user = "user", assistant = "assistant" },
            },
        },
    },
    interactions = {
        chat = {
            adapter = "test_adapter",
            roles = {
                llm = "assistant",
                user = "foo",
            },
            keymaps = {},
            tools = {
                ["cmd_runner"] = {
                    callback = "interactions.chat.agents.tools.cmd_runner",
                    description = "Run shell commands initiated by the LLM",
                },
                ["editor"] = {
                    callback = "interactions.chat.agents.tools.editor",
                    description = "Update a buffer with the LLM's response",
                },
                ["files"] = {
                    callback = "interactions.chat.agents.tools.files",
                    description = "Update the file system with the LLM's response",
                },
                ["weather"] = {
                    callback = vim.fn.getcwd() .. "/tests/stubs/weather.lua",
                    description = "Get the latest weather",
                },
                groups = {
                    ["tool_group"] = {
                        description = "Tool Group",
                        system_prompt = "My tool group system prompt",
                        tools = {
                            "editor",
                            "files",
                        },
                    },
                },
                opts = {
                    system_prompt = "My tool system prompt",
                },
            },
            variables = {
                ["buffer"] = {
                    callback = "interactions.chat.variables.buffer",
                    description = "Share the current buffer with the LLM",
                    opts = {
                        contains_code = true,
                        has_params = true,
                    },
                },
            },
            slash_commands = {
                ["file"] = {
                    callback = "interactions.chat.slash_commands.file",
                    description = "Insert a file",
                    opts = {
                        contains_code = true,
                        max_lines = 1000,
                        provider = "default", -- default|telescope|mini_pick|fzf_lua
                    },
                },
            },
            opts = {
                blank_prompt = "",
            },
        },

        inline = {
            adapter = "test_adapter",
            variables = {},
        },
    },
    prompt_library = {
        ["Demo"] = {
            interaction = "chat",
            description = "Demo prompt",
            opts = {
                alias = "demo",
            },
            prompts = {
                {
                    role = "system",
                    content = "This is some system message",
                    opts = {
                        visible = false,
                    },
                },
                {
                    role = "user",
                    content = "Hi",
                },
                {
                    role = "llm",
                    content = "What can I do?\n",
                },
                {
                    role = "user",
                    content = "",
                },
            },
        },
        ["Test References"] = {
            alias = "chat",
            description = "Add some references",
            opts = {
                index = 1,
                is_default = true,
                is_slash_cmd = false,
                alias = "test_ref",
                auto_submit = false,
            },
            references = {
                {
                    type = "file",
                    path = {
                        "lua/codecompanion/health.lua",
                        "lua/codecompanion/http.lua",
                    },
                },
            },
            prompts = {
                {
                    role = "foo",
                    content = "I need some references",
                },
            },
        },
    },
    display = {
        chat = {
            icons = {
                pinned_buffer = " ",
                watched_buffer = "👀 ",
            },
            show_references = true,
            show_settings = false,
            window = {
                layout = "vertical", -- float|vertical|horizontal|buffer
                position = nil, -- left|right|top|bottom (nil will default depending on vim.opt.splitright|vim.opt.splitbelow)
                border = "single",
                height = 0.8,
                width = 0.45,
                relative = "editor",
                opts = {
                    breakindent = true,
                    cursorcolumn = false,
                    cursorline = false,
                    foldcolumn = "0",
                    linebreak = true,
                    list = false,
                    numberwidth = 1,
                    signcolumn = "no",
                    spell = false,
                    wrap = true,
                },
            },
            intro_message = "", -- Keep this blank or it messes up the screenshot tests
        },
        diff = { enabled = false },
    },
    opts = {
        log_level = "TRACE",
        system_prompt = "default system prompt",
    },
}
