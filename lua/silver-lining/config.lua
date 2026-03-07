local M = {}

---@class silver-lining.Config
---@field repo? string GitHub repo in "owner/repo" format (auto-detects if omitted)
---@field auto_open? boolean auto-open quickfix list after loading (default: true)
local defaults = {
	repo = nil,
	auto_open = true,
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
