package.path =
	table.concat({ vim.fn.getcwd() .. "/lua/?.lua", vim.fn.getcwd() .. "/lua/?/init.lua", package.path }, ";")

local selected_file = require("chunk.selected_file")

local function run(argv, cwd)
	local result = vim.system(argv, { cwd = cwd, text = true }):wait()
	assert(result.code == 0, result.stderr or result.stdout)
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
run({ "git", "init", "-q" }, root)
run({ "git", "config", "user.name", "Chunk Test" }, root)
run({ "git", "config", "user.email", "chunk@example.com" }, root)

local path = root .. "/tracked.lua"
vim.fn.writefile({ "local value = 1", "return value" }, path)
run({ "git", "add", "tracked.lua" }, root)
run({ "git", "commit", "-qm", "initial" }, root)
vim.fn.writefile({ "local value = 2", "return value" }, path)

local unified_buf = vim.api.nvim_create_buf(false, true)
local win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(win, unified_buf)

local transitions = {}
local warnings = {}
local display = selected_file.new({
	win = win,
	buf = unified_buf,
	name = "chunk://selected-file-test",
	source_config = { enabled = true, debounce_ms = 0 },
	on_buffer = function(previous, current)
		table.insert(transitions, { previous, current })
	end,
	on_warning = function(message)
		table.insert(warnings, message)
	end,
})

local source_backed = selected_file.show(display, {
	root = root,
	spec = { mode = "working_tree" },
	file = { path = "tracked.lua", section = "unstaged", status = "modified", is_binary = false },
	lines = { { kind = "section_heading", text = "Unified fallback" } },
})
local source_buf = vim.api.nvim_win_get_buf(win)
assert(source_backed, "eligible working-tree files use the source-backed adapter")
assert(source_buf ~= unified_buf, "the source-backed adapter activates the canonical file buffer")
assert(vim.api.nvim_buf_get_name(source_buf) == path, "the selected file is shown in its canonical buffer")
assert(transitions[1][1] == unified_buf and transitions[1][2] == source_buf, "activation is reported")

source_backed = selected_file.show(display, {
	root = root,
	spec = { mode = "working_tree" },
	file = { path = "tracked.lua", section = "staged", status = "modified", is_binary = false },
	lines = { { kind = "section_heading", text = "Staged fallback" } },
})
assert(not source_backed, "unsupported selections use the unified adapter")
assert(vim.api.nvim_win_get_buf(win) == unified_buf, "the unified buffer is restored")
assert(vim.api.nvim_buf_get_lines(unified_buf, 0, -1, false)[1] == "Staged fallback", "fallback lines are rendered")
assert(vim.api.nvim_buf_is_valid(source_buf), "switching adapters preserves the canonical source buffer")
assert(transitions[2][1] == source_buf and transitions[2][2] == unified_buf, "fallback activation is reported")

source_backed = selected_file.show(display, {
	root = root,
	spec = { mode = "working_tree" },
	file = { path = "missing.lua", section = "unstaged", status = "modified", is_binary = false },
	lines = { { kind = "empty", text = "Missing fallback" } },
})
assert(not source_backed, "failed baseline lookup keeps the unified adapter active")
assert(#warnings == 1 and warnings[1]:match("Could not open source%-backed diff"), "lookup failures are reported")
assert(vim.api.nvim_buf_get_lines(unified_buf, 0, -1, false)[1] == "Missing fallback", "failure keeps fallback content")

source_backed = selected_file.show(display, {
	root = root,
	spec = { mode = "working_tree" },
	file = { path = "tracked.lua", section = "unstaged", status = "modified", is_binary = false },
	lines = {},
})
assert(source_backed, "the display can switch back to the source-backed adapter")
selected_file.close(display)
assert(not vim.api.nvim_buf_is_valid(unified_buf), "close deletes the display-owned unified buffer")
assert(vim.api.nvim_buf_is_valid(source_buf), "close preserves the canonical source buffer")
assert(transitions[#transitions][2] == nil, "close reports that no display buffer remains active")

vim.fn.delete(root, "rf")
print("ok 1 test")
