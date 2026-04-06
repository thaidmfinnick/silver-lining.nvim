# Changelog

## Unreleased

### Added

- **Create PR comments from Neovim** with draft workflow
  - `:SilverLiningComment` — open a floating window to draft a comment on visually selected lines
  - `:SilverLiningSuggestion` — open a floating window pre-filled with selected code to draft a suggestion
  - Toggle between comment and suggestion modes with `<C-t>` inside the float
  - In normal mode: `s` save draft, `t` toggle mode, `<leader>s` save and submit, `q`/`<Esc>` cancel
  - In insert mode: `<C-s>` save draft, `<C-t>` toggle mode
- **Draft management via Telescope** (`:SilverLiningDrafts`)
  - Preview all pending drafts
  - `<CR>` jump to file, `<C-e>` edit draft, `<C-d>` delete draft
- **Batch review submission** (`:SilverLiningSubmit [event]`)
  - Submit all drafts as a single GitHub review
  - Supports `COMMENT`, `APPROVE`, and `REQUEST_CHANGES` events
- New default keymaps: `<leader>sc` (comment), `<leader>ss` (suggestion)

### Changed

- `async_cmd`, `detect_repo_async`, `detect_pr_number_async` are now public module functions on `require("silver-lining")` for reuse across modules

## 1.0.0

### Added

- Auto-detect repo and PR number from current branch via `gh` CLI
- Fetch PR review comments using GitHub GraphQL API (paginated)
- Filter to show only unresolved review threads
- Telescope picker with severity indicators, file path, and preview
- Inline virtual text rendering for comments and suggestions
- Accept / dismiss suggestions with configurable keymaps
- Accept all / dismiss all in buffer
- Side-by-side diff view for suggested changes
- Native Neovim diagnostics integration (ERROR / WARN / INFO / HINT)
- Quickfix list fallback when Telescope is not installed
- Configurable keymaps with option to disable individually or entirely
