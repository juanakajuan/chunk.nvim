package.path = table.concat({
	vim.fn.getcwd() .. "/lua/?.lua",
	vim.fn.getcwd() .. "/lua/?/init.lua",
	package.path,
}, ";")

local pending = {}
local git = require("chunk.git")
local original_collect = git.collect

rawset(git, "collect", function(_, callback)
	local request = { callback = callback, cancelled = false }
	request.cancel = function()
		request.cancelled = true
	end
	table.insert(pending, request)
	return request
end)

local chunk = require("chunk")

dofile(vim.fn.getcwd() .. "/plugin/chunk.lua")
local commands = vim.api.nvim_get_commands({ builtin = false })
assert(commands.Chunk, ":Chunk command remains available")
assert(not commands.ChunkRefresh, "manual refresh command is removed")

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

local function complete(request, result)
	request.callback(result)
	assert(
		vim.wait(1000, function()
			return not chunk.is_collecting()
		end, 5),
		"collection completes"
	)
end

chunk.setup({ open_mode = "tab", files_panel = false })
chunk.open()
complete(pending[1], collected("first"))

for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
	assert(keymap.lhs ~= "R", "manual refresh mapping is removed")
end

vim.api.nvim_exec_autocmds("BufWritePost", { buffer = vim.api.nvim_get_current_buf() })
vim.api.nvim_exec_autocmds("BufWritePost", { buffer = vim.api.nvim_get_current_buf() })
assert(
	vim.wait(1000, function()
		return #pending == 2
	end, 5),
	"saving starts an automatic refresh"
)
assert(#pending == 2, "bursts of change events are debounced")

complete(pending[2], collected("automatic"))
local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
assert(vim.list_contains(lines, "+automatic"), "automatic refresh renders new Git changes")

chunk.close()
rawset(git, "collect", original_collect)
print("ok 1 test")
