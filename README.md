<!-- panvimdoc-ignore-start -->

# CodeCompanion History Extension (Simplified)

[![Neovim](https://img.shields.io/badge/Neovim-57A143?style=flat-square&logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white)](https://www.lua.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A simplified history management extension for [codecompanion.nvim](https://codecompanion.olimorris.dev/) that enables saving, browsing and restoring chat sessions on-demand.

<!-- panvimdoc-ignore-end -->

## ✨ Features

### 🤖 Chat Management
- 💾 **On-demand chat saving** - Save chats manually with `sc` keymap, no automatic saving
- 🎯 **Random title generation** - Chats get unique random titles automatically
- 🔄 **Resume previous conversations** - Load any saved chat with full context
- 📚 **Browse saved chats** - Built-in picker with preview functionality
- 🔍 **Multiple picker interfaces** - Support for telescope, snacks, fzf-lua, and default picker
- ⌛ **Optional chat expiration** - Auto-delete chats older than specified days
- ⚡ **Full state restoration** - Messages, tools, references, adapter settings all preserved
- 🏢 **Project-aware filtering** - Filter chats by working directory or project context
- 📋 **Chat duplication** - Easily duplicate chats to create variations

## 📋 Requirements

- Neovim >= 0.8.0
- [codecompanion.nvim](https://codecompanion.olimorris.dev/)
- [snacks.nvim](https://github.com/folke/snacks.nvim) (optional, for enhanced picker)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for enhanced picker)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (optional, for enhanced picker)

## 📦 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "olimorris/codecompanion.nvim",
    dependencies = {
        --other plugins
        "ravitemer/codecompanion-history.nvim"
    }
}
```

Add history extension to CodeCompanion config:

```lua
require("codecompanion").setup({
    extensions = {
        history = {
            enabled = true,
            opts = {
                -- Keymap to open history from chat buffer (default: gh)
                keymap = "gh",
                -- Keymap to save the current chat manually
                save_chat_keymap = "sc",
                -- Number of days after which chats are automatically deleted (0 to disable)
                expiration_days = 0,
                -- Picker interface (auto resolved to a valid picker)
                picker = "telescope", --- ("telescope", "snacks", "fzf-lua", or "default") 
                ---Optional filter function to control which chats are shown when browsing
                chat_filter = nil, -- function(chat_data) return boolean end
                -- Customize picker keymaps (optional)
                picker_keymaps = {
                    rename = { n = "r", i = "<M-r>" },
                    delete = { n = "d", i = "<M-d>" },
                    duplicate = { n = "<C-y>", i = "<C-y>" },
                },
                ---On exiting and entering neovim, loads the last chat on opening chat
                continue_last_chat = false,
                ---When chat is cleared with `gx` delete the chat from history
                delete_on_clearing_chat = false,
                ---Directory path to save the chats
                dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history",
                ---Enable detailed logging for history extension
                enable_logging = false,
            }
        }
    }
})
```

## 🛠️ Usage

### 🎯 Commands

- `:CodeCompanionHistory` - Open the history browser

### ⌨️ Chat Buffer Keymaps

**History Management:**
- `gh` - Open history browser (customizable via `opts.keymap`)
- `sc` - Save current chat manually (customizable via `opts.save_chat_keymap`)

### 📚 History Browser

The history browser shows all your saved chats with:
- Title (randomly generated or custom)
- Adapter and model used
- Message count and token estimates
- Last updated timestamp
- Full chat preview

**Browser Actions:**
- `<CR>` - Open/restore selected chat
- Normal mode:
  - `d` - Delete selected chat(s)
  - `r` - Rename selected chat
  - `<C-y>` - Duplicate selected chat
- Insert mode:
  - `<M-d>` (Alt+d) - Delete selected chat(s)
  - `<M-r>` (Alt+r) - Rename selected chat
  - `<C-y>` - Duplicate selected chat

## 🏢 Project-Aware Chat Filtering

You can filter chats to show only those relevant to your current project:

```lua
-- Show only chats from current working directory
chat_filter = function(chat_data)
    return chat_data.cwd == vim.fn.getcwd()
end

-- Show only recent chats (last 7 days)
chat_filter = function(chat_data)
    local seven_days_ago = os.time() - (7 * 24 * 60 * 60)
    return chat_data.updated_at >= seven_days_ago
end
```

### Chat Index Data Structure

Each chat's metadata (used in filtering) includes:

```lua
{
    save_id = "1672531200",                 -- Unique chat identifier
    title = "Debug API endpoint",           -- Chat title
    cwd = "/home/user/my-project",         -- Working directory when saved
    project_root = "/home/user/my-project", -- Detected project root
    adapter = "openai",                     -- LLM adapter used
    model = "gpt-4",                        -- Model name
    updated_at = 1672531200,                -- Unix timestamp
    message_count = 15,                     -- Number of messages
    token_estimate = 3420,                  -- Estimated token count
}
```

## 🔧 API

The history extension exports the following functions via `require("codecompanion").extensions.history`:

```lua
-- Get storage location
get_location(): string?

-- Save a chat (uses last chat if none provided)
save_chat(chat?: CodeCompanion.Chat)

-- Browse chats with optional filter
browse_chats(filter_fn?: function(ChatIndexData): boolean)

-- Get all chats metadata with optional filter
get_chats(filter_fn?: function(ChatIndexData): boolean): table<string, ChatIndexData>

-- Load a specific chat by save_id
load_chat(save_id: string): ChatData?

-- Delete a chat by save_id
delete_chat(save_id: string): boolean

-- Duplicate a chat
duplicate_chat(save_id: string, new_title?: string): string?
```

### Example Usage

```lua
local history = require("codecompanion").extensions.history

-- Browse chats from current project only
history.browse_chats(function(chat_data)
    return chat_data.cwd == vim.fn.getcwd()
end)

-- Get all chats metadata
local chats = history.get_chats()

-- Load a specific chat
local chat_data = history.load_chat("1672531200")

-- Delete a chat
history.delete_chat("1672531200")

-- Duplicate with custom title
local new_id = history.duplicate_chat("1672531200", "My Custom Copy")
```

## ⚙️ How It Works

**When you create a new chat:**
1. The extension assigns a unique save ID (timestamp)
2. A random title is generated for the chat

**Manual Saving:**
- Press `sc` in chat buffer to save at any time
- All messages, tools, adapters, and references are stored
- Prevents data loss and allows chat resumption

**Browsing & Restoring:**
1. Open history with `gh` or `:CodeCompanionHistory`
2. Preview chats in the picker
3. Select a chat to restore it completely with full context

**Chat Expiration (Optional):**
- If configured, chats older than `expiration_days` are automatically deleted on startup
- Keeps your history clean without manual maintenance

## Preserved Chat Features

When saving and restoring chats, the following CodeCompanion features are preserved:

| Feature | Status | Notes |
|---------|--------|-------|
| System Prompts | ✅ | Original system prompt restored |
| Messages History | ✅ | Complete message history |
| LLM Adapter | ✅ | Specific adapter used in chat |
| LLM Settings | ✅ | Model, temperature, other settings |
| Tools | ✅ | Tool schemas and configurations |
| Tool Outputs | ✅ | Results from tool executions |
| References | ✅ | Code snippets and command outputs |
| Variables | ✅ | Variables used in chat |

## 📄 License

MIT
