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
	require("silver-lining.comment").submit(event)
end, {
	nargs = "?",
	complete = function()
		return { "COMMENT", "APPROVE", "REQUEST_CHANGES" }
	end,
	desc = "Submit all drafts as a GitHub review",
})
