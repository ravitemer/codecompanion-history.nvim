# CodeCompanion History Extension

[![Neovim](https://img.shields.io/badge/Neovim-57A143?style=flat-square&logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-2C2D72?style=flat-square&logo=lua&logoColor=white)](https://www.lua.org)
[![Tests](https://github.com/ravitemer/codecompanion-history.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/ravitemer/codecompanion-history.nvim/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](./CONTRIBUTING.md)

A history management extension for [codecompanion.nvim](https://codecompanion.olimorris.dev/) that enables saving, browsing and restoring chat sessions.


<p>
    <video controls muted src="https://github.com/user-attachments/assets/04a6ad1f-8351-4381-ae60-00c352a1670c"></video>
</p>

## ✨ Features

- 💾 Flexible chat saving:
  - Automatic session saving (can be disabled)
  - Manual save with dedicated keymap
- 🎯 Smart title generation for chats
- 🔄 Continue from where you left
- 📚 Browse saved chats with preview
- 🔍 Multiple picker interfaces
- ⌛ Optional automatic chat expiration
- ⚡ Restore chat sessions with full context and tools state

The following CodeCompanion features are preserved when saving and restoring chats:

| Feature | Status | Notes |
|---------|--------|-------|
|  System Prompts | ✅  | System prompt used in the chat |
|  Messages History | ✅  | All messages |
|  Images | ✅  | Restores images as base64 strings |
|  LLM Adapter | ✅  | The specific adapter used for the chat |
|  LLM Settings | ✅  | Model, temperature and other adapter settings |
|  Tools | ✅  | Tool schemas and their system prompts |
|  Tool Outputs | ✅  | Tool execution results |
|  Variables | ✅  | Variables used in the chat |
|  References | ✅  | Code snippets and command outputs added via slash commands |
|  Pinned References | ✅  | Pinned references |
|  Watchers | ⚠  | Saved but requires original buffer context to resume watching |

When restoring a chat:
1. The complete message history is recreated
2. All tools and references are reinitialized
3. Original LLM settings and adapter are restored
4. Previous system prompts are preserved

> **Note**: While watched buffer states are saved, they require the original buffer context to resume watching functionality.

> [!NOTE]
> As this is an extension that deeply integrates with CodeCompanion's internal APIs, occasional compatibility issues may arise when CodeCompanion updates. If you encounter any bugs or unexpected behavior, please [raise an issue](https://github.com/ravitemer/codecompanion-history.nvim/issues) to help us maintain compatibility.

## 📋 Requirements

- Neovim >= 0.8.0
- [codecompanion.nvim](https://codecompanion.olimorris.dev/)
- [snacks.nvim](https://github.com/folke/snacks.nvim) (optional, for enhanced picker)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for enhanced picker)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua) (optional, for enhanced picker)

## 📦 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

### First install the plugin

```lua
{
    "olimorris/codecompanion.nvim",
    dependencies = {
        --other plugins
        "ravitemer/codecompanion-history.nvim"
    }
}
```

### Add history extension to CodeCompanion config

```lua
require("codecompanion").setup({
    extensions = {
        history = {
            enabled = true,
            opts = {
                -- Keymap to open history from chat buffer (default: gh)
                keymap = "gh",
                -- Keymap to save the current chat manually (when auto_save is disabled)
                save_chat_keymap = "sc",
                -- Save all chats by default (disable to save only manually using 'sc')
                auto_save = true,
                -- Number of days after which chats are automatically deleted (0 to disable)
                expiration_days = 0,
                -- Picker interface (auto resolved to a valid picker)
                picker = "telescope", --- ("telescope", "snacks", "fzf-lua", or "default") 
                ---Automatically generate titles for new chats
                auto_generate_title = true,
                title_generation_opts = {
                    ---Adapter for generating titles (defaults to current chat adapter) 
                    adapter = nil, -- "copilot"
                    ---Model for generating titles (defaults to current chat model)
                    model = nil, -- "gpt-4o"
                    ---Number of user prompts after which to refresh the title (0 to disable)
                    refresh_every_n_prompts = 0, -- e.g., 3 to refresh after every 3rd user prompt
                    ---Maximum number of times to refresh the title (default: 3)
                    max_refreshes = 3,
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

#### 🎯 Commands

- `:CodeCompanionHistory` - Open the history browser


#### ⌨️ Chat Buffer Keymaps

- `gh` - Open history browser (customizable via `opts.keymap`)
- `sc` - Save current chat manually (customizable via `opts.save_chat_keymap`)

#### 📚 History Browser

The history browser shows all your saved chats with:
- Title (auto-generated or custom)
- Last updated time
- Preview of chat contents

Actions in history browser:
- `<CR>` - Open selected chat
- Normal mode:
  - `d` - Delete selected chat(s)
  - `r` - Rename selected chat
- Insert mode:
  - `<M-d>` (Alt+d) - Delete selected chat(s)
  - `<M-r>` (Alt+r) - Rename selected chat

> Note: Delete and rename actions are only available in telescope and snacks pickers. Multiple chats can be selected for deletion using picker's multi-select feature (press `<Tab>`).

#### 🔄 Title Refresh Feature

The extension can automatically refresh chat titles as conversations evolve:

- **`refresh_every_n_prompts`**: Set to refresh the title after every N user prompts (e.g., 3 means refresh after the 3rd, 6th, 9th user message)
- **`max_refreshes`**: Limits how many times a title can be refreshed to avoid excessive API calls
- When refreshing, the system considers recent conversation context (both user and assistant messages) and the original title
- Individual messages are truncated at 1000 characters with a `[truncated]` indicator
- Total conversation context is limited to 10,000 characters with a `[conversation truncated]` indicator

Example configuration for title refresh:
```lua
title_generation_opts = {
    refresh_every_n_prompts = 3, -- Refresh after every 3rd user prompt
    max_refreshes = 10,           -- Allow up to 10 refreshes per chat
}
```

#### 🔧 API

The history extension exports the following functions that can be accessed via `require("codecompanion").extensions.history`:

```lua
-- Get the storage location for saved chats
get_location(): string?

-- Save a chat to storage (uses last chat if none provided)
save_chat(chat?: CodeCompanion.Chat)

-- Get metadata for all saved chats
get_chats(): table<string, ChatIndexData>

-- Load a specific chat by its save_id
load_chat(save_id: string): ChatData?

-- Delete a chat by its save_id
delete_chat(save_id: string): boolean
```

Example usage:
```lua
local history = require("codecompanion").extensions.history

-- Get all saved chats metadata
local chats = history.get_chats()

-- Load a specific chat
local chat_data = history.load_chat("some_save_id")

-- Delete a chat
history.delete_chat("some_save_id")
```

## ⚙️ How It Works


```mermaid
graph TD
    subgraph CodeCompanion Core Lifecycle
        A[CodeCompanionChatCreated Event] --> B{Chat Submitted};
        B --> C[LLM Response Received];
        subgraph Chat End
            direction RL
            D[CodeCompanionChatCleared Event];
        end
        C --> D;
        B --> D;
    end

    subgraph Extension Integration
        A -- Extension Hooks --> E[Init & Subscribe];
        E --> F[Setup Auto-Save];
        F --> G[Prepare Auto-Title];

        C -- Extension Hooks --> H[Subscriber Triggered];
        H --> H1{Auto-Save Enabled?};
        H1 -- Yes --> I[Save Chat State - Messages, Tools, Refs];
        H1 -- No --> H2[Manual Save via `sc`];
        H2 --> I;
        I --> J{No Title & Auto-Title Enabled?};
        J -- Yes --> K[Generate Title];
        K --> L[Update Buffer Title];
        L --> M[Save Chat with New Title];
        J -- No --> B;
        M --> B;

        D -- Extension Hooks --> N[Respond to Clear Event];
        N --> O[Delete Chat from Storage];
        O --> P[Reset Extension State - Title/ID];
    end

    subgraph User History Interaction
        Q[User Action - gh / :CodeCompanionHistory] --> R{History Browser};
        R -- Restore --> S[Load Chat State from Storage];
        S --> A;
        R -- Delete --> O;
    end
```

Here's what's happening in simple terms:

1. When you create a new chat, our extension jumps in and sets up two things:
   - An autosave system that will save your chat
   - A title generator that will name your chat based on the conversation

2. As you chat:
   - When auto-save is enabled (default):
     - Each submitted message triggers automatic saving
     - Every LLM response automatically saves the chat state
   - Manual saving is available via the `sc` keymap
   - If your chat doesn't have a title yet, it tries to create one that makes sense
   - All your messages, tools, and references are safely stored

3. When you clear a chat:
   - Our extension knows to remove it from storage (if configured)
   - This keeps your history clean and organized

4. Any time you want to look at old chats:
   - Use `gh` or the command to open the history browser
   - Pick any chat to restore it completely
   - Or remove ones you don't need anymore

<details>
    <summary> Technical details </summary>

The extension integrates with CodeCompanion through a robust event-driven architecture:

1. **Initialization and Storage Management**:
   - Uses a dedicated Storage class to manage chat persistence in `{data_path}/codecompanion-history/`
   - Maintains an index.json for metadata and individual JSON files for each chat
   - Implements file I/O operations with error handling and atomic writes

2. **Chat Lifecycle Integration**:
   - Hooks into `CodeCompanionChatCreated` event to:
     - Generate unique save_id (Unix timestamp)
     - Initialize chat subscribers for auto-saving
     - Set initial buffer title with sparkle icon (✨)

   - Monitors `CodeCompanionChatSubmitted` events to:
     - Persist complete chat state including messages, tools, schemas, and references
     - Trigger title generation if enabled and title is empty
     - Update buffer title with relative timestamps

3. **Title Generation System**:
   - Uses the chat's configured LLM adapter for title generation
   - Implements smart content truncation (1000 chars) and prompt engineering
   - Handles title collisions with automatic numbering
   - Updates titles asynchronously using vim.schedule

4. **State Management**:
   - Preserves complete chat context including:
     - Message history with role-based organization
     - Tool states and schemas
     - Reference management
     - Adapter configurations
     - Custom settings

5. **UI Components**:
   - Implements multiple picker interfaces (telescope/snacks/default)
   - Provides real-time preview generation with markdown formatting
   - Supports justified text layout for buffer titles
   - Handles window/buffer lifecycle management

6. **Data Flow**:
   - Chat data follows a structured schema (ChatData)
   - Implements proper serialization/deserialization
   - Maintains backward compatibility with existing chats
   - Provides error handling for corrupt or missing data

</details>

## 📝 TODOs

- [x] Add support for additional pickers like snacks, fzf etc

## 🔌 Related Extensions

- [MCP Hub](https://codecompanion.olimorris.dev/extensions/mcphub.html) extension
- [VectorCode](https://codecompanion.olimorris.dev/extensions/vectorcode.html) extension

## 🙏 Acknowledgements

Special thanks to [Oli Morris](https://github.com/olimorris) for creating the amazing [CodeCompanion.nvim](https://codecompanion.olimorris.dev) plugin - a highly configurable and powerful coding assistant for Neovim.

## 📄 License

MIT

