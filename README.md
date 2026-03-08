# silver-lining.nvim

Every cloud has a silver lining — and every code review has one too.

**silver-lining.nvim** brings GitHub PR review comments straight into your nvim. Cloud or Claude...

## Features

- Auto-detects repo and PR number from your current branch and fetch PR review comments from GitHub using `gh` CLI
- Browse comments in a Telescope picker with severity, file path, and preview
- Inline virtual text showing reviewer comments and code suggestions
- Accept or dismiss suggestions with a single keypress
- Side-by-side diff view for suggested changes
- Native diagnostics integration

## Requirements

- Neovim >= 0.9
- [gh](https://cli.github.com/) CLI (authenticated)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for the picker UI)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "thadmfinnick/silver-lining.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim", -- optional, for picker UI
  },
  config = function()
    require("silver-lining").setup()
    -- If you have telescope installed:
    require("telescope").load_extension("silver-lining")
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "thadmfinnick/silver-lining.nvim",
  requires = { "nvim-telescope/telescope.nvim" }, -- optional
  config = function()
    require("silver-lining").setup()
    require("telescope").load_extension("silver-lining")
  end,
}
```

Without Telescope, you can use `require("silver-lining").load_review()` directly — comments will be loaded into the quickfix list.

## Configuration

```lua
require("silver-lining").setup({
  -- GitHub repo in "owner/repo" format (auto-detects if omitted)
  repo = nil,
  -- Buffer-local keymaps (set to false to disable all)
  keymaps = {
    accept = "<leader>sa",
    dismiss = "<leader>sx",
    diff = "<leader>sd",
    accept_all = "<leader>sA",
    dismiss_all = "<leader>sX",
    next_comment = "]r",
    prev_comment = "[r",
  },
})
```

Set individual keys to `false` to disable them, or set `keymaps = false` to disable all keymaps and define your own.

## Usage

### Commands

| Command | Description |
|---|---|
| `:SilverLining` | Fetch review comments for the current branch's PR and open Telescope picker |
| `:SilverLining 42` | Fetch review comments for PR #42 |
| `:SilverLiningClear` | Clear all inline suggestions and diagnostics |

### Keymaps

Once review comments are loaded and you select a file from the Telescope picker, the following buffer-local keymaps are available (all configurable):

| Key | Description |
|---|---|
| `<leader>sa` | Accept suggestion under cursor |
| `<leader>sx` | Dismiss comment under cursor |
| `<leader>sd` | Open side-by-side diff view |
| `<leader>sA` | Accept all suggestions in buffer |
| `<leader>sX` | Dismiss all comments in buffer |
| `]r` | Jump to next review comment |
| `[r` | Jump to previous review comment |

In the diff view:

| Key | Description |
|---|---|
| `<leader>sa` | Accept suggestion and close diff |
| `q` / `<Esc>` | Close diff view |

## How it works

1. Run `:SilverLining` — the plugin calls the GitHub API via `gh` to fetch PR review comments
2. Comments are parsed, categorized by severity, and presented in a Telescope picker
3. Select a comment to jump to the file — inline virtual text and diagnostics appear on the relevant lines
4. Review the suggestion, then accept it to apply the change or dismiss it to move on
