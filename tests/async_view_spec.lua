package.path = table.concat({
	vim.fn.getcwd() .. "/lua/?.lua",
	vim.fn.getcwd() .. "/lua/?/init.lua",
	package.path,
}, ";")

local git = require("chunk.git")
local pending = {}
local original_collect_async = git.collect_async

git.collect_async = function(opts, callback)
	local request = { opts = opts, callback = callback, cancelled = false }
	table.insert(pending, request)
	return {
		cancel = function()
			request.cancelled = true
		end,
	}
end

local chunk = require("chunk")

local function collected(label)
	return {
		root = vim.fn.getcwd(),
		spec = { mode = "working_tree", pathspecs = {} },
		mutable = true,
		empty_message = "empty",
		sections = {
			{
				id = "unstaged",
				title = "Changes",
				diff = table.concat({
					"diff --git a/test.txt b/test.txt",
					"--- a/test.txt",
					"+++ b/test.txt",
					"@@ -1 +1 @@",
					"-old",
					"+" .. label,
				}, "\n") .. "\n",
			},
			{ id = "staged", title = "Staged Changes", diff = "" },
		},
	}
end

local function lines()
	return vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
end

local function complete(request, result, err)
	request.callback(result, err)
	vim.wait(1000, function()
		return not chunk.is_collecting()
	end, 5)
end

chunk.setup({ open_mode = "tab", files_panel = false })
chunk.open()
assert(lines()[1] == "Loading Git changes…", "initial view renders a loading state")

local scheduled = false
vim.schedule(function()
	scheduled = true
end)
assert(
	vim.wait(1000, function()
		return scheduled
	end, 5),
	"editor loop remains responsive while collection is pending"
)

complete(pending[1], collected("first"))
assert(vim.list_contains(lines(), "+first"), "initial collection renders")

chunk.refresh()
local refresh_a = pending[2]
chunk.refresh()
local refresh_b = pending[3]
assert(refresh_a.cancelled, "obsolete refresh is cancelled")
complete(refresh_b, collected("newest"))
refresh_a.callback(collected("stale"))
vim.wait(20)
assert(vim.list_contains(lines(), "+newest"), "newest refresh wins")
assert(not vim.list_contains(lines(), "+stale"), "stale refresh cannot overwrite the view")

local before_failure = table.concat(lines(), "\n")
local original_notify = vim.notify
vim.notify = function() end
chunk.refresh()
complete(pending[4], nil, "refresh failed")
vim.notify = original_notify
assert(table.concat(lines(), "\n") == before_failure, "failed refresh retains the last successful result")

chunk.refresh()
local closing = pending[5]
chunk.close()
assert(closing.cancelled, "closing cancels collection")
closing.callback(collected("too late"))
vim.wait(20)

git.collect_async = original_collect_async
print("ok 1 test")
