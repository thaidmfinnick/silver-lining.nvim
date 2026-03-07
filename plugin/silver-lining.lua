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

	require("telescope").extensions["silver-lining"]["silver-lining"]({ pr_number = pr_number })
end, {
	nargs = "?",
	desc = "Load GitHub PR review comments into Telescope",
})

vim.api.nvim_create_user_command("SilverLiningClear", function()
	require("silver-lining.suggestions").clear()
	require("silver-lining.diagnostics").clear()
	require("silver-lining")._items = {}
	vim.notify("[silver-lining] Cleared all reviews", vim.log.levels.INFO)
end, {
	desc = "Clear all Silver Lining suggestions and diagnostics",
})
