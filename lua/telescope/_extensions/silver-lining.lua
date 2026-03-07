local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
	error("silver-lining telescope extension requires nvim-telescope/telescope.nvim")
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")

local type_labels = {
	E = "ERROR",
	W = "WARN",
	N = "NOTE",
	I = "INFO",
}

local type_highlights = {
	E = "DiagnosticError",
	W = "DiagnosticWarn",
	N = "DiagnosticHint",
	I = "DiagnosticInfo",
}

--- Custom previewer that shows the full review comment body + diff hunk
local function review_previewer()
	return previewers.new_buffer_previewer({
		title = "Review Comment",
		define_preview = function(self, entry)
			local item = entry.value
			local lines = {}

			table.insert(lines, "Reviewer: " .. item.user)
			table.insert(lines, "File: " .. item.path .. ":" .. item.lnum)
			if item.start_line and item.start_line ~= vim.NIL then
				table.insert(lines, "Lines: " .. tostring(item.start_line) .. "-" .. tostring(item.line))
			end
			table.insert(lines, "Severity: " .. (type_labels[item.type] or "INFO"))
			table.insert(lines, "")
			table.insert(lines, "--- Comment ---")
			for line in item.body:gmatch("[^\r\n]*") do
				table.insert(lines, line)
			end

			if item.suggestion then
				table.insert(lines, "")
				table.insert(lines, "--- Suggestion ---")
				for line in item.suggestion:gmatch("[^\r\n]*") do
					table.insert(lines, line)
				end
			end

			if item.diff_hunk ~= "" then
				table.insert(lines, "")
				table.insert(lines, "--- Diff Hunk ---")
				for line in item.diff_hunk:gmatch("[^\r\n]*") do
					table.insert(lines, line)
				end
			end

			vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
			vim.bo[self.state.bufnr].filetype = "markdown"
		end,
	})
end

local function open_picker(items, opts)
	opts = opts or {}

	local displayer = entry_display.create({
		separator = " ",
		items = {
			{ width = 7 },
			{ width = 40 },
			{ remaining = true },
		},
	})

	local make_display = function(entry)
		local suffix = ""
		if entry.value.suggestion then
			suffix = " [suggestion]"
		end
		return displayer({
			{ type_labels[entry.severity] or "INFO", type_highlights[entry.severity] or "DiagnosticInfo" },
			{ entry.value.path .. ":" .. entry.lnum, "TelescopeResultsIdentifier" },
			{ entry.text .. suffix },
		})
	end

	pickers
		.new(opts, {
			prompt_title = "Silver Lining - PR Review",
			finder = finders.new_table({
				results = items,
				entry_maker = function(item)
					return {
						value = item,
						display = make_display,
						ordinal = (type_labels[item.type] or "") .. " " .. item.path .. " " .. item.text,
						filename = item.filename,
						lnum = item.lnum,
						col = 0,
						text = item.text,
						severity = item.type,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = review_previewer(),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					local entry = action_state.get_selected_entry()
					if entry then
						local bufnr = vim.fn.bufadd(entry.filename)
						vim.api.nvim_set_current_buf(bufnr)
						vim.bo[bufnr].buflisted = true
						vim.api.nvim_win_set_cursor(0, { entry.lnum, 0 })

						local sl = require("silver-lining")
						require("silver-lining.diagnostics").set(bufnr, sl._items)
						require("silver-lining.suggestions").show(bufnr, sl._items)
					end
				end)
				return true
			end,
		})
		:find()
end

local function pick_reviews(opts)
	opts = opts or {}
	local sl = require("silver-lining")

	-- If we already have cached items, open picker directly
	if #sl._items > 0 then
		open_picker(sl._items, opts)
		return
	end

	-- Otherwise fetch from GitHub first, then open picker
	sl.load_review(opts.pr_number, function(items)
		if #items > 0 then
			open_picker(items, opts)
		end
	end)
end

return telescope.register_extension({
	exports = {
		["silver-lining"] = pick_reviews,
	},
})
