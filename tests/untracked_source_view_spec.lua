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
vim.fn.writefile({ "# fixture" }, root .. "/README.md")
run({ "git", "add", "README.md" }, root)
run({ "git", "commit", "-qm", "initial" }, root)
vim.fn.writefile({ "# changed fixture" }, root .. "/README.md")

local path = root .. "/sample.lua"
vim.fn.writefile({ "local answer = 42", "return answer" }, path)
vim.cmd.edit(vim.fn.fnameescape(root .. "/README.md"))

local diagnostic_namespace = vim.api.nvim_create_namespace("chunk_untracked_source_test")
vim.api.nvim_create_autocmd("FileType", {
	pattern = "lua",
	once = true,
	callback = function(args)
		vim.b[args.buf].lsp_fixture_attached = true
		vim.keymap.set("n", "gd", function() end, { buffer = args.buf, desc = "Fixture definition" })
		vim.diagnostic.set(diagnostic_namespace, args.buf, {
			{ lnum = 0, col = 0, message = "fixture diagnostic" },
		})
	end,
})

chunk.setup({
	open_mode = "tab",
	files_panel = true,
	source_view = { enabled = true, debounce_ms = 5 },
})
chunk.open()
assert(
	vim.wait(5000, function()
		return not chunk.is_collecting()
	end, 10),
	"collection completed"
)

local files_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "chunkfiles" then
		files_win = win
		break
	end
end
assert(files_win, "files panel exists")

local files_buf = vim.api.nvim_win_get_buf(files_win)
for row, line in ipairs(vim.api.nvim_buf_get_lines(files_buf, 0, -1, false)) do
	if line:match("sample%.lua") then
		vim.api.nvim_set_current_win(files_win)
		vim.api.nvim_win_set_cursor(files_win, { row, 0 })
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = files_buf })
		break
	end
end

local source_buf
local source_win
assert(vim.wait(1000, function()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.api.nvim_buf_get_name(buf) == path then
			source_buf = buf
			source_win = win
			return true
		end
	end
	return false
end), "cursor navigation shows the previously unloaded source file")

assert(source_win, "the canonical untracked source buffer is shown in the Chunk tab")
assert(vim.bo[source_buf].buftype == "", "source buftype is preserved")
assert(vim.bo[source_buf].filetype == "lua", "source filetype is preserved")
assert(vim.b[source_buf].lsp_fixture_attached == true, "FileType attachment hooks run")
assert(vim.iter(vim.api.nvim_buf_get_keymap(source_buf, "n")):any(function(keymap)
	return keymap.lhs == "gd"
end), "buffer-local LSP-style keymaps are available")
assert(#vim.diagnostic.get(source_buf) == 1, "buffer diagnostics are available")

chunk.close()
vim.fn.delete(root, "rf")
print("ok 1 test")
