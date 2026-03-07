local M = {}

--- Resolve a basename or relative path to a full path by searching the project directory
---@param filepath string e.g. "lib/views/channel_thread_view.dart"
---@return string resolved full path or original if not found
local function resolve_filepath(filepath)
	-- If already absolute and exists, return as-is
	if filepath:sub(1, 1) == "/" then
		return filepath
	end

	-- Try as relative path from cwd first
	local cwd = vim.fn.getcwd()
	local full = cwd .. "/" .. filepath
	if vim.fn.filereadable(full) == 1 then
		return full
	end

	-- Fallback: glob search by basename
	local basename = vim.fn.fnamemodify(filepath, ":t")
	local results = vim.fn.globpath(cwd, "**/" .. basename, false, true)
	if #results == 1 then
		return results[1]
	elseif #results > 1 then
		-- Prefer path that ends with the original relative path
		for _, r in ipairs(results) do
			if r:sub(-#filepath) == filepath then
				return r
			end
		end
		table.sort(results, function(a, b)
			return #a < #b
		end)
		return results[1]
	end

	return filepath
end

--- Extract suggestion code block from comment body if present
---@param body string
---@return string? suggestion the suggested replacement code, or nil
local function extract_suggestion(body)
	return body:match("```suggestion\r?\n(.-)\r?\n```")
end

--- Infer severity from comment body keywords
---@param body string
---@return string type quickfix type char
local function infer_severity(body)
	local lower = body:lower()
	if lower:find("bug") or lower:find("crash") or lower:find("error") or lower:find("security") then
		return "E"
	end
	if lower:find("warning") or lower:find("dead") or lower:find("unused") or lower:find("deprecated") then
		return "W"
	end
	if lower:find("nit") or lower:find("style") or lower:find("minor") then
		return "N"
	end
	return "I"
end

---@class silver-lining.ReviewComment
---@field id number
---@field path string file path relative to repo root
---@field filename string resolved full file path
---@field line number end line (or single line)
---@field start_line? number start line for multi-line comments
---@field side string "LEFT" or "RIGHT"
---@field start_side? string "LEFT" or "RIGHT"
---@field body string full comment body
---@field diff_hunk string diff context
---@field commit_id string
---@field original_commit_id string
---@field suggestion? string extracted suggestion code
---@field user string reviewer login
---@field created_at string
---@field type string severity: E, W, I, N
---@field lnum number line number (alias for quickfix)
---@field col number column (always 0)
---@field text string short text for display

--- Parse the raw JSON array from gh api pulls/comments endpoint
---@param comments table[] array of comment objects from GitHub API
---@return silver-lining.ReviewComment[]
function M.parse_review_comments(comments)
	local items = {}

	for _, c in ipairs(comments) do
		if not c.path or c.path == "" then
			goto continue
		end

		local body = c.body or ""
		local suggestion = extract_suggestion(body)
		-- Clean body for display: strip badges, suggestion blocks, collapse newlines
		local display_text = body:gsub("```suggestion\r?\n.-\r?\n```", "[has suggestion]")
		display_text = display_text:gsub("!%[.-%]%(.-%) ?", "")
		display_text = display_text:gsub("\r?\n", " "):gsub("%s+", " ")
		display_text = vim.trim(display_text):sub(1, 500)

		local function non_nil(val)
			if val == nil or val == vim.NIL then
				return nil
			end
			return val
		end

		local line = non_nil(c.line) or non_nil(c.original_line) or non_nil(c.position) or 1
		local start_line = non_nil(c.start_line) or non_nil(c.original_start_line)

		table.insert(items, {
			id = c.id,
			path = c.path,
			filename = resolve_filepath(c.path),
			line = line,
			start_line = start_line,
			side = c.side or "RIGHT",
			start_side = c.start_side,
			body = body,
			diff_hunk = c.diff_hunk or "",
			commit_id = c.commit_id or "",
			original_commit_id = c.original_commit_id or "",
			suggestion = suggestion,
			user = c.user and c.user.login or "unknown",
			created_at = c.created_at or "",
			type = infer_severity(body),
			-- quickfix-compatible fields
			lnum = line,
			col = 0,
			text = display_text,
		})

		::continue::
	end

	return items
end

return M
