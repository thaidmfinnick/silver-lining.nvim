local M = {}

---@class silver-lining.Keymaps
---@field accept? string Accept suggestion under cursor (default: "<leader>sa")
---@field dismiss? string Dismiss comment under cursor (default: "<leader>sx")
---@field diff? string Open side-by-side diff view (default: "<leader>sd")
---@field accept_all? string Accept all suggestions in buffer (default: "<leader>sA")
---@field dismiss_all? string Dismiss all comments in buffer (default: "<leader>sX")
---@field next_comment? string Jump to next review comment (default: "]r")
---@field prev_comment? string Jump to previous review comment (default: "[r")

---@class silver-lining.Config
---@field repo? string GitHub repo in "owner/repo" format (auto-detects if omitted)
---@field keymaps? silver-lining.Keymaps|false Buffer-local keymaps (set to false to disable all)
local defaults = {
	repo = nil,
	keymaps = {
		accept = "<leader>sa",
		dismiss = "<leader>sx",
		diff = "<leader>sd",
		accept_all = "<leader>sA",
		dismiss_all = "<leader>sX",
		next_comment = "]r",
		prev_comment = "[r",
	},
}

---@type silver-lining.Config
local current = {}

function M.setup(opts)
	current = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

---@return silver-lining.Config
function M.get()
	if vim.tbl_isempty(current) then
		current = vim.tbl_deep_extend("force", {}, defaults)
	end
	return current
end

return M
