package.path =
	table.concat({ vim.fn.getcwd() .. "/lua/?.lua", vim.fn.getcwd() .. "/lua/?/init.lua", package.path }, ";")

local chunk = require("chunk")

local function run(argv, cwd)
	local result = vim.system(argv, { cwd = cwd, text = true }):wait()
	assert(result.code == 0, result.stderr or result.stdout)
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
run({ "git", "init", "-q" }, root)
run({ "git", "config", "user.name", "Chunk Test" }, root)
run({ "git", "config", "user.email", "chunk@example.com" }, root)
local path = root .. "/sample.lua"
vim.fn.writefile({
	"-- keep 1",
	"-- keep 2",
	"local one = 1",
	"-- keep 4",
	"-- keep 5",
	"local removed = true",
	"-- keep 7",
	"-- keep 8",
	"return one",
	"-- keep 10",
}, path)
run({ "git", "add", "sample.lua" }, root)
run({ "git", "commit", "-qm", "initial" }, root)
vim.fn.writefile({
	"-- keep 1",
	"-- keep 2",
	"local one = 2",
	"-- keep 4",
	"-- keep 5",
	"-- keep 7",
	"-- keep 8",
	"return one",
	"-- keep 10",
}, path)

vim.cmd.edit(vim.fn.fnameescape(path))
local original = vim.api.nvim_get_current_buf()
local original_win = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(original, 7, 8, false, { "return one -- unsaved" })
chunk.setup({
	open_mode = "tab",
	files_panel = true,
	source_view = { enabled = true, debounce_ms = 5, fold_unchanged = true, context_lines = 0 },
})
chunk.open()
assert(
	vim.wait(5000, function()
		return not chunk.is_collecting()
	end, 10),
	"collection completed"
)

local source_buf
local source_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.api.nvim_buf_get_name(buf) == path then
		source_buf = buf
		source_win = win
	end
end
assert(source_buf == original, "the existing canonical source buffer is reused")
assert(vim.bo[source_buf].buftype == "", "source buftype is preserved")
assert(vim.bo[source_buf].filetype == "lua", "source filetype is preserved")
local lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
assert(lines[8] == "return one -- unsaved", "unsaved text is preserved")
assert(#lines == 9, "virtual deletions do not alter text")
assert(vim.api.nvim_win_call(source_win, function()
	return vim.fn.foldclosed(1)
end) == 1, "unchanged source lines are folded in the Chunk window")
assert(vim.api.nvim_win_call(original_win, function()
	return vim.fn.foldclosed(1)
end) == -1, "folds do not affect another source window")

local marks = vim.api.nvim_buf_get_extmarks(source_buf, -1, 0, -1, { details = true })
assert(#marks >= 2, "changed and deleted lines are decorated")
assert(
	vim.iter(marks):any(function(mark)
		return mark[4].virt_lines ~= nil
	end),
	"deleted baseline lines are virtual"
)
local decoration_namespaces = {}
for _, mark in ipairs(marks) do
	if mark[4].virt_lines ~= nil then
		decoration_namespaces[mark[4].ns_id] = true
	end
end

vim.api.nvim_buf_set_lines(source_buf, 7, 8, false, { "return one -- written" })
vim.api.nvim_buf_call(source_buf, function()
	vim.cmd.write()
end)
assert(vim.fn.readfile(path)[8] == "return one -- written", "write updates the working-tree file")
chunk.close()
assert(vim.api.nvim_buf_is_valid(source_buf), "closing Chunk keeps the source buffer")
assert(
	not vim.iter(vim.api.nvim_buf_get_extmarks(source_buf, -1, 0, -1, { details = true })):any(function(mark)
		return decoration_namespaces[mark[4].ns_id] == true
	end),
	"closing clears Chunk decorations"
)

vim.fn.delete(root, "rf")
print("ok 1 test")
