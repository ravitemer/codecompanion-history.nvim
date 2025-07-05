local h = require("tests.helpers")
local eq, new_set = MiniTest.expect.equality, MiniTest.new_set
local T = new_set()

local child = h.new_child_neovim()

T = new_set({
    hooks = {
        pre_case = function()
            child.setup()
            child.lua([[              
                -- Setup logging first
                local log = require("codecompanion._extensions.history.log")
                log.setup_logging(false) -- Disable logging for tests

                h = require("tests.helpers")
                
                -- Create summary generator instance with mocked adapter request
                local SummaryGenerator = require("codecompanion._extensions.history.summary_generator")
                test_summary_gen = SummaryGenerator.new({
                    summary = {
                        generation_opts = {
                            context_size = 90000,
                            include_references = true,
                            include_tool_outputs = true,
                        }
                    }
                })

                -- Mock the _make_adapter_request method for basic tests - this should return just the content string
                SummaryGenerator._make_adapter_request = function(self, chat, system_prompt, user_prompt, callback)
                    -- Store prompts for verification
                    self.last_system_prompt = system_prompt
                    self.last_user_prompt = user_prompt
                    
                    -- Clear previous stored values
                    self.last_summary_content = nil

                    -- Simulate async response - return just the content string
                    vim.schedule(function()
                        self.last_summary_content = "# Generated Summary\n\n## Overview\nTest summary content"
                        callback(self.last_summary_content, nil)
                    end)
                end
            ]])
        end,
        post_case = function() end,
        post_once = child.stop,
    },
})

-- Basic Summary Generation Tests
T["Summary Generation"] = new_set()

T["Summary Generation"]["generates summary from basic chat"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil
        local error_msg = nil

        -- Mock chat with basic user-assistant conversation
        local chat = {
            opts = {
                save_id = "test_summary_123",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "How do I create a new file in Vim?",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "You can create a new file in Vim by using the :e command followed by the filename.",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "What about saving the file?",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "To save a file in Vim, use :w command.",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            error_msg = error
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local user_prompt = test_summary_gen.last_user_prompt or ""
        local system_prompt = test_summary_gen.last_system_prompt or ""

        return {
            completed = completed,
            has_summary = generated_summary ~= nil,
            has_error = error_msg ~= nil,
            summary_has_title = generated_summary and type(generated_summary) == "table" and generated_summary.content and generated_summary.content:find("# Generated Summary") ~= nil,
            user_prompt_has_vim_content = user_prompt:find("How do I create a new file in Vim") ~= nil,
            user_prompt_has_user_prefix = user_prompt:find("User:") ~= nil,
            user_prompt_has_assistant_prefix = user_prompt:find("Assistant:") ~= nil,
            system_prompt_has_structure = system_prompt:find("SUMMARY FORMAT") ~= nil,
            summary_id = generated_summary and type(generated_summary) == "table" and generated_summary.summary_id or nil
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_summary)
    eq(false, result.has_error)
    eq(true, result.summary_has_title)
    eq(true, result.user_prompt_has_vim_content)
    eq(true, result.user_prompt_has_user_prefix)
    eq(true, result.user_prompt_has_assistant_prefix)
    eq(true, result.system_prompt_has_structure)
end

T["Summary Generation"]["handles insufficient content"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil
        local error_msg = nil

        -- Mock chat with insufficient messages (less than minimum required)
        local chat = {
            opts = {
                save_id = "test_insufficient",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "Hi",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            error_msg = error
            completed = true
        end)

        -- Wait for completion
        vim.wait(100)

        return {
            completed = completed,
            has_summary = generated_summary ~= nil,
            has_error = error_msg ~= nil,
            error_mentions_minimum = error_msg and error_msg:find("minimum") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(false, result.has_summary)
    eq(true, result.has_error)
    eq(true, result.error_mentions_minimum)
end

T["Summary Generation"]["handles empty messages"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil
        local error_msg = nil

        -- Mock chat with nil messages
        local chat = {
            opts = {
                save_id = "test_empty",
                title = "Test Chat"
            }
            -- messages field intentionally omitted
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            error_msg = error
            completed = true
        end)

        -- Wait for completion
        vim.wait(100)

        return {
            completed = completed,
            has_summary = generated_summary ~= nil,
            has_error = error_msg ~= nil,
            error_mentions_minimum = error_msg and error_msg:find("minimum") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(false, result.has_summary)
    eq(true, result.has_error)
    eq(true, result.error_mentions_minimum)
end

-- Message Filtering Tests
T["Message Filtering"] = new_set()

T["Message Filtering"]["filters out system messages with from_config tag"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil

        -- Mock chat with system messages that should be filtered
        local chat = {
            opts = {
                save_id = "test_filter_system",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "system",
                    content = "You are a helpful assistant",
                    opts = { tag = "from_config" }
                },
                {
                    role = "system",
                    content = "Tool system prompt",
                    opts = { tag = "tool" }
                },
                {
                    role = "user",
                    content = "How do I create a file?",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Use the touch command.",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local user_prompt = test_summary_gen.last_user_prompt or ""

        return {
            completed = completed,
            has_system_config = user_prompt:find("helpful assistant") ~= nil,
            has_tool_system = user_prompt:find("Tool system prompt") ~= nil,
            has_user_content = user_prompt:find("How do I create a file") ~= nil,
            has_llm_content = user_prompt:find("Use the touch command") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(false, result.has_system_config) -- Should be filtered out
    eq(false, result.has_tool_system) -- Should be filtered out
    eq(true, result.has_user_content) -- Should be included
    eq(true, result.has_llm_content) -- Should be included
end

T["Message Filtering"]["includes tool outputs when enabled"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil

        -- Mock chat with tool outputs
        local chat = {
            opts = {
                save_id = "test_tool_outputs",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "List files in current directory",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "I'll list the files for you.",
                    opts = { visible = true },
                    tool_calls = {
                        { ["function"] = { name = "cmd_runner" } }
                    }
                },
                {
                    role = "tool",
                    content = "file1.txt\nfile2.py\nREADME.md",
                    opts = { tag = "tool_output" }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local user_prompt = test_summary_gen.last_user_prompt or ""

        return {
            completed = completed,
            has_tool_output = user_prompt:find("file1.txt") ~= nil,
            has_tool_result_prefix = user_prompt:find("Tool Result:") ~= nil,
            has_tool_call_info = user_prompt:find("cmd_runner") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_tool_output) -- Tool output should be included
    eq(true, result.has_tool_result_prefix) -- Should have proper prefix
    eq(true, result.has_tool_call_info) -- Should mention called tools
end

T["Message Filtering"]["excludes tool outputs when disabled"] = function()
    local result = child.lua([[              
        -- Create generator with tool outputs disabled
        local SummaryGenerator = require("codecompanion._extensions.history.summary_generator")
        local no_tools_gen = SummaryGenerator.new({
            summary = {
                generation_opts = {
                    include_tool_outputs = false
                }
            }
        })

        -- Mock the adapter request for this generator too
        no_tools_gen._make_adapter_request = function(self, chat, system_prompt, user_prompt, callback)
            self.last_user_prompt = user_prompt
            vim.schedule(function()
                callback("# Summary without tools", nil)
            end)
        end

        local completed = false
        local generated_summary = nil

        -- Mock chat with tool outputs
        local chat = {
            opts = {
                save_id = "test_no_tool_outputs",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "List files in directory",
                    opts = { visible = true }
                },
                {
                    role = "tool",
                    content = "file1.txt\nfile2.py",
                    opts = { tag = "tool_output" }
                }
            }
        }

        -- Generate summary
        no_tools_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local user_prompt = no_tools_gen.last_user_prompt or ""

        return {
            completed = completed,
            has_tool_output = user_prompt:find("file1.txt") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(false, result.has_tool_output) -- Tool output should be excluded
end

T["Message Filtering"]["includes references when enabled"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil

        -- Mock chat with reference messages
        local chat = {
            opts = {
                save_id = "test_references",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "function test() { return 42; }",
                    opts = { 
                        visible = false,
                        reference = "file.js"
                    }
                },
                {
                    role = "user",
                    content = "Analyze this code",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "This function returns the number 42.",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local user_prompt = test_summary_gen.last_user_prompt or ""

        return {
            completed = completed,
            has_reference_content = user_prompt:find("function test") ~= nil,
            has_context_prefix = user_prompt:find("Context:") ~= nil,
            has_reference_id = user_prompt:find("file.js") ~= nil,
            has_user_content = user_prompt:find("Analyze this code") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_reference_content) -- Reference should be included
    eq(true, result.has_context_prefix) -- Should have Context: prefix
    eq(true, result.has_reference_id) -- Should include reference ID
    eq(true, result.has_user_content) -- User content should also be included
end

T["Message Filtering"]["excludes references when disabled"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil

        -- Mock chat with reference messages 
        local chat = {
            opts = {
                save_id = "test_no_references",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "function test() { return 42; }",
                    opts = { 
                        visible = false,
                        reference = "file.js"
                    }
                },
                {
                    role = "user",
                    content = "Regular user message1",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Regular user message",
                    opts = { visible = true }
                }
            }
        }

        -- Test the message formatting directly with references disabled
        local SummaryGenerator = require("codecompanion._extensions.history.summary_generator")
        local no_refs_gen = SummaryGenerator.new({
            summary = {
                generation_opts = {
                    include_references = false
                }
            }
        })

        -- Generate summary
        no_refs_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local user_prompt = no_refs_gen.last_user_prompt 

        return {
            completed = completed,
            has_reference_content = user_prompt:find("function test") ~= nil,
            has_regular_msg = user_prompt:find("Regular user message") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(false, result.has_reference_content) -- Reference should be excluded
    eq(true, result.has_regular_msg) -- Regular user message should be included
end

-- Configuration and System Prompt Tests
T["Configuration"] = new_set()

T["Configuration"]["applies format_summary function"] = function()
    local result = child.lua([[              
        -- Create generator with format_summary function
        local SummaryGenerator = require("codecompanion._extensions.history.summary_generator")
        local format_gen = SummaryGenerator.new({
            summary = {
                generation_opts = {
                    format_summary = function(summary)
                        -- Remove <think> tags and trim whitespace
                        return summary:gsub("<think>.-</think>", ""):gsub("^%s*", ""):gsub("%s*$", "")
                    end
                }
            }
        })

        -- Mock the adapter request to return summary with thinking tags
        format_gen._make_adapter_request = function(self, chat, system_prompt, user_prompt, callback)
            vim.schedule(function()
                callback("<think>This is internal reasoning</think># Clean Summary\n\n## Overview\nThis is the actual summary content", nil)
            end)
        end

        local completed = false
        local generated_summary = nil
        local error_msg = nil

        -- Mock chat
        local chat = {
            opts = {
                save_id = "test_format_summary",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "First message",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Response",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Second message",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        format_gen:generate(chat, function(summary, error)
            generated_summary = summary
            error_msg = error
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        return {
            completed = completed,
            has_summary = generated_summary ~= nil,
            has_error = error_msg ~= nil,
            summary_content = generated_summary and generated_summary.content or "",
            has_thinking_tags = generated_summary and generated_summary.content:find("<think>") ~= nil,
            has_clean_content = generated_summary and generated_summary.content:find("# Clean Summary") ~= nil,
            starts_with_hash = generated_summary and generated_summary.content:match("^#") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_summary)
    eq(false, result.has_error)
    eq(false, result.has_thinking_tags) -- Should be removed by format function
    eq(true, result.has_clean_content) -- Should contain the actual content
    eq(true, result.starts_with_hash) -- Should start cleanly without whitespace
end

T["Configuration"]["uses custom system prompt as string"] = function()
    local result = child.lua([[              
        -- Create generator with custom system prompt
        local SummaryGenerator = require("codecompanion._extensions.history.summary_generator")
        local custom_gen = SummaryGenerator.new({
            summary = {
                generation_opts = {
                    system_prompt = "Custom system prompt for testing"
                }
            }
        })

        -- Mock the adapter request
        custom_gen._make_adapter_request = function(self, chat, system_prompt, user_prompt, callback)
            self.last_system_prompt = system_prompt
            vim.schedule(function()
                callback("# Custom Summary", nil)
            end)
        end

        local completed = false
        local generated_summary = nil

        -- Mock chat
        local chat = {
            opts = {
                save_id = "test_custom_prompt",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "First message",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Response",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Second message",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        custom_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local system_prompt = custom_gen.last_system_prompt or ""

        return {
            completed = completed,
            has_custom_prompt = system_prompt:find("Custom system prompt for testing") ~= nil,
            doesnt_have_default = system_prompt:find("SUMMARY FORMAT") == nil
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_custom_prompt)
    eq(true, result.doesnt_have_default)
end

T["Configuration"]["uses custom system prompt as function"] = function()
    local result = child.lua([[              
        -- Create generator with function system prompt
        local SummaryGenerator = require("codecompanion._extensions.history.summary_generator")
        local function_gen = SummaryGenerator.new({
            summary = {
                generation_opts = {
                    system_prompt = function() 
                        return "Function-generated prompt: " .. os.date("%Y")
                    end
                }
            }
        })

        -- Mock the adapter request
        function_gen._make_adapter_request = function(self, chat, system_prompt, user_prompt, callback)
            self.last_system_prompt = system_prompt
            vim.schedule(function()
                callback("# Function Summary", nil)
            end)
        end

        local completed = false
        local generated_summary = nil

        -- Mock chat
        local chat = {
            opts = {
                save_id = "test_function_prompt",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "Message 1",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Response 1",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Message 2",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        function_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local system_prompt = function_gen.last_system_prompt or ""

        return {
            completed = completed,
            has_function_prompt = system_prompt:find("Function%-generated prompt:") ~= nil,
            has_current_year = system_prompt:find(tostring(os.date("%Y"))) ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_function_prompt)
    eq(true, result.has_current_year)
end

T["Configuration"]["respects custom context size"] = function()
    local result = child.lua([[              
        -- Create generator with small context size
        local SummaryGenerator = require("codecompanion._extensions.history.summary_generator")
        local small_context_gen = SummaryGenerator.new({
            summary = {
                generation_opts = {
                    context_size = 100 -- Very small context size
                }
            }
        })

        -- Mock the adapter request to track how content is chunked
        local request_count = 0
        small_context_gen._make_adapter_request = function(self, chat, system_prompt, user_prompt, callback)
            request_count = request_count + 1
            self.last_user_prompt = user_prompt
            vim.schedule(function()
                -- Simulate chunked response
                if request_count == 1 then
                    callback("First chunk summary", nil)
                else
                    callback("Final summary", nil)
                end
            end)
        end

        local completed = false
        local generated_summary = nil

        -- Mock chat with large content that should trigger chunking
        local large_content = string.rep("This is a very long message. ", 50) -- About 1500 chars
        local chat = {
            opts = {
                save_id = "test_context_size",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = large_content,
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Response to large content",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Follow up message",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        small_context_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(2000, function() return completed end)

        return {
            completed = completed,
            request_count = request_count,
            has_summary = generated_summary ~= nil,
            final_summary_correct = generated_summary and generated_summary.content == "Final summary"
        }
    ]])

    eq(true, result.completed)
    eq(true, result.request_count >= 1) -- At least one request was made
    eq(true, result.has_summary)
    eq(true, result.final_summary_correct)
end

-- Summary Object Creation Tests
T["Summary Object Creation"] = new_set()

T["Summary Object Creation"]["creates complete summary object with metadata"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil

        -- Mock chat
        local chat = {
            opts = {
                save_id = "test_metadata_123",
                title = "Test Metadata Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "Test question",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Test answer",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Follow up",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        return {
            completed = completed,
            has_summary_id = generated_summary and generated_summary.summary_id == "test_metadata_123",
            has_chat_id = generated_summary and generated_summary.chat_id == "test_metadata_123",
            has_chat_title = generated_summary and generated_summary.chat_title == "Test Metadata Chat",
            has_generated_at = generated_summary and type(generated_summary.generated_at) == "number",
            has_content = generated_summary and generated_summary.content ~= nil,
            has_project_root = generated_summary and generated_summary.project_root ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_summary_id)
    eq(true, result.has_chat_id)
    eq(true, result.has_chat_title)
    eq(true, result.has_generated_at)
    eq(true, result.has_content)
    eq(true, result.has_project_root)
end

T["Summary Object Creation"]["handles chat without title"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil

        -- Mock chat without title
        local chat = {
            opts = {
                save_id = "test_no_title_456"
                -- title intentionally omitted
            },
            messages = {
                {
                    role = "user",
                    content = "Question without title",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Answer",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Follow up",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        return {
            completed = completed,
            has_nil_title = generated_summary and generated_summary.chat_title == nil,
            has_other_fields = generated_summary and generated_summary.summary_id == "test_no_title_456"
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_nil_title)
    eq(true, result.has_other_fields)
end

-- Error Handling and Edge Cases Tests
T["Error Handling"] = new_set()

T["Error Handling"]["handles adapter request errors"] = function()
    local result = child.lua([[              
        -- Create generator that simulates adapter errors
        local SummaryGenerator = require("codecompanion._extensions.history.summary_generator")
        local error_gen = SummaryGenerator.new({
            summary = {
                generation_opts = {
                    context_size = 90000
                }
            }
        })

        -- Mock adapter request to return error
        error_gen._make_adapter_request = function(self, chat, system_prompt, user_prompt, callback)
            vim.schedule(function()
                callback(nil, "Simulated API error")
            end)
        end

        local completed = false
        local generated_summary = nil
        local error_msg = nil

        -- Mock chat
        local chat = {
            opts = {
                save_id = "test_adapter_error",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "This will fail",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Response",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Another message",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        error_gen:generate(chat, function(summary, error)
            generated_summary = summary
            error_msg = error
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        return {
            completed = completed,
            has_summary = generated_summary ~= nil,
            has_error = error_msg ~= nil,
            error_content = error_msg
        }
    ]])

    eq(true, result.completed)
    eq(false, result.has_summary)
    eq(true, result.has_error)
    eq("Simulated API error", result.error_content)
end

T["Error Handling"]["handles empty summary response"] = function()
    local result = child.lua([[              
        -- Create generator that returns empty summary
        local SummaryGenerator = require("codecompanion._extensions.history.summary_generator")
        local empty_gen = SummaryGenerator.new({
            summary = {
                generation_opts = {
                    context_size = 90000
                }
            }
        })

        -- Mock adapter request to return empty string
        empty_gen._make_adapter_request = function(self, chat, system_prompt, user_prompt, callback)
            vim.schedule(function()
                callback("", nil) -- Empty response
            end)
        end

        local completed = false
        local generated_summary = nil
        local error_msg = nil

        -- Mock chat
        local chat = {
            opts = {
                save_id = "test_empty_response",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "This will be empty",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Response",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Another message",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        empty_gen:generate(chat, function(summary, error)
            generated_summary = summary
            error_msg = error
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        return {
            completed = completed,
            has_summary = generated_summary ~= nil,
            has_error = error_msg ~= nil,
            error_mentions_empty = error_msg and error_msg:find("Empty summary") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(false, result.has_summary)
    eq(true, result.has_error)
    eq(true, result.error_mentions_empty)
end

-- Edge Cases Tests
T["Edge Cases"] = new_set()

T["Edge Cases"]["handles very long tool outputs with truncation"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil

        -- Mock chat with very long tool output
        local very_long_output = string.rep("Very long tool output. ", 100) -- About 2500 chars
        local chat = {
            opts = {
                save_id = "test_long_tool_output",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "Run a command",
                    opts = { visible = true }
                },
                {
                    role = "tool",
                    content = very_long_output,
                    opts = { tag = "tool_output" }
                },
                {
                    role = "user",
                    content = "What does this output mean?",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local user_prompt = test_summary_gen.last_user_prompt or ""

        return {
            completed = completed,
            has_summary = generated_summary ~= nil,
            has_tool_content = user_prompt:find("Very long tool output") ~= nil,
            has_truncation = user_prompt:find("truncated") ~= nil,
            prompt_not_too_long = #user_prompt < 2000 -- Should be truncated
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_summary)
    eq(true, result.has_tool_content)
    eq(true, result.has_truncation) -- Should be truncated due to length
    eq(true, result.prompt_not_too_long)
end

T["Edge Cases"]["handles mixed visible and invisible messages"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil

        -- Mock chat with mix of visible and invisible messages
        local chat = {
            opts = {
                save_id = "test_mixed_visibility",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = "Visible user message 1",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Invisible user message",
                    opts = { visible = false }
                },
                {
                    role = "llm",
                    content = "Visible LLM response",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Invisible LLM response",
                    opts = { visible = false }
                },
                {
                    role = "user",
                    content = "Visible user message 2",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local user_prompt = test_summary_gen.last_user_prompt or ""

        return {
            completed = completed,
            has_visible_user = user_prompt:find("Visible user message") ~= nil,
            has_invisible_user = user_prompt:find("Invisible user message") ~= nil,
            has_visible_llm = user_prompt:find("Visible LLM response") ~= nil,
            has_invisible_llm = user_prompt:find("Invisible LLM response") ~= nil
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_visible_user) -- Should include visible user messages
    eq(false, result.has_invisible_user) -- Should exclude invisible user messages
    eq(true, result.has_visible_llm) -- Should include visible LLM responses
    eq(false, result.has_invisible_llm) -- Should exclude invisible LLM responses
end

T["Edge Cases"]["handles messages with nil or empty content"] = function()
    local result = child.lua([[              
        local completed = false
        local generated_summary = nil

        -- Mock chat with nil/empty content
        local chat = {
            opts = {
                save_id = "test_nil_content",
                title = "Test Chat"
            },
            messages = {
                {
                    role = "user",
                    content = nil, -- nil content
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "", -- empty content
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Valid message",
                    opts = { visible = true }
                },
                {
                    role = "llm",
                    content = "Response",
                    opts = { visible = true }
                },
                {
                    role = "user",
                    content = "Another valid message",
                    opts = { visible = true }
                }
            }
        }

        -- Generate summary
        test_summary_gen:generate(chat, function(summary, error)
            generated_summary = summary
            completed = true
        end)

        -- Wait for completion
        vim.wait(1000, function() return completed end)

        local user_prompt = test_summary_gen.last_user_prompt or ""

        return {
            completed = completed,
            has_summary = generated_summary ~= nil,
            has_valid_content = user_prompt:find("Valid message") ~= nil,
            doesnt_have_empty = user_prompt:find("^User: $") == nil -- No empty user messages
        }
    ]])

    eq(true, result.completed)
    eq(true, result.has_summary)
    eq(true, result.has_valid_content)
    eq(true, result.doesnt_have_empty)
end

return T
