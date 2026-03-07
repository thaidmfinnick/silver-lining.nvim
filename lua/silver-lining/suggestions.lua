local M = {}

local ns = vim.api.nvim_create_namespace("silver-lining-suggestions")
local sign_ns = vim.api.nvim_create_namespace("silver-lining-signs")

local hl_groups_defined = false

local function ensure_highlights()
	if hl_groups_defined then
		return
	end
	hl_groups_defined = true

	vim.api.nvim_set_hl(0, "SilverLiningAdd", { link = "DiffAdd", default = true })
	vim.api.nvim_set_hl(0, "SilverLiningDelete", { link = "DiffDelete", default = true })
	vim.api.nvim_set_hl(0, "SilverLiningChange", { link = "DiffChange", default = true })
	vim.api.nvim_set_hl(0, "SilverLiningComment", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "SilverLiningHeader", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "SilverLiningSuggestionSign", { link = "DiagnosticSignInfo", default = true })
end

--- Get all review items for a given buffer
---@param bufnr number
---@param items silver-lining.ReviewComment[]
---@return silver-lining.ReviewComment[]
local function items_for_buffer(bufnr, items)
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	local matched = {}
	for _, item in ipairs(items) do
		if bufname == item.filename or bufname:sub(-#item.path) == item.path then
			table.insert(matched, item)
		end
	end
	return matched
end

--- Strip markdown badge images like ![Severity](url)
---@param text string
---@return string
local function strip_badges(text)
	return text:gsub("!%[.-%]%(.-%) ?", "")
end

--- Wrap a long line into multiple lines at a given width
---@param text string
---@param max_width number
---@return string[]
local function wrap_text(text, max_width)
	if #text <= max_width then
		return { text }
	end

	local lines = {}
	local remaining = text
	while #remaining > max_width do
		-- Find last space before max_width to break at word boundary
		local break_at = max_width
		local space_pos = remaining:sub(1, max_width):find("%s[^%s]*$")
		if space_pos then
			break_at = space_pos
		end
		table.insert(lines, remaining:sub(1, break_at))
		remaining = remaining:sub(break_at + 1)
	end
	if #remaining > 0 then
		table.insert(lines, remaining)
	end
	return lines
end

--- Show inline suggestion diff as virtual lines below the target code
---@param bufnr number
---@param item silver-lining.ReviewComment
local function render_suggestion(bufnr, item)
	local start_line = item.start_line or item.line
	local end_line = item.line

	-- Calculate available width for wrapping
	local win_width = vim.api.nvim_win_get_width(0)
	local prefix_width = 4 -- "  │ "
	local max_width = math.max(win_width - prefix_width - 5, 40)

	local virt_lines = {}

	-- Comment header
	table.insert(virt_lines, {
		{ "  ┌─ ", "SilverLiningComment" },
		{ " " .. item.user, "SilverLiningHeader" },
		{ " ── " .. (item.created_at:sub(1, 10) or ""), "SilverLiningComment" },
	})

	-- Comment body (without the suggestion block, stripped of badges)
	local body_clean = item.body:gsub("```suggestion\r?\n.-\r?\n```", ""):gsub("\r?\n+$", "")
	body_clean = strip_badges(body_clean)
	for raw_line in body_clean:gmatch("[^\r\n]+") do
		local wrapped = wrap_text(raw_line, max_width)
		for _, wl in ipairs(wrapped) do
			table.insert(virt_lines, {
				{ "  │ ", "SilverLiningComment" },
				{ wl, "SilverLiningComment" },
			})
		end
	end

	if item.suggestion then
		-- Show deleted lines (original code)
		table.insert(virt_lines, {
			{ "  │ ", "SilverLiningComment" },
			{ "─── Original ───", "SilverLiningDelete" },
		})

		local buf_lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
		for _, bl in ipairs(buf_lines) do
			local wrapped = wrap_text("- " .. bl, max_width)
			for _, wl in ipairs(wrapped) do
				table.insert(virt_lines, {
					{ "  │ ", "SilverLiningComment" },
					{ wl, "SilverLiningDelete" },
				})
			end
		end

		-- Show suggested lines
		table.insert(virt_lines, {
			{ "  │ ", "SilverLiningComment" },
			{ "─── Suggestion ───", "SilverLiningAdd" },
		})

		for sug_line in item.suggestion:gmatch("[^\r\n]*") do
			local wrapped = wrap_text("+ " .. sug_line, max_width)
			for _, wl in ipairs(wrapped) do
				table.insert(virt_lines, {
					{ "  │ ", "SilverLiningComment" },
					{ wl, "SilverLiningAdd" },
				})
			end
		end
	end

	-- Footer with accept/reject hint
	local hint = item.suggestion and "  [a]ccept  [x]dismiss" or "  [x]dismiss"
	table.insert(virt_lines, {
		{ "  └─", "SilverLiningComment" },
		{ hint, "SilverLiningComment" },
	})

	-- Place virtual lines below the end_line
	vim.api.nvim_buf_set_extmark(bufnr, ns, end_line - 1, 0, {
		virt_lines = virt_lines,
		virt_lines_above = false,
		id = item.id,
	})

	-- Place sign on each affected line
	for lnum = start_line, end_line do
		vim.api.nvim_buf_set_extmark(bufnr, sign_ns, lnum - 1, 0, {
			sign_text = item.suggestion and "󰌶 " or "󰍨 ",
			sign_hl_group = "SilverLiningSuggestionSign",
			number_hl_group = "SilverLiningChange",
		})
	end
end

--- Show all review comments/suggestions inline for a buffer
---@param bufnr number
---@param items silver-lining.ReviewComment[]
function M.show(bufnr, items)
	ensure_highlights()
	M.clear(bufnr)

	local buf_items = items_for_buffer(bufnr, items)
	if #buf_items == 0 then
		return
	end

	for _, item in ipairs(buf_items) do
		render_suggestion(bufnr, item)
	end

	-- Set up buffer-local keymaps
	M._setup_keymaps(bufnr, buf_items)
end

--- Clear all suggestion decorations from a buffer
---@param bufnr? number
function M.clear(bufnr)
	if bufnr then
		vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
		vim.api.nvim_buf_clear_namespace(bufnr, sign_ns, 0, -1)
		-- Remove buffer-local keymaps
		pcall(vim.keymap.del, "n", "<leader>sa", { buffer = bufnr })
		pcall(vim.keymap.del, "n", "<leader>sx", { buffer = bufnr })
		pcall(vim.keymap.del, "n", "<leader>sd", { buffer = bufnr })
		pcall(vim.keymap.del, "n", "<leader>sA", { buffer = bufnr })
		pcall(vim.keymap.del, "n", "<leader>sX", { buffer = bufnr })
		pcall(vim.keymap.del, "n", "]r", { buffer = bufnr })
		pcall(vim.keymap.del, "n", "[r", { buffer = bufnr })
	else
		for _, b in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(b) then
				vim.api.nvim_buf_clear_namespace(b, ns, 0, -1)
				vim.api.nvim_buf_clear_namespace(b, sign_ns, 0, -1)
			end
		end
	end
end

--- Find the review item at or near the cursor position
---@param bufnr number
---@param cursor_line number 1-indexed
---@param buf_items silver-lining.ReviewComment[]
---@return silver-lining.ReviewComment?
local function find_item_at_cursor(bufnr, cursor_line, buf_items)
	for _, item in ipairs(buf_items) do
		local start_l = item.start_line or item.line
		local end_l = item.line
		if cursor_line >= start_l and cursor_line <= end_l then
			return item
		end
	end
	-- Fallback: find nearest item below cursor
	local nearest = nil
	local nearest_dist = math.huge
	for _, item in ipairs(buf_items) do
		local dist = math.abs(item.line - cursor_line)
		if dist < nearest_dist then
			nearest_dist = dist
			nearest = item
		end
	end
	return nearest
end

--- Remove all decorations (extmark, signs, diagnostic) for a single item
---@param bufnr number
---@param item silver-lining.ReviewComment
local function clear_item(bufnr, item)
	-- Remove virtual lines extmark
	pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, item.id)

	-- Remove signs for this item's line range
	local start_l = item.start_line or item.line
	local end_l = item.line
	local signs = vim.api.nvim_buf_get_extmarks(bufnr, sign_ns, { start_l - 1, 0 }, { end_l - 1, -1 }, {})
	for _, mark in ipairs(signs) do
		vim.api.nvim_buf_del_extmark(bufnr, sign_ns, mark[1])
	end

	-- Remove diagnostic for this item
	require("silver-lining.diagnostics").remove_for_item(bufnr, item.id)

	-- Remove from cached items
	local sl = require("silver-lining")
	for i, cached in ipairs(sl._items) do
		if cached.id == item.id then
			table.remove(sl._items, i)
			break
		end
	end
end

--- Accept a suggestion: replace the original lines with suggested code
---@param bufnr number
---@param item silver-lining.ReviewComment
function M.accept(bufnr, item)
	if not item.suggestion then
		vim.notify("[silver-lining] No suggestion to accept at this position", vim.log.levels.WARN)
		return
	end

	local start_line = item.start_line or item.line
	local end_line = item.line

	-- Split suggestion into lines
	local new_lines = {}
	for line in item.suggestion:gmatch("[^\r\n]*") do
		table.insert(new_lines, line)
	end
	-- Remove trailing empty line if suggestion ends with newline
	if #new_lines > 0 and new_lines[#new_lines] == "" then
		table.remove(new_lines)
	end

	-- Replace lines in buffer
	vim.api.nvim_buf_set_lines(bufnr, start_line - 1, end_line, false, new_lines)

	-- Clear all decorations for this item
	clear_item(bufnr, item)

	vim.notify(
		string.format("[silver-lining] Applied suggestion at line %d", start_line),
		vim.log.levels.INFO
	)
end

--- Dismiss a review comment (remove virtual lines, signs, diagnostic)
---@param bufnr number
---@param item silver-lining.ReviewComment
function M.dismiss(bufnr, item)
	clear_item(bufnr, item)
	vim.notify(
		string.format("[silver-lining] Dismissed comment at line %d", item.line),
		vim.log.levels.INFO
	)
end

--- Resolve (mark as done): dismiss + clear everything for item under cursor
---@param bufnr number
---@param item silver-lining.ReviewComment
function M.resolve(bufnr, item)
	clear_item(bufnr, item)
	vim.notify(
		string.format("[silver-lining] Resolved review at line %d", item.line),
		vim.log.levels.INFO
	)
end

--- Open a diff split showing original vs suggested code
--- Left = original, Right = with suggestion applied
---@param bufnr number
---@param item silver-lining.ReviewComment
function M.open_diff(bufnr, item)
	if not item.suggestion and item.diff_hunk == "" then
		vim.notify("[silver-lining] No suggestion or diff hunk for this comment", vim.log.levels.WARN)
		return
	end

	local filename = vim.api.nvim_buf_get_name(bufnr)
	local filetype = vim.bo[bufnr].filetype
	local all_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local start_line = item.start_line or item.line
	local end_line = item.line

	-- Build the "suggested" version of the file
	local suggested_lines = vim.deepcopy(all_lines)

	if item.suggestion then
		-- Parse suggestion into lines
		local new_lines = {}
		for line in item.suggestion:gmatch("[^\r\n]*") do
			table.insert(new_lines, line)
		end
		if #new_lines > 0 and new_lines[#new_lines] == "" then
			table.remove(new_lines)
		end

		-- Replace the target range
		local before = vim.list_slice(suggested_lines, 1, start_line - 1)
		local after = vim.list_slice(suggested_lines, end_line + 1)
		suggested_lines = {}
		vim.list_extend(suggested_lines, before)
		vim.list_extend(suggested_lines, new_lines)
		vim.list_extend(suggested_lines, after)
	end

	-- Store original window to return to
	local orig_win = vim.api.nvim_get_current_win()

	-- Create the diff layout
	-- Left: scratch buffer with original content
	vim.cmd("tabnew")
	local tab = vim.api.nvim_get_current_tabpage()

	local short_name = vim.fn.fnamemodify(filename, ":t")
	local orig_name = "silver-lining://original/" .. short_name
	local suggested_name = "silver-lining://suggested/" .. short_name

	-- Wipe any leftover buffers with these names from a previous diff
	for _, name in ipairs({ orig_name, suggested_name }) do
		local existing = vim.fn.bufnr(name)
		if existing ~= -1 then
			vim.api.nvim_buf_delete(existing, { force = true })
		end
	end

	local orig_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, all_lines)
	vim.bo[orig_buf].filetype = filetype
	vim.bo[orig_buf].buftype = "nofile"
	vim.bo[orig_buf].modifiable = false
	vim.api.nvim_buf_set_name(orig_buf, orig_name)
	vim.api.nvim_set_current_buf(orig_buf)
	vim.cmd("diffthis")

	-- Right: scratch buffer with suggested content
	vim.cmd("vsplit")
	local suggested_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(suggested_buf, 0, -1, false, suggested_lines)
	vim.bo[suggested_buf].filetype = filetype
	vim.bo[suggested_buf].buftype = "nofile"
	vim.bo[suggested_buf].modifiable = false
	vim.api.nvim_buf_set_name(suggested_buf, suggested_name)
	vim.api.nvim_set_current_buf(suggested_buf)
	vim.cmd("diffthis")

	-- Jump to the changed line
	vim.api.nvim_win_set_cursor(0, { math.min(start_line, vim.api.nvim_buf_line_count(suggested_buf)), 0 })

	-- Add comment body as virtual text at top of suggested buffer
	local header_lines = {}
	table.insert(header_lines, { { "  Review by " .. item.user, "SilverLiningHeader" } })
	local body_clean = item.body:gsub("```suggestion\r?\n.-\r?\n```", ""):gsub("\r?\n+$", "")
	for line in body_clean:gmatch("[^\r\n]+") do
		table.insert(header_lines, { { "  " .. line, "SilverLiningComment" } })
	end
	table.insert(header_lines, { { "" } })

	ensure_highlights()
	vim.api.nvim_buf_set_extmark(suggested_buf, ns, math.max(start_line - 2, 0), 0, {
		virt_lines = header_lines,
		virt_lines_above = true,
	})

	-- Keymaps for the diff tab
	local function close_diff()
		-- Close the diff tab and go back
		vim.cmd("tabclose")
	end

	local function accept_and_close()
		if not item.suggestion then
			vim.notify("[silver-lining] No suggestion to accept", vim.log.levels.WARN)
			return
		end
		vim.cmd("tabclose")
		-- Apply the suggestion in the original buffer
		M.accept(bufnr, item)
	end

	-- Set keymaps on both buffers in the diff tab
	for _, buf in ipairs({ orig_buf, suggested_buf }) do
		vim.keymap.set("n", "q", close_diff, { buffer = buf, desc = "Close diff view" })
		vim.keymap.set("n", "<leader>sa", accept_and_close, { buffer = buf, desc = "Accept suggestion and close" })
		vim.keymap.set("n", "<Esc>", close_diff, { buffer = buf, desc = "Close diff view" })
	end
end

--- Setup buffer-local keymaps for navigating and acting on suggestions
---@param bufnr number
---@param buf_items silver-lining.ReviewComment[]
function M._setup_keymaps(bufnr, buf_items)
	-- Accept suggestion under cursor
	vim.keymap.set("n", "<leader>sa", function()
		local cursor = vim.api.nvim_win_get_cursor(0)[1]
		local item = find_item_at_cursor(bufnr, cursor, buf_items)
		if item then
			M.accept(bufnr, item)
		end
	end, { buffer = bufnr, desc = "Silver Lining: Accept suggestion" })

	-- Open inline diff view for comment under cursor
	vim.keymap.set("n", "<leader>sd", function()
		local cursor = vim.api.nvim_win_get_cursor(0)[1]
		local item = find_item_at_cursor(bufnr, cursor, buf_items)
		if item then
			M.open_diff(bufnr, item)
		end
	end, { buffer = bufnr, desc = "Silver Lining: Open diff view" })

	-- Dismiss comment under cursor
	vim.keymap.set("n", "<leader>sx", function()
		local cursor = vim.api.nvim_win_get_cursor(0)[1]
		local item = find_item_at_cursor(bufnr, cursor, buf_items)
		if item then
			M.dismiss(bufnr, item)
		end
	end, { buffer = bufnr, desc = "Silver Lining: Dismiss comment" })

	-- Accept all suggestions in buffer
	vim.keymap.set("n", "<leader>sA", function()
		-- Apply in reverse order to preserve line numbers
		local with_suggestions = vim.tbl_filter(function(item)
			return item.suggestion ~= nil
		end, buf_items)

		table.sort(with_suggestions, function(a, b)
			return a.line > b.line
		end)

		local count = 0
		for _, item in ipairs(with_suggestions) do
			M.accept(bufnr, item)
			count = count + 1
		end
		vim.notify(string.format("[silver-lining] Applied %d suggestions", count), vim.log.levels.INFO)
	end, { buffer = bufnr, desc = "Silver Lining: Accept all suggestions" })

	-- Dismiss all
	vim.keymap.set("n", "<leader>sX", function()
		M.clear(bufnr)
		vim.notify("[silver-lining] Dismissed all comments", vim.log.levels.INFO)
	end, { buffer = bufnr, desc = "Silver Lining: Dismiss all comments" })

	-- Navigate: next review comment
	vim.keymap.set("n", "]r", function()
		local cursor = vim.api.nvim_win_get_cursor(0)[1]
		for _, item in ipairs(buf_items) do
			if item.line > cursor then
				vim.api.nvim_win_set_cursor(0, { item.line, 0 })
				return
			end
		end
		-- Wrap around
		if #buf_items > 0 then
			vim.api.nvim_win_set_cursor(0, { buf_items[1].line, 0 })
		end
	end, { buffer = bufnr, desc = "Silver Lining: Next review comment" })

	-- Navigate: previous review comment
	vim.keymap.set("n", "[r", function()
		local cursor = vim.api.nvim_win_get_cursor(0)[1]
		for i = #buf_items, 1, -1 do
			if buf_items[i].line < cursor then
				vim.api.nvim_win_set_cursor(0, { buf_items[i].line, 0 })
				return
			end
		end
		-- Wrap around
		if #buf_items > 0 then
			vim.api.nvim_win_set_cursor(0, { buf_items[#buf_items].line, 0 })
		end
	end, { buffer = bufnr, desc = "Silver Lining: Previous review comment" })
end

return M
