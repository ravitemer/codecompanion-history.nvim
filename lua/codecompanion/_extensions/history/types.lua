---@meta CodeCompanion.Extension
---
---@class CodeCompanion.Extension
---@field setup fun(opts: table): any Function called when extension is loaded
---@field exports? table Optional table of functions exposed via codecompanion.extensions.name

---@class HistoryOpts
---@field default_buf_title? string A name for the chat buffer that tells that this is an auto saving chat
---@field auto_generate_title? boolean Generate title for the chat
---@field continue_last_chat? boolean On exiting and entering neovim, loads the last chat on opening chat
---@field delete_on_clearing_chat? boolean When chat is cleared with `gx` delete the chat from history
---@field keymap? string | table Keymap to open saved chats from the chat buffer
---@field picker? Pickers Picker to use (telescope, etc.)
---@field enable_logging? boolean Enable logging for history extension
---@field auto_save? boolean Automatically save the chat whenever it is updated
---@field save_chat_keymap? string | table Keymap to save the current chat
---@field expiration_days? number Number of days after which chats are automatically deleted (0 to disable)
---@field picker_keymaps? {rename?: table, delete?: table}

---@class Chat
---@field opts {title:string, save_id: string}
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
---

---@class ChatIndexData
---@field title string
---@field updated_at number
---@field save_id string
---@field model string
---@field adapter string
---@field message_count number
---@field token_estimate number

---@class UIHandlers
---@field on_preview fun(chat_data: ChatData): string[]
---@field on_delete fun(chat_data: ChatData):nil
---@field on_select fun(chat_data: ChatData):nil
---@field on_open fun():nil
---@field on_rename fun(chat_data: ChatData, new_title:string): nil

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
