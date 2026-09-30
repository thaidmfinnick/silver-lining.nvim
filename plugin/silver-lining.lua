if vim.g.loaded_silver_lining then
	return
end
vim.g.loaded_silver_lining = true

vim.api.nvim_create_user_command("SilverLining", function(opts)
	local args = opts.fargs
	local pr_number = tonumber(args[1])

	if #args > 0 and not pr_number then
		vim.notify("[silver-lining] Usage: :SilverLining [pr_number]", vim.log.levels.WARN)
		return
	end

	local has_telescope = pcall(require, "telescope")
	if has_telescope then
		require("telescope").extensions["silver-lining"]["silver-lining"]({ pr_number = pr_number })
	else
		require("silver-lining").load_review(pr_number, function()
			vim.cmd("copen")
		end)
	end
end, {
	nargs = "?",
	desc = "Load GitHub PR review comments",
})

vim.api.nvim_create_user_command("SilverLiningClear", function()
	require("silver-lining.suggestions").clear()
	require("silver-lining.diagnostics").clear()
	require("silver-lining")._items = {}
	vim.notify("[silver-lining] Cleared all reviews", vim.log.levels.INFO)
end, {
	desc = "Clear all Silver Lining suggestions and diagnostics",
})

vim.api.nvim_create_user_command("SilverLiningComment", function()
	require("silver-lining.comment").open("comment")
end, {
	range = true,
	desc = "Create a comment draft on selected lines",
})

vim.api.nvim_create_user_command("SilverLiningSuggestion", function()
	require("silver-lining.comment").open("suggestion")
end, {
	range = true,
	desc = "Create a suggestion draft on selected lines",
})

vim.api.nvim_create_user_command("SilverLiningDrafts", function()
	require("silver-lining.comment").open_picker()
end, {
	desc = "Preview and manage pending comment drafts",
})

vim.api.nvim_create_user_command("SilverLiningSubmit", function(opts)
	local event = opts.fargs[1]
	local ids
	if #opts.fargs > 1 then
		ids = {}
		for i = 2, #opts.fargs do
			local id = tonumber(opts.fargs[i])
			if not id then
				vim.notify("[silver-lining] Usage: :SilverLiningSubmit [event] [draft_id...]", vim.log.levels.WARN)
				return
			end
			table.insert(ids, id)
		end
	end
	require("silver-lining.comment").submit(event, ids)
end, {
	nargs = "*",
	complete = function(_, cmdline)
		if #vim.split(cmdline, "%s+") <= 2 then
			return { "COMMENT", "APPROVE", "REQUEST_CHANGES" }
		end
		local ids = {}
		if package.loaded["silver-lining.comment"] then
			for _, d in ipairs(require("silver-lining.comment").get_drafts()) do
				table.insert(ids, tostring(d.id))
			end
		end
		return ids
	end,
	desc = "Submit drafts as a GitHub review (all, or only the given draft ids)",
})

-- Show review comments and pending drafts inline in any buffer you open
local group = vim.api.nvim_create_augroup("SilverLining", { clear = true })
vim.api.nvim_create_autocmd("BufWinEnter", {
	group = group,
	callback = function(args)
		if package.loaded["silver-lining.comment"] then
			require("silver-lining.comment").render_drafts(args.buf)
		end
		local sl = package.loaded["silver-lining"]
		if sl and sl._items and #sl._items > 0 then
			require("silver-lining.suggestions").show(args.buf, sl._items)
			require("silver-lining.diagnostics").set(args.buf, sl._items)
		end
	end,
})
