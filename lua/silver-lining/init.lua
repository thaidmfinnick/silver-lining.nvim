local parser = require("silver-lining.parser")
local config = require("silver-lining.config")

local M = {}

-- Cache parsed items so telescope can access without re-fetching
M._items = {}

--- Setup the plugin with user options
---@param opts? silver-lining.Config
function M.setup(opts)
	config.setup(opts)
end

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---@return fun() stop function
local function start_spinner()
	local idx = 1
	local timer = vim.uv.new_timer()
	timer:start(
		0,
		80,
		vim.schedule_wrap(function()
			idx = (idx % #spinner_frames) + 1
			vim.api.nvim_echo(
				{ { spinner_frames[idx] .. " [silver-lining] Fetching PR review comments...", "Comment" } },
				false,
				{}
			)
		end)
	)

	return function()
		timer:stop()
		timer:close()
		vim.api.nvim_echo({ { "" } }, false, {})
	end
end

--- Run a shell command async and return output via callback
---@param cmd string
---@param callback fun(output: string?, err: string?)
local function async_cmd(cmd, callback)
	local stdout_data = {}
	local stderr_data = {}

	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			stdout_data = data
		end,
		on_stderr = function(_, data)
			stderr_data = data
		end,
		on_exit = function(_, exit_code)
			vim.schedule(function()
				local out = vim.trim(table.concat(stdout_data, "\n"))
				local err = vim.trim(table.concat(stderr_data, "\n"))
				if exit_code == 0 and out ~= "" then
					callback(out, nil)
				else
					callback(nil, err ~= "" and err or "Command failed")
				end
			end)
		end,
	})
end

--- Detect repo async, then call callback with result
---@param callback fun(repo: string?)
local function detect_repo_async(callback)
	async_cmd("gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null", function(out)
		callback(out)
	end)
end

--- Detect PR number async, then call callback with result
---@param callback fun(pr_number: number?)
local function detect_pr_number_async(callback)
	async_cmd("gh pr view --json number -q .number 2>/dev/null", function(out)
		callback(out and tonumber(out) or nil)
	end)
end

--- Fetch PR review comments (fully async, never blocks)
---@param pr_number? number PR number (auto-detects from current branch if omitted)
---@param on_done? fun(items: silver-lining.ReviewComment[]) callback with parsed items
function M.load_review(pr_number, on_done)
	local cfg = config.get()
	local stop_spinner = start_spinner()

	local function fetch_comments(repo, pr_num)
		-- Validate repo format to prevent command injection
		if not repo:match("^[%w%.%-_]+/[%w%.%-_]+$") then
			stop_spinner()
			vim.notify("[silver-lining] Invalid repo format: " .. repo, vim.log.levels.ERROR)
			return
		end

		local owner, name = repo:match("^([^/]+)/(.+)$")
		-- stylua: ignore
		local query = table.concat({
			"query($owner: String!, $name: String!, $pr: Int!, $cursor: String) {",
			"  repository(owner: $owner, name: $name) {",
			"    pullRequest(number: $pr) {",
			"      reviewThreads(first: 100, after: $cursor) {",
			"        pageInfo { hasNextPage endCursor }",
			"        nodes {",
			"          isResolved",
			"          comments(first: 100) {",
			"            nodes {",
			"              databaseId path body line startLine",
			"              originalLine originalStartLine diffHunk",
			"              commit { oid } originalCommit { oid }",
			"              author { login } createdAt",
			"            }",
			"          }",
			"        }",
			"      }",
			"    }",
			"  }",
			"}",
		}, "\n")

		local cmd = string.format(
			"gh api graphql --paginate -F owner=%s -F name=%s -F pr=%d -f query=%s",
			vim.fn.shellescape(owner),
			vim.fn.shellescape(name),
			pr_num,
			vim.fn.shellescape(query)
		)

		async_cmd(cmd, function(output, err)
			stop_spinner()

			if not output then
				vim.notify("[silver-lining] " .. (err or "No output from gh api"), vim.log.levels.ERROR)
				return
			end

			local ok, json = pcall(vim.json.decode, output)
			if not ok then
				vim.notify("[silver-lining] Failed to parse API response", vim.log.levels.ERROR)
				return
			end

			if type(json) ~= "table" then
				vim.notify("[silver-lining] Unexpected API response format", vim.log.levels.ERROR)
				return
			end

			if json.errors then
				local msg = json.errors[1] and json.errors[1].message or "Unknown GraphQL error"
				vim.notify("[silver-lining] GitHub API: " .. msg, vim.log.levels.ERROR)
				return
			end

			-- Extract unresolved thread comments and transform to REST-compatible format
			local threads = json.data
				and json.data.repository
				and json.data.repository.pullRequest
				and json.data.repository.pullRequest.reviewThreads
				and json.data.repository.pullRequest.reviewThreads.nodes
			if not threads then
				vim.notify("[silver-lining] Unexpected API response structure", vim.log.levels.ERROR)
				return
			end

			local comments = {}
			for _, thread in ipairs(threads) do
				if not thread.isResolved then
					for _, c in ipairs(thread.comments.nodes) do
						table.insert(comments, {
							id = c.databaseId,
							path = c.path,
							body = c.body,
							line = c.line,
							start_line = c.startLine,
							original_line = c.originalLine,
							original_start_line = c.originalStartLine,
							diff_hunk = c.diffHunk,
							commit_id = c.commit and c.commit.oid,
							original_commit_id = c.originalCommit and c.originalCommit.oid,
							user = { login = c.author and c.author.login },
							created_at = c.createdAt,
							side = "RIGHT",
						})
					end
				end
			end

			local items = parser.parse_review_comments(comments)
			M._items = items

			if #items == 0 then
				vim.notify("[silver-lining] No review comments found", vim.log.levels.INFO)
				if on_done then
					on_done(items)
				end
				return
			end

			vim.fn.setqflist({}, " ", {
				title = "Silver Lining - PR Review",
				items = items,
			})

			vim.notify(string.format("[silver-lining] Loaded %d review comments", #items), vim.log.levels.INFO)

			if on_done then
				on_done(items)
			end
		end)
	end

	-- Resolve repo (async if needed)
	local function with_repo(repo)
		if not repo then
			stop_spinner()
			vim.notify("[silver-lining] Could not detect repo. Set repo in config.", vim.log.levels.ERROR)
			return
		end

		-- Resolve PR number (async if needed)
		if pr_number then
			fetch_comments(repo, pr_number)
		else
			detect_pr_number_async(function(pr_num)
				if not pr_num then
					stop_spinner()
					vim.notify("[silver-lining] Could not detect PR number. Pass it as argument.", vim.log.levels.ERROR)
					return
				end
				fetch_comments(repo, pr_num)
			end)
		end
	end

	if cfg.repo then
		with_repo(cfg.repo)
	else
		detect_repo_async(with_repo)
	end
end

return M
