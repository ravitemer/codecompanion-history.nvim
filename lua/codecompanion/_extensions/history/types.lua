---@meta CodeCompanion.Extension

---@alias CodeCompanion.History.Pickers "telescope" | "snacks" | "fzf-lua" |  "default"

---@class CodeCompanion.History.GenOpts
---@field adapter? string? The adapter to use for generation
---@field model? string? The model of the adapter to use for generation
---@field refresh_every_n_prompts? number Number of user prompts after which to refresh the title (0 to disable)
---@field max_refreshes? number Maximum number of times to refresh the title (default: 3)
---@field format_title? fun(original_title: string):string a function that applies a custom transformation to the title.

---@class CodeCompanion.History.SummaryOpts
---@field create_summary_keymap? string | table Keymap to generate summary for current chat (default: "gcs")
---@field browse_summaries_keymap? string | table Keymap to browse saved summaries (default: "gbs")
---@field generation_opts? CodeCompanion.History.SummaryGenerationOpts Options for summary generation

--- The tool-call arguments provided by the LLM
---@class CodeCompanion.History.MemoryTool.Args
---@field keywords string[]
---@field count integer

--- The tool options specified by the user
---@class CodeCompanion.History.MemoryTool.Opts
---@field default_num integer

---@class CodeCompanion.History.MemoryOpts
---@field auto_create_memories_on_summary_generation boolean Should vectorize summaries as they are created
---@field vectorcode_exe string VectorCode executable
---@field tool_opts CodeCompanion.History.MemoryTool.Opts
---@field notify boolean whether to enable notification
---@field index_on_startup boolean whether to perform indexing when this plugin is loaded.

---@class CodeCompanion.History.Opts
---@field default_buf_title? string A name for the chat buffer that tells that this is an auto saving chat
---@field auto_generate_title? boolean  Generate title for the chat
---@field title_generation_opts? CodeCompanion.History.GenOpts Options for title generation
---@field continue_last_chat? boolean On exiting and entering neovim, loads the last chat on opening chat
---@field delete_on_clearing_chat? boolean When chat is cleared with `gx` delete the chat from history
---@field keymap? string | table Keymap to open saved chats from the chat buffer
---@field keymap_description? string Description for the history keymap (for which-key integration)
---@field picker? CodeCompanion.History.Pickers Picker to use (telescope, etc.)
---@field enable_logging? boolean Enable logging for history extension
---@field auto_save? boolean Automatically save the chat whenever it is updated
---@field save_chat_keymap? string | table Keymap to save the current chat
---@field save_chat_keymap_description? string Description for the save chat keymap (for which-key integration)
---@field expiration_days? number Number of days after which chats are automatically deleted (0 to disable)
---@field summary? CodeCompanion.History.SummaryOpts Summary-related options
---@field memory? CodeCompanion.History.MemoryOpts
---@field picker_keymaps? {rename?: table, delete?: table, duplicate?: table}
---@field chat_filter? fun(chat_data: CodeCompanion.History.ChatIndexData): boolean Filter function for browsing chats

---@class CodeCompanion.History.ChatMessage
---@field role string
---@field content string
---@field tool_calls table
---@field opts? {visible?: boolean, tag?: string}

---@class CodeCompanion.History.ChatData
---@field save_id string
---@field title? string
---@field messages CodeCompanion.History.ChatMessage[]
---@field updated_at number
---@field settings table
---@field adapter string
---@field refs? table -- Deprecated: for backward compatibility with old chats
---@field context_items? table -- New: replaces refs
---@field schemas? table
---@field in_use? table
---@field name? string
---@field cycle number
---@field title_refresh_count? number
---@field cwd string Current working directory when chat was saved
---@field project_root string Project root directory when chat was saved

---@class CodeCompanion.History.ChatIndexData
---@field title string
---@field updated_at number
---@field save_id string
---@field model string
---@field adapter string
---@field message_count number
---@field token_estimate number
---@field cwd string Current working directory when chat was saved
---@field project_root string Project root directory when chat was saved

---@class CodeCompanion.History.SummaryGenerationOpts
---@field adapter? string The adapter to use for summary generation
---@field model? string The model of the adapter to use for summary generation
---@field context_size? number Maximum tokens to use for summarization context (default: 90000)
---@field include_references? boolean Include user messages with references (slash commands, variables) (default: true)
---@field include_tool_outputs? boolean Include tool execution results in summary context (default: true)
---@field system_prompt? string|fun(): string Custom system prompt for summarization (can be a string or function)
---@field format_summary? fun(summary: string): string Custom function to format the summary before saving e.g to remove <think/> tags

---@class CodeCompanion.History.UIHandlers
---@field on_preview fun(chat_data: CodeCompanion.History.EntryItem): string[]
---@field on_delete fun(chat_data: CodeCompanion.History.EntryItem|CodeCompanion.History.EntryItem[]): nil
---@field on_select fun(chat_data: CodeCompanion.History.EntryItem): nil
---@field on_open fun(): nil
---@field on_rename fun(chat_data: CodeCompanion.History.EntryItem): nil
---@field on_duplicate? fun(chat_data: CodeCompanion.History.EntryItem): nil

---@class CodeCompanion.History.SummaryData
---@field summary_id string
---@field chat_id string
---@field generated_at number
---@field chat_title? string
---@field content string
---@field project_root? string
---@field path string?

---@class CodeCompanion.History.SummaryIndexData
---@field summary_id string
---@field chat_id string
---@field chat_title? string
---@field generated_at number
---@field project_root? string

---@class CodeCompanion.History.EntryItem : CodeCompanion.History.ChatIndexData, CodeCompanion.History.SummaryIndexData
---@field name string Display name for the item
---@field has_summary boolean Flag indicating if the item has an associated summary (for chats only)

---@class CodeCompanion.History.BufferInfo
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
---@field line_count number

---@class CodeCompanion.History.EditorInfo
---@field last_active CodeCompanion.History.BufferInfo|nil
---@field buffers CodeCompanion.History.BufferInfo[]
