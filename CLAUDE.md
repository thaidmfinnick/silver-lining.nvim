# silver-lining.nvim

Neovim plugin that brings GitHub PR review comments inline into the editor and lets you author reviews without leaving Neovim. Fetches unresolved review threads via `gh` CLI (GraphQL), displays them as virtual text with diagnostics, and supports drafting comments/suggestions and submitting full reviews.

## Project Structure

```
plugin/silver-lining.lua          -- User commands (:SilverLining, :SilverLiningClear, :SilverLiningComment, :SilverLiningSuggestion, :SilverLiningDrafts, :SilverLiningSubmit)
lua/silver-lining/
  init.lua                        -- Core: async fetching, repo/PR detection, spinner, caching
  config.lua                      -- setup() and defaults
  parser.lua                      -- GitHub API response parsing, severity inference, suggestion extraction
  suggestions.lua                 -- Virtual text rendering, accept/dismiss/diff actions, keymaps
  diagnostics.lua                 -- Neovim diagnostics integration (custom namespace)
  comment.lua                     -- Draft authoring: float editor, toggle comment/suggestion, draft management, review submission via REST API
lua/telescope/_extensions/
  silver-lining.lua               -- Telescope picker with custom previewer for review comments
```

## Tech Stack

- Pure Lua (no build step)
- Neovim >= 0.9
- `gh` CLI (authenticated) for GitHub API access
- telescope.nvim (optional — falls back to quickfix list)

## Key Patterns

- **Async-first**: All shell commands use `vim.fn.jobstart()`, never blocking
- **Extmarks** for inline decorations (virtual text + signs)
- **GraphQL** for fetching review threads with pagination
- **REST API** (`POST /repos/{owner}/{repo}/pulls/{pr}/reviews`) for submitting reviews
- **Error-first callbacks** with spinner feedback
- **Buffer-local keymaps** set when suggestions are rendered, configurable via `setup()`
- **In-memory draft storage** (`comment.lua:M._drafts`) — drafts do not persist across sessions

## Commands

- `:SilverLining [pr_number]` — fetch and display PR comments (auto-detects PR if omitted)
- `:SilverLiningClear` — clear all suggestions, diagnostics, and cached items
- `:SilverLiningComment` — open float to draft a comment on selected lines (supports visual range)
- `:SilverLiningSuggestion` — open float to draft a code suggestion on selected lines
- `:SilverLiningDrafts` — open Telescope picker to browse/edit/delete pending drafts
- `:SilverLiningSubmit [event]` — submit all drafts as a GitHub review (COMMENT, APPROVE, or REQUEST_CHANGES)

## Development

No build process. To test manually:

1. Install the plugin in Neovim (e.g., symlink or use a plugin manager pointing to local path)
2. Ensure `gh auth status` succeeds
3. Open a file on a branch that has an open PR with review comments
4. Run `:SilverLining`

There are no automated tests currently.

## Code Conventions

- LuaLS type annotations on module-level functions
- Modules return a table `M` with public functions
- Config accessed via `require("silver-lining.config").get()`
- Highlight groups prefixed with `SilverLining` (e.g., `SilverLiningAdd`, `SilverLiningDelete`)
- Namespaces: `silver-lining-suggestions`, `silver-lining-signs` for extmarks; `silver-lining` for diagnostics
- Input validation on repo format to prevent command injection
- Shell args escaped with `vim.fn.shellescape()`
