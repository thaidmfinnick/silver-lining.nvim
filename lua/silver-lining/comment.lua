local M = {}

--- In-memory draft storage
---@class silver-lining.Draft
---@field id number unique draft id
---@field path string file path relative to repo root
---@field abs_path string absolute file path
---@field line number end line
---@field start_line? number start line for multi-line
---@field body string comment text
---@field mode string "comment" or "suggestion"
---@field original_code string[] original selected lines (used for suggestion mode)

M._drafts = {}
local next_id = 1

--- Get the file path relative to the git repo root
---@param bufnr number
---@return string? relative path, or nil if not in a git repo
local function get_relative_path(bufnr)
	local abs = vim.api.nvim_buf_get_name(bufnr)
	if abs == "" then
		return nil
	end
	local toplevel = vim.trim(vim.fn.system("git rev-parse --show-toplevel"))
	if vim.v.shell_error ~= 0 then
		return nil
	end
	if abs:sub(1, #toplevel) == toplevel then
		return abs:sub(#toplevel + 2) -- skip the trailing /
	end
	return nil
end

--- Add a draft to the list
---@param draft silver-lining.Draft
local function add_draft(draft)
	draft.id = next_id
	next_id = next_id + 1
	table.insert(M._drafts, draft)
end

--- Remove a draft by id
---@param id number
function M.remove_draft(id)
	for i, d in ipairs(M._drafts) do
		if d.id == id then
			table.remove(M._drafts, i)
			return
		end
	end
end

--- Update a draft's body and mode
---@param id number
---@param body string
---@param mode string
function M.update_draft(id, body, mode)
	for _, d in ipairs(M._drafts) do
		if d.id == id then
			d.body = body
			d.mode = mode
			return
		end
	end
end

--- Get all drafts
---@return silver-lining.Draft[]
function M.get_drafts()
	return M._drafts
end

--- Clear all drafts
function M.clear_drafts()
	M._drafts = {}
end

--- State for the currently open float
---@class silver-lining.FloatState
---@field bufnr number float buffer
---@field winnr number float window
---@field mode string "comment" or "suggestion"
---@field source_bufnr number buffer the comment targets
---@field path string relative file path
---@field abs_path string absolute file path
---@field start_line number
---@field end_line number
---@field original_code string[]
---@field editing_draft_id? number if editing an existing draft

local float_state = nil

--- Close the float window if open
local function close_float()
	if float_state and float_state.winnr and vim.api.nvim_win_is_valid(float_state.winnr) then
		vim.api.nvim_win_close(float_state.winnr, true)
	end
	if float_state and float_state.bufnr and vim.api.nvim_buf_is_valid(float_state.bufnr) then
		vim.api.nvim_buf_delete(float_state.bufnr, { force = true })
	end
	float_state = nil
end

--- Build the float title string
---@param mode string
---@param path string
---@param start_line number
---@param end_line number
---@return string
local function float_title(mode, path, start_line, end_line)
	local short = vim.fn.fnamemodify(path, ":t")
	local range = start_line == end_line and tostring(start_line) or (start_line .. "-" .. end_line)
	local label = mode == "suggestion" and "New Suggestion" or "New Comment"
	return " " .. label .. " -- " .. short .. ":" .. range .. " "
end

--- Save the current float content as a draft
local function save_draft()
	if not float_state then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(float_state.bufnr, 0, -1, false)
	local body = vim.trim(table.concat(lines, "\n"))

	if body == "" then
		vim.notify("[silver-lining] Empty comment, not saved", vim.log.levels.WARN)
		return
	end

	-- In suggestion mode, wrap the edited code in a suggestion block
	-- and prepend any text before the code as the comment body
	local final_body
	if float_state.mode == "suggestion" then
		final_body = "```suggestion\n" .. body .. "\n```"
	else
		final_body = body
	end

	if float_state.editing_draft_id then
		M.update_draft(float_state.editing_draft_id, final_body, float_state.mode)
		vim.notify(
			string.format("[silver-lining] Draft updated (%d total)", #M._drafts),
			vim.log.levels.INFO
		)
	else
		add_draft({
			path = float_state.path,
			abs_path = float_state.abs_path,
			line = float_state.end_line,
			start_line = float_state.start_line ~= float_state.end_line and float_state.start_line or nil,
			body = final_body,
			mode = float_state.mode,
			original_code = float_state.original_code,
		})
		vim.notify(
			string.format("[silver-lining] Draft saved (%d total)", #M._drafts),
			vim.log.levels.INFO
		)
	end

	close_float()
end

--- Toggle between comment and suggestion mode in the float
local function toggle_mode()
	if not float_state then
		return
	end

	local current_lines = vim.api.nvim_buf_get_lines(float_state.bufnr, 0, -1, false)

	if float_state.mode == "comment" then
		-- Switch to suggestion: save comment text, fill with original code
		float_state._saved_comment = current_lines
		float_state.mode = "suggestion"
		vim.api.nvim_buf_set_lines(float_state.bufnr, 0, -1, false, float_state.original_code)
	else
		-- Switch to comment: save suggestion edits, restore comment text
		float_state._saved_suggestion = current_lines
		float_state.mode = "comment"
		local restore = float_state._saved_comment or {}
		vim.api.nvim_buf_set_lines(float_state.bufnr, 0, -1, false, restore)
	end

	-- Update window title
	local title = float_title(
		float_state.mode,
		float_state.path,
		float_state.start_line,
		float_state.end_line
	)
	vim.api.nvim_win_set_config(float_state.winnr, { title = title })
end

--- Open the comment float
---@param mode string "comment" or "suggestion"
---@param opts? { draft_id?: number, body?: string, path?: string, abs_path?: string, start_line?: number, end_line?: number, original_code?: string[] }
function M.open(mode, opts)
	opts = opts or {}

	-- Close any existing float
	close_float()

	local source_bufnr = vim.api.nvim_get_current_buf()
	local abs_path, path, start_line, end_line, original_code

	if opts.path then
		-- Editing an existing draft
		path = opts.path
		abs_path = opts.abs_path or path
		start_line = opts.start_line or 1
		end_line = opts.end_line or start_line
		original_code = opts.original_code or {}
	else
		-- New draft from visual selection
		path = get_relative_path(source_bufnr)
		if not path then
			vim.notify("[silver-lining] Not in a git repository", vim.log.levels.ERROR)
			return
		end
		abs_path = vim.api.nvim_buf_get_name(source_bufnr)

		-- Get visual selection range
		start_line = vim.fn.getpos("'<")[2]
		end_line = vim.fn.getpos("'>")[2]
		if start_line == 0 then
			-- No visual selection, use current line
			start_line = vim.api.nvim_win_get_cursor(0)[1]
			end_line = start_line
		end

		original_code = vim.api.nvim_buf_get_lines(source_bufnr, start_line - 1, end_line, false)
	end

	-- Create float buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].filetype = mode == "suggestion" and vim.bo[source_bufnr].filetype or "markdown"

	-- Set initial content
	if opts.body then
		-- Editing existing draft: extract content from body
		local body = opts.body
		if mode == "suggestion" then
			-- Extract code from suggestion block
			local suggestion_code = body:match("```suggestion\r?\n(.-)\r?\n```")
			if suggestion_code then
				local lines = {}
				for line in suggestion_code:gmatch("[^\r\n]*") do
					table.insert(lines, line)
				end
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			else
				vim.api.nvim_buf_set_lines(buf, 0, -1, false, original_code)
			end
		else
			local lines = {}
			for line in body:gmatch("[^\r\n]*") do
				table.insert(lines, line)
			end
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		end
	elseif mode == "suggestion" then
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, original_code)
	end

	-- Calculate window size
	local width = math.min(math.floor(vim.o.columns * 0.6), 100)
	local height = math.min(math.max(#original_code + 3, 8), math.floor(vim.o.lines * 0.5))

	local title = float_title(mode, path, start_line, end_line)
	local footer = " s: save  t: toggle  <leader>s: submit  q: quit "

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		style = "minimal",
		border = "rounded",
		title = title,
		title_pos = "center",
		footer = footer,
		footer_pos = "center",
	})

	-- Enter insert mode for comment, normal for suggestion (user edits code)
	if mode == "comment" and not opts.body then
		vim.cmd("startinsert")
	end

	float_state = {
		bufnr = buf,
		winnr = win,
		mode = mode,
		source_bufnr = source_bufnr,
		path = path,
		abs_path = abs_path,
		start_line = start_line,
		end_line = end_line,
		original_code = original_code,
		editing_draft_id = opts.draft_id,
	}

	-- Float-local keymaps
	local km_opts = { buffer = buf, nowait = true }
	vim.keymap.set("n", "q", close_float, km_opts)
	vim.keymap.set("n", "<Esc>", close_float, km_opts)
	vim.keymap.set("n", "s", save_draft, km_opts)
	vim.keymap.set("n", "t", toggle_mode, km_opts)
	vim.keymap.set("n", "<leader>s", function()
		save_draft()
		if #M._drafts > 0 then
			M.submit()
		end
	end, km_opts)
	vim.keymap.set("i", "<C-s>", function()
		vim.cmd("stopinsert")
		save_draft()
	end, km_opts)
	vim.keymap.set("i", "<C-t>", function()
		vim.cmd("stopinsert")
		toggle_mode()
		vim.cmd("startinsert")
	end, km_opts)
end

--- Open Telescope picker showing all pending drafts
function M.open_picker()
	local has_telescope, pickers = pcall(require, "telescope.pickers")
	if not has_telescope then
		vim.notify("[silver-lining] Telescope is required for draft picker", vim.log.levels.ERROR)
		return
	end

	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")
	local previewers = require("telescope.previewers")

	if #M._drafts == 0 then
		vim.notify("[silver-lining] No pending drafts", vim.log.levels.INFO)
		return
	end

	pickers
		.new({}, {
			prompt_title = "Silver Lining Drafts (" .. #M._drafts .. ")",
			finder = finders.new_table({
				results = M._drafts,
				entry_maker = function(draft)
					local icon = draft.mode == "suggestion" and "󰌶 " or "󰍨 "
					local range = draft.start_line
							and (draft.start_line .. "-" .. draft.line)
						or tostring(draft.line)
					local short_path = vim.fn.fnamemodify(draft.path, ":t")
					-- Clean body for display
					local display_body = draft.body:gsub("```suggestion\r?\n.-\r?\n```", "[suggestion]")
					display_body = display_body:gsub("\r?\n", " "):gsub("%s+", " ")
					display_body = vim.trim(display_body):sub(1, 60)

					return {
						value = draft,
						display = icon .. short_path .. ":" .. range .. "  " .. display_body,
						ordinal = draft.path .. ":" .. tostring(draft.line) .. " " .. draft.body,
					}
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = previewers.new_buffer_previewer({
				title = "Draft Preview",
				define_preview = function(self, entry)
					local draft = entry.value
					local lines = {}
					table.insert(lines, "Mode: " .. draft.mode)
					table.insert(lines, "File: " .. draft.path)
					local range = draft.start_line
							and ("Lines: " .. draft.start_line .. "-" .. draft.line)
						or ("Line: " .. draft.line)
					table.insert(lines, range)
					table.insert(lines, string.rep("─", 40))
					table.insert(lines, "")
					for line in draft.body:gmatch("[^\r\n]*") do
						table.insert(lines, line)
					end
					if draft.original_code and #draft.original_code > 0 then
						table.insert(lines, "")
						table.insert(lines, string.rep("─", 40))
						table.insert(lines, "Original code:")
						for _, cl in ipairs(draft.original_code) do
							table.insert(lines, cl)
						end
					end
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
					vim.bo[self.state.bufnr].filetype = "markdown"
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				-- <CR> open file at draft location
				actions.select_default:replace(function()
					local entry = action_state.get_selected_entry()
					if not entry then
						return
					end
					actions.close(prompt_bufnr)
					local draft = entry.value
					vim.cmd("edit " .. vim.fn.fnameescape(draft.abs_path))
					vim.api.nvim_win_set_cursor(0, { draft.line, 0 })
				end)

				-- <C-d> delete draft
				map({ "i", "n" }, "<C-d>", function()
					local entry = action_state.get_selected_entry()
					if not entry then
						return
					end
					local draft = entry.value
					M.remove_draft(draft.id)
					vim.notify(
						string.format("[silver-lining] Draft deleted (%d remaining)", #M._drafts),
						vim.log.levels.INFO
					)
					actions.close(prompt_bufnr)
					-- Re-open picker if drafts remain
					if #M._drafts > 0 then
						vim.schedule(function()
							M.open_picker()
						end)
					end
				end)

				-- <C-e> edit draft
				map({ "i", "n" }, "<C-e>", function()
					local entry = action_state.get_selected_entry()
					if not entry then
						return
					end
					actions.close(prompt_bufnr)
					local draft = entry.value
					vim.schedule(function()
						M.open(draft.mode, {
							draft_id = draft.id,
							body = draft.body,
							path = draft.path,
							abs_path = draft.abs_path,
							start_line = draft.start_line,
							end_line = draft.line,
							original_code = draft.original_code,
						})
					end)
				end)

				return true
			end,
		})
		:find()
end

--- Detect the HEAD commit SHA of the current PR
---@param callback fun(sha: string?)
local function detect_head_sha_async(callback)
	local sl = require("silver-lining")
	sl.async_cmd("gh pr view --json headRefOid -q .headRefOid 2>/dev/null", function(out)
		callback(out)
	end)
end

--- Submit all drafts as a single GitHub review
---@param event? string "COMMENT" (default), "APPROVE", or "REQUEST_CHANGES"
function M.submit(event)
	event = event or "COMMENT"
	event = event:upper()

	if not vim.tbl_contains({ "COMMENT", "APPROVE", "REQUEST_CHANGES" }, event) then
		vim.notify(
			"[silver-lining] Invalid event: " .. event .. ". Use COMMENT, APPROVE, or REQUEST_CHANGES",
			vim.log.levels.ERROR
		)
		return
	end

	if #M._drafts == 0 then
		vim.notify("[silver-lining] No drafts to submit", vim.log.levels.WARN)
		return
	end

	local sl = require("silver-lining")
	local cfg = require("silver-lining.config").get()

	local function do_submit(repo, pr_num, head_sha)
		-- Validate repo format
		if not repo:match("^[%w%.%-_]+/[%w%.%-_]+$") then
			vim.notify("[silver-lining] Invalid repo format: " .. repo, vim.log.levels.ERROR)
			return
		end

		-- Build comments array for the review
		local comments = {}
		for _, draft in ipairs(M._drafts) do
			local comment = {
				path = draft.path,
				body = draft.body,
				line = draft.line,
				side = "RIGHT",
			}
			if draft.start_line then
				comment.start_line = draft.start_line
				comment.start_side = "RIGHT"
			end
			table.insert(comments, comment)
		end

		local payload = {
			commit_id = head_sha,
			event = event,
			comments = comments,
		}

		local json_body = vim.json.encode(payload)
		local cmd = string.format(
			"gh api repos/%s/pulls/%d/reviews --input - <<'SILVER_LINING_EOF'\n%s\nSILVER_LINING_EOF",
			repo,
			pr_num,
			json_body
		)

		vim.notify("[silver-lining] Submitting review...", vim.log.levels.INFO)

		sl.async_cmd(cmd, function(output, err)
			if err then
				vim.notify("[silver-lining] Failed to submit review: " .. err, vim.log.levels.ERROR)
				return
			end

			local count = #M._drafts
			M.clear_drafts()
			vim.notify(
				string.format("[silver-lining] Review submitted with %d comment(s) (%s)", count, event),
				vim.log.levels.INFO
			)
		end)
	end

	-- Chain: detect repo -> detect PR -> detect HEAD SHA -> submit
	local function with_repo(repo)
		if not repo then
			vim.notify("[silver-lining] Could not detect repo. Set repo in config.", vim.log.levels.ERROR)
			return
		end

		sl.detect_pr_number_async(function(pr_num)
			if not pr_num then
				vim.notify("[silver-lining] Could not detect PR number.", vim.log.levels.ERROR)
				return
			end

			detect_head_sha_async(function(sha)
				if not sha then
					vim.notify("[silver-lining] Could not detect PR HEAD commit.", vim.log.levels.ERROR)
					return
				end

				do_submit(repo, pr_num, sha)
			end)
		end)
	end

	if cfg.repo then
		with_repo(cfg.repo)
	else
		sl.detect_repo_async(with_repo)
	end
end

return M
