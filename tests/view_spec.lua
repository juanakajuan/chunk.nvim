package.path = table.concat({
	vim.fn.getcwd() .. "/lua/?.lua",
	vim.fn.getcwd() .. "/lua/?/init.lua",
	package.path,
}, ";")

local chunk = require("chunk")

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)), 2)
	end
end

local function assert_match(value, pattern, message)
	if not value:match(pattern) then
		error(("%s: expected %s to match %s"):format(message, vim.inspect(value), vim.inspect(pattern)), 2)
	end
end

local function run(argv, cwd)
	local result = vim.system(argv, {
		cwd = cwd,
		text = true,
	}):wait()

	if result.code ~= 0 then
		error(("command failed: %s\n%s"):format(table.concat(argv, " "), result.stderr or result.stdout or ""), 2)
	end

	return result.stdout or ""
end

local function write_file(path, lines)
	vim.fn.writefile(lines, path)
end

local function window_lines(win)
	return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

local function current_window_line(win)
	local line = vim.api.nvim_win_get_cursor(win)[1]
	return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), line - 1, line, false)[1]
end

local function setup_changed_files_repo(root)
	run({ "git", "init", "-q" }, root)
	run({ "git", "config", "user.name", "Chunk Test" }, root)
	run({ "git", "config", "user.email", "chunk@example.com" }, root)

	write_file(root .. "/a.txt", { "one" })
	run({ "git", "add", "a.txt" }, root)
	run({ "git", "commit", "-qm", "initial" }, root)

	write_file(root .. "/a.txt", { "one", "two" })
	write_file(root .. "/b.txt", { "new" })
end

local function with_changed_files_repo(fn)
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")

	local ok, err = xpcall(function()
		setup_changed_files_repo(root)
		fn(root)
	end, debug.traceback)

	vim.fn.delete(root, "rf")

	if not ok then
		error(err, 0)
	end
end

local function find_chunk_windows()
	local diff_win = nil
	local files_win = nil

	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())) do
		local buf = vim.api.nvim_win_get_buf(win)
		local filetype = vim.api.nvim_get_option_value("filetype", {
			buf = buf,
		})

		if filetype == "diff" then
			diff_win = win
		elseif filetype == "chunkfiles" then
			files_win = win
		end
	end

	return diff_win, files_win
end

local function test_files_panel_selects_file_diff()
	with_changed_files_repo(function(root)
		chunk.setup({
			open_mode = "tab",
			files_panel = {
				enabled = true,
				width = 24,
			},
		})

		vim.cmd.edit(vim.fn.fnameescape(root .. "/a.txt"))
		chunk.open()

		local diff_win, files_win = find_chunk_windows()
		assert(diff_win, "diff window exists")
		assert(files_win, "files window exists")
		assert_equal(#vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage()), 2, "chunk window count")

		local file_lines = window_lines(files_win)
		assert_equal(#file_lines, 2, "files panel line count")
		assert_match(file_lines[1], "^ M a%.txt", "modified file row")
		assert_match(file_lines[2], "^ A b%.txt", "added file row")

		vim.api.nvim_set_current_win(files_win)
		vim.api.nvim_win_set_cursor(files_win, { 2, 0 })
		chunk.select_file_at_cursor()

		assert_equal(vim.api.nvim_get_current_win(), diff_win, "select focuses diff window")
		assert_match(current_window_line(diff_win), "b%.txt", "selected file diff header")

		chunk.jump("file_header", -1)

		assert_match(current_window_line(diff_win), "a%.txt", "previous file diff header")
		assert_equal(vim.api.nvim_win_get_cursor(files_win)[1], 1, "files panel cursor sync")
	end)
end

local tests = {
	test_files_panel_selects_file_diff,
}

for _, test in ipairs(tests) do
	test()
end

print(("ok %d tests"):format(#tests))
