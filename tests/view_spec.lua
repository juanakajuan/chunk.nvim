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

local function buffer_keymap(buf, lhs)
	for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
		if keymap.lhs == lhs then
			return keymap
		end
	end
end

local function init_repo(root)
	run({ "git", "init", "-q" }, root)
	run({ "git", "config", "user.name", "Chunk Test" }, root)
	run({ "git", "config", "user.email", "chunk@example.com" }, root)
end

local function setup_changed_files_repo(root)
	init_repo(root)
	write_file(root .. "/a.txt", { "one" })
	run({ "git", "add", "a.txt" }, root)
	run({ "git", "commit", "-qm", "initial" }, root)

	write_file(root .. "/a.txt", { "one", "two" })
	write_file(root .. "/b.txt", { "new" })
end

local function setup_staged_and_unstaged_repo(root)
	init_repo(root)

	local lines = {}
	for index = 1, 16 do
		lines[index] = ("line %02d"):format(index)
	end

	write_file(root .. "/shared.txt", lines)
	run({ "git", "add", "shared.txt" }, root)
	run({ "git", "commit", "-qm", "initial" }, root)

	lines[2] = "staged line 02"
	write_file(root .. "/shared.txt", lines)
	run({ "git", "add", "shared.txt" }, root)

	lines[14] = "unstaged line 14"
	write_file(root .. "/shared.txt", lines)
end

local function with_repo(setup, fn)
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")

	local ok, err = xpcall(function()
		setup(root)
		fn(root)
	end, debug.traceback)

	vim.fn.delete(root, "rf")

	if not ok then
		error(err, 0)
	end
end

local function with_changed_files_repo(fn)
	with_repo(setup_changed_files_repo, fn)
end

local function with_staged_and_unstaged_repo(fn)
	with_repo(setup_staged_and_unstaged_repo, fn)
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

local function open_chunk(root, filename, options)
	chunk.setup(vim.tbl_extend("force", { open_mode = "tab" }, options or {}))
	vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. filename))
	chunk.open()

	return find_chunk_windows()
end

local function with_hunk_keymaps(keymaps, fn)
	with_staged_and_unstaged_repo(function(root)
		local diff_win = open_chunk(root, "shared.txt", { keymaps = keymaps })
		fn(vim.api.nvim_win_get_buf(diff_win))
		chunk.close()
	end)
end

local function test_files_panel_selects_file_diff()
	with_changed_files_repo(function(root)
		local diff_win, files_win = open_chunk(root, "a.txt", {
			files_panel = {
				enabled = true,
				width = 24,
			},
		})

		assert(diff_win, "diff window exists")
		assert(files_win, "files window exists")
		assert_equal(#vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage()), 2, "chunk window count")

		local file_lines = window_lines(files_win)
		assert_equal(#file_lines, 3, "files panel line count")
		assert_equal(file_lines[1], "Changes", "files section heading")
		assert_match(file_lines[2], "^ M a%.txt", "modified file row")
		assert_match(file_lines[3], "^ A b%.txt", "added file row")

		vim.api.nvim_set_current_win(files_win)
		vim.api.nvim_win_set_cursor(files_win, { 3, 0 })
		chunk.select_file_at_cursor()

		assert_equal(vim.api.nvim_get_current_win(), diff_win, "select focuses diff window")
		assert_match(current_window_line(diff_win), "b%.txt", "selected file diff header")

		chunk.jump("file_header", -1)

		assert_match(current_window_line(diff_win), "a%.txt", "previous file diff header")
		assert_equal(vim.api.nvim_win_get_cursor(files_win)[1], 2, "files panel cursor sync")

		chunk.close()
	end)
end

local function test_staged_and_unstaged_sections_distinguish_same_path()
	with_staged_and_unstaged_repo(function(root)
		local diff_win, files_win = open_chunk(root, "shared.txt", {
			context_lines = 1,
			files_panel = {
				enabled = true,
				width = 24,
			},
		})

		local file_lines = window_lines(files_win)
		local diff_buf = vim.api.nvim_win_get_buf(diff_win)
		assert_equal(buffer_keymap(diff_buf, "s").desc, "Stage hunk", "default stage mapping")
		assert_equal(buffer_keymap(diff_buf, "u").desc, "Unstage hunk", "default unstage mapping")
		assert_equal(file_lines[1], "Changes", "unstaged files section heading")
		assert_match(file_lines[2], "^ M shared%.txt", "unstaged file row")
		assert_equal(file_lines[3], "Staged Changes", "staged files section heading")
		assert_match(file_lines[4], "^ M shared%.txt", "staged file row")

		local diff_lines = window_lines(diff_win)
		assert_equal(diff_lines[1], "Changes", "unstaged diff section heading")
		assert(vim.list_contains(diff_lines, "+unstaged line 14"), "unstaged hunk is rendered")
		assert(vim.list_contains(diff_lines, "Staged Changes"), "staged diff section heading is rendered")
		assert(vim.list_contains(diff_lines, "+staged line 02"), "staged hunk is rendered")

		local staged_heading_row = vim.fn.index(diff_lines, "Staged Changes") + 1
		vim.api.nvim_set_current_win(files_win)
		vim.api.nvim_win_set_cursor(files_win, { 4, 0 })
		chunk.select_file_at_cursor()
		assert(
			vim.api.nvim_win_get_cursor(diff_win)[1] > staged_heading_row,
			"staged path selects the staged file entry"
		)

		chunk.jump("file_header", -1)
		assert(
			vim.api.nvim_win_get_cursor(diff_win)[1] < staged_heading_row,
			"file navigation reaches the distinct unstaged entry"
		)
		assert_equal(vim.api.nvim_win_get_cursor(files_win)[1], 2, "sidebar selection follows section-aware navigation")

		chunk.close()
	end)
end

local function test_hunk_action_mappings_can_be_overridden()
	with_hunk_keymaps({
		stage_hunk = "S",
		unstage_hunk = "U",
	}, function(diff_buf)
		assert_equal(buffer_keymap(diff_buf, "S").desc, "Stage hunk", "custom stage mapping")
		assert_equal(buffer_keymap(diff_buf, "U").desc, "Unstage hunk", "custom unstage mapping")
		assert_equal(buffer_keymap(diff_buf, "s"), nil, "default stage mapping is replaced")
		assert_equal(buffer_keymap(diff_buf, "u"), nil, "default unstage mapping is replaced")
	end)
end

local function test_hunk_action_mappings_can_be_disabled()
	with_hunk_keymaps({
		stage_hunk = false,
		unstage_hunk = false,
	}, function(diff_buf)
		assert_equal(buffer_keymap(diff_buf, "s"), nil, "stage mapping can be disabled")
		assert_equal(buffer_keymap(diff_buf, "u"), nil, "unstage mapping can be disabled")
	end)
end

local tests = {
	test_files_panel_selects_file_diff,
	test_staged_and_unstaged_sections_distinguish_same_path,
	test_hunk_action_mappings_can_be_overridden,
	test_hunk_action_mappings_can_be_disabled,
}

for _, test in ipairs(tests) do
	test()
end

print(("ok %d tests"):format(#tests))
