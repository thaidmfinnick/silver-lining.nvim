# silver-lining.nvim

Every cloud has a silver lining — and every code review has one too.

**silver-lining.nvim** brings GitHub PR review comments straight into your Neovim — and lets you write reviews without ever leaving the editor. Cloud or Claude...

## Features

- Auto-detects repo and PR number from your current branch
- Fetches only **unresolved** review threads from GitHub using `gh` CLI
- Browse comments in a Telescope picker with severity, file path, and preview
- Inline virtual text showing reviewer comments and code suggestions
- Accept or dismiss suggestions with a single keypress
- Side-by-side diff view for suggested changes
- Native diagnostics integration
- **Draft comments and suggestions** from selected lines in a floating editor
- **Toggle between comment and suggestion mode** inside the float
- **Browse, edit, and delete drafts** via a Telescope picker
- **Submit all drafts as a GitHub review** (comment, approve, or request changes)

## Requirements

- Neovim >= 0.9
- [gh](https://cli.github.com/) CLI (authenticated)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for picker UI)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "thaidmfinnick/silver-lining.nvim",
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
  "thaidmfinnick/silver-lining.nvim",
  requires = { "nvim-telescope/telescope.nvim" }, -- optional
  config = function()
    require("silver-lining").setup()
    require("telescope").load_extension("silver-lining")
  end,
}
```

Without Telescope, comments are loaded into the quickfix list instead of the picker.

## Configuration

```lua
require("silver-lining").setup({
  -- GitHub repo in "owner/repo" format (auto-detects if omitted)
  repo = nil,
  -- Buffer-local keymaps (set to false to disable all)
  keymaps = {
    accept = "<leader>sa",       -- Accept suggestion under cursor
    dismiss = "<leader>sx",      -- Dismiss comment under cursor
    diff = "<leader>sd",         -- Open side-by-side diff view
    accept_all = "<leader>sA",   -- Accept all suggestions in buffer
    dismiss_all = "<leader>sX",  -- Dismiss all comments in buffer
    next_comment = "]r",         -- Jump to next review comment
    prev_comment = "[r",         -- Jump to previous review comment
    comment = "<leader>sc",      -- Open comment float on selected lines
    suggestion = "<leader>ss",   -- Open suggestion float on selected lines
  },
})
```

Set individual keys to `false` to disable them, or set `keymaps = false` to disable all keymaps and define your own.

## Usage

### Reading Reviews

| Command | Description |
|---|---|
| `:SilverLining` | Fetch review comments for the current branch's PR and open Telescope picker |
| `:SilverLining 42` | Fetch review comments for PR #42 |
| `:SilverLiningClear` | Clear all inline suggestions and diagnostics |

Once review comments are loaded and you select a file from the Telescope picker, the following buffer-local keymaps are available:

| Key | Action |
|---|---|
| `<leader>sa` | Accept suggestion under cursor |
| `<leader>sx` | Dismiss comment under cursor |
| `<leader>sd` | Open side-by-side diff view |
| `<leader>sA` | Accept all suggestions in buffer |
| `<leader>sX` | Dismiss all comments in buffer |
| `]r` | Jump to next review comment |
| `[r` | Jump to previous review comment |

In the diff view:

| Key | Action |
|---|---|
| `<leader>sa` | Accept suggestion and close diff |
| `q` / `<Esc>` | Close diff view |

### Writing Reviews

Select lines in visual mode, then use one of these commands to open a floating editor:

| Command | Description |
|---|---|
| `:SilverLiningComment` | Draft a comment on the selected lines |
| `:SilverLiningSuggestion` | Draft a code suggestion on the selected lines |
| `:SilverLiningDrafts` | Browse and manage pending drafts (Telescope) |
| `:SilverLiningSubmit` | Submit all drafts as a review (defaults to `COMMENT`) |
| `:SilverLiningSubmit APPROVE` | Submit drafts and approve the PR |
| `:SilverLiningSubmit REQUEST_CHANGES` | Submit drafts and request changes |

Inside the comment/suggestion float:

| Key | Action |
|---|---|
| `<C-s>` | Save the current draft |
| `<C-t>` | Toggle between comment and suggestion mode |
| `q` / `<Esc>` | Close without saving |

Inside the drafts picker:

| Key | Action |
|---|---|
| `<CR>` | Jump to the draft's file and line |
| `<C-e>` | Edit the selected draft |
| `<C-d>` | Delete the selected draft |

## How It Works

### Reading Reviews

1. Run `:SilverLining` — the plugin calls the GitHub GraphQL API via `gh` to fetch unresolved review threads
2. Comments are parsed, categorized by severity (error, warning, note, info), and presented in a Telescope picker
3. Select a comment to jump to the file — inline virtual text and diagnostics appear on the relevant lines
4. Review the suggestion, then accept it to apply the change or dismiss it to move on

### Writing Reviews

1. Select lines in visual mode and run `:SilverLiningComment` or `:SilverLiningSuggestion`
2. A floating editor opens — write your comment or edit the code for a suggestion
3. Press `<C-t>` to toggle between comment and suggestion mode, `<C-s>` to save the draft
4. Use `:SilverLiningDrafts` to review, edit, or delete your pending drafts
5. When ready, run `:SilverLiningSubmit` to submit all drafts as a single GitHub review

## FAQ

**Q: Do I need Telescope installed?**
A: No. Without Telescope, review comments are loaded into the quickfix list. However, `:SilverLiningDrafts` does require Telescope.

**Q: How does the plugin detect which PR to use?**
A: It uses the `gh` CLI to find the PR associated with your current branch. You can also pass a PR number explicitly with `:SilverLining 42`.

**Q: What happens when I accept a suggestion?**
A: The suggested code replaces the original lines in the buffer. The virtual text and diagnostics for that comment are cleared.

**Q: Do my drafts persist across Neovim sessions?**
A: No. Drafts are stored in memory and are lost when Neovim exits. Submit your review before closing.

**Q: Can I use this with GitHub Enterprise?**
A: Yes, as long as your `gh` CLI is authenticated against your GitHub Enterprise instance.

## Contributing

Contributions are welcome! If you'd like to help improve silver-lining.nvim:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Submit a pull request

Please open an issue first if you want to discuss a larger change.
