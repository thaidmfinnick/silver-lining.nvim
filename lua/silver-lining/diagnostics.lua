local M = {}

local ns = vim.api.nvim_create_namespace("silver-lining")

M.ns = ns

local severity_map = {
	E = vim.diagnostic.severity.ERROR,
	W = vim.diagnostic.severity.WARN,
	N = vim.diagnostic.severity.HINT,
	I = vim.diagnostic.severity.INFO,
}

--- Set diagnostics on a buffer for all review items matching that file
---@param bufnr number
---@param items silver-lining.ReviewComment[]
function M.set(bufnr, items)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local diagnostics = {}

	for _, item in ipairs(items) do
		if bufname == item.filename or bufname:sub(-#item.path) == item.path then
			local message = item.text
			if item.suggestion then
				message = message .. "\nSuggestion: " .. item.suggestion
			end

			local lnum = (item.lnum or 1) - 1
			local end_lnum = lnum
			if item.start_line and item.start_line ~= vim.NIL then
				lnum = item.start_line - 1
				end_lnum = item.line - 1
			end

			table.insert(diagnostics, {
				lnum = lnum,
				end_lnum = end_lnum,
				col = 0,
				message = message,
				severity = severity_map[item.type] or vim.diagnostic.severity.INFO,
				source = "silver-lining",
				user_data = {
					id = item.id,
					suggestion = item.suggestion,
					diff_hunk = item.diff_hunk,
					user = item.user,
					commit_id = item.commit_id,
				},
			})
		end
	end

	vim.diagnostic.set(ns, bufnr, diagnostics)
end

--- Remove diagnostic for a specific review item by id
---@param bufnr number
---@param item_id number
function M.remove_for_item(bufnr, item_id)
	local existing = vim.diagnostic.get(bufnr, { namespace = ns })
	local remaining = {}

	for _, d in ipairs(existing) do
		if not d.user_data or d.user_data.id ~= item_id then
			table.insert(remaining, d)
		end
	end

	vim.diagnostic.set(ns, bufnr, remaining)
end

--- Clear silver-lining diagnostics from a buffer
---@param bufnr? number buffer number, nil to clear all
function M.clear(bufnr)
	if bufnr then
		vim.diagnostic.reset(ns, bufnr)
	else
		vim.diagnostic.reset(ns)
	end
end

return M
