---@meta CodeCompanion.Extension
---
---@class CodeCompanion.Extension
---@field setup fun(opts: table): any Function called when extension is loaded
---@field exports? table Optional table of functions exposed via codecompanion.extensions.name

---@alias Pickers "telescope" | "snacks" | "fzf-lua" |  "default"

---@class GenOpts
---@field adapter? string? The adapter to use for generation
---@field model? string? The model of the adapter to use for generation
---@field refresh_every_n_prompts? number Number of user prompts after which to refresh the title (0 to disable)
---@field max_refreshes? number Maximum number of times to refresh the title (default: 3)

---@class SummaryOpts
---@field create_summary_keymap? string | table Keymap to generate summary for current chat (default: "gcs")
---@field browse_summaries_keymap? string | table Keymap to browse saved summaries (default: "gbs")
---@field preview_summary_keymap? string | table Keymap to preview/edit summary (default: "gps")
---@field generation_opts? SummaryGenerationOpts Options for summary generation

--- The tool-call arguments provided by the LLM
---@class CodeCompanion.History.MemoryTool.Args
---@field keywords string[]
---@field count integer

--- The tool options specified by the user
---@class CodeCompanion.History.MemoryTool.Opts
---@field default_num integer

---@class MemoryOpts
---@field auto_create_memories_on_summary_generation boolean Should vectorize summaries as they are created
---@field vectorcode_exe string VectorCode executable
---@field tool_opts CodeCompanion.History.MemoryTool.Opts

---@class HistoryOpts
---@field default_buf_title? string A name for the chat buffer that tells that this is an auto saving chat
---@field auto_generate_title? boolean  Generate title for the chat
---@field title_generation_opts? GenOpts Options for title generation
---@field continue_last_chat? boolean On exiting and entering neovim, loads the last chat on opening chat
---@field delete_on_clearing_chat? boolean When chat is cleared with `gx` delete the chat from history
---@field keymap? string | table Keymap to open saved chats from the chat buffer
---@field picker? Pickers Picker to use (telescope, etc.)
---@field enable_logging? boolean Enable logging for history extension
---@field auto_save? boolean Automatically save the chat whenever it is updated
---@field save_chat_keymap? string | table Keymap to save the current chat
---@field expiration_days? number Number of days after which chats are automatically deleted (0 to disable)
---@field picker_keymaps? {rename?: table, delete?: table}
---@field summary? SummaryOpts Summary-related options
---@field memory? MemoryOpts

---@class Chat
---@field opts {title:string, title_refresh_count?: number, save_id: string}
---@field messages ChatMessage[]
---@field id number
---@field bufnr number
---@field settings table
---@field adapter table
---@field refs table
---@field tools {schemas: table, in_use: table}
---@field references table
---@field subscribers {subscribe: function}
---@field ui {is_active: function, hide: function, open: function}
---@field cycle number

---@class ChatMessage
---@field role string
---@field content string
---@field tool_calls table
---@field opts? {visible?: boolean, tag?: string}

---@class ChatData
---@field save_id string
---@field title? string
---@field messages ChatMessage[]
---@field updated_at number
---@field settings table
---@field adapter string
---@field refs? table
---@field schemas? table
---@field in_use? table
---@field name? string
---@field cycle number
---@field title_refresh_count? number
---

---@class ChatIndexData
---@field title string
---@field updated_at number
---@field save_id string
---@field model string
---@field adapter string
---@field message_count number
---@field token_estimate number

---@class SummaryGenerationOpts
---@field adapter? string The adapter to use for summary generation
---@field model? string The model of the adapter to use for summary generation
---@field context_size? number Maximum tokens to use for summarization context (default: 90000)
---@field include_references? boolean Include user messages with references (slash commands, variables) (default: true)
---@field include_tool_outputs? boolean Include tool execution results in summary context (default: true)
---@field system_prompt? string|fun(): string Custom system prompt for summarization (can be a string or function)

---@class SummaryData
---@field summary_id string
---@field chat_id string
---@field generated_at number
---@field content string
---@field project_root? string
---@field path string?

---@class SummaryIndexData
---@field summary_id string
---@field chat_id string
---@field chat_title? string
---@field generated_at number
---@field project_root? string

---@class EntryItem : ChatIndexData, SummaryIndexData
---@field name string Display name for the item
---@field has_summary boolean Flag indicating if the item has an associated summary (for chats only)

---@class UIHandlers
---@field on_preview fun(entry:EntryItem): string[]
---@field on_delete fun(entry: EntryItem):nil
---@field on_select fun(entry: EntryItem):nil
---@field on_open fun():nil
---@field on_rename fun(entry: EntryItem, new_title:string): nil

---@class BufferInfo
---@field bufnr number
---@field name string
---@field filename string
---@field is_visible boolean
---@field is_modified boolean
---@field is_loaded boolean
---@field lastused number
---@field windows number[]
---@field winnr number
---@field cursor_pos? number[]

---@class EditorInfo
---@field last_active BufferInfo|nil
---@field buffers BufferInfo[]

return {}
