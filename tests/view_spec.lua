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
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
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

local function has_line_highlight(buf, group)
	return vim.iter(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })):any(function(mark)
		return mark[4].line_hl_group == group
	end)
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
	write_file(root .. "/nested/b.txt", { "new" })
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
	assert(
		vim.wait(5000, function()
			return not chunk.is_collecting()
		end, 10),
		"Chunk collection completed"
	)

	local diff_win, files_win = find_chunk_windows()
	assert(diff_win, "diff window exists")
	assert(files_win, "files window exists")
	return diff_win, files_win
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
		assert_equal(vim.api.nvim_get_current_win(), files_win, "files panel has initial focus")
		vim.wait(100, function()
			return false
		end, 10)
		assert_equal(vim.api.nvim_win_get_cursor(files_win)[1], 2, "files panel starts on its first tree entry")
		assert(not has_line_highlight(vim.api.nvim_win_get_buf(files_win), "ChunkFileSelected"), "root owns initial selection")

		local file_lines = window_lines(files_win)
		assert_equal(#file_lines, 5, "files panel line count")
		assert_equal(file_lines[1], "Changes", "files section heading")
		assert_match(file_lines[2], "^▾ .+ /$", "repository root row")
		assert_match(file_lines[3], "^     a%.txt%s+%+1$", "modified root file row")
		assert_match(file_lines[4], "^  ▾ .+ nested/$", "directory row")
		assert_match(file_lines[5], "^       b%.txt%s+%+1$", "nested added file row")
		assert_equal(vim.api.nvim_get_option_value("winbar", { win = files_win }), "", "files panel has no header")
		local initial_diff_lines = window_lines(diff_win)
		assert(vim.list_contains(initial_diff_lines, "diff --git a/a.txt b/a.txt"), "initial file diff is rendered")
		assert(
			not vim.list_contains(initial_diff_lines, "diff --git a/nested/b.txt b/nested/b.txt"),
			"other file is excluded"
		)
		local diff_buf = vim.api.nvim_win_get_buf(diff_win)
		assert_equal(buffer_keymap(diff_buf, "]f"), nil, "diff has no next-file mapping")
		assert_equal(buffer_keymap(diff_buf, "[f"), nil, "diff has no previous-file mapping")

		vim.cmd.normal({ "2j", bang = true })
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_win_get_buf(files_win) })
		assert(vim.wait(1000, function()
			return current_window_line(diff_win):match("b%.txt") ~= nil
		end), "folder navigation previews its first nested file")

		assert_equal(vim.api.nvim_get_current_win(), files_win, "cursor navigation keeps sidebar focus")
		assert_equal(vim.api.nvim_win_get_cursor(files_win)[1], 4, "cursor remains on the nested folder")
		assert(not has_line_highlight(vim.api.nvim_win_get_buf(files_win), "ChunkFileSelected"), "folder owns selection")

		vim.cmd.normal({ "j", bang = true })
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_win_get_buf(files_win) })
		vim.wait(100, function()
			return false
		end, 10)
		assert_equal(vim.api.nvim_win_get_cursor(files_win)[1], 5, "cursor moves to the nested changed file")
		assert_match(current_window_line(diff_win), "b%.txt", "selected file diff header")
		local selected_diff_lines = window_lines(diff_win)
		assert(
			vim.list_contains(selected_diff_lines, "diff --git a/nested/b.txt b/nested/b.txt"),
			"selected file is rendered"
		)
		assert(not vim.list_contains(selected_diff_lines, "diff --git a/a.txt b/a.txt"), "previous file is removed")

		chunk.select_file_at_cursor()
		assert_equal(vim.api.nvim_get_current_win(), diff_win, "explicit selection still focuses the diff")
		vim.api.nvim_set_current_win(files_win)
		vim.cmd.normal({ "2k", bang = true })
		vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_win_get_buf(files_win) })
		assert(vim.wait(1000, function()
			return current_window_line(diff_win):match("a%.txt") ~= nil
		end), "cursor navigation updates the next file diff")
		assert_equal(vim.api.nvim_win_get_cursor(files_win)[1], 3, "cursor moves to the root changed file")
		assert_match(current_window_line(diff_win), "a%.txt", "cursor navigation updates the diff")

		vim.api.nvim_win_set_cursor(files_win, { 3, 0 })
		chunk.select_relative_file(1)
		assert_equal(vim.api.nvim_get_current_win(), files_win, "sidebar navigation keeps sidebar focus")
		assert_equal(vim.api.nvim_win_get_cursor(files_win)[1], 5, "sidebar navigation follows tree order")
		assert_match(current_window_line(diff_win), "b%.txt", "tree navigation selects the nested file")

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
		assert_match(file_lines[2], "^▾ .+ /$", "unstaged root row")
		assert_match(file_lines[3], "^     shared%.txt%s+%+1 %-1$", "unstaged file row")
		assert_equal(file_lines[4], "Staged Changes", "staged files section heading")
		assert_match(file_lines[5], "^▾ .+ /$", "staged root row")
		assert_match(file_lines[6], "^     shared%.txt%s+%+1 %-1$", "staged file row")

		local diff_lines = window_lines(diff_win)
		assert_equal(diff_lines[1], "Changes", "unstaged diff section heading")
		assert(vim.list_contains(diff_lines, "+unstaged line 14"), "unstaged hunk is rendered")
		assert(not vim.list_contains(diff_lines, "Staged Changes"), "staged section is excluded")
		assert(not vim.list_contains(diff_lines, "+staged line 02"), "staged hunk is excluded")

		vim.api.nvim_set_current_win(files_win)
		vim.api.nvim_win_set_cursor(files_win, { 6, 0 })
		chunk.select_file_at_cursor()
		diff_lines = window_lines(diff_win)
		assert_equal(diff_lines[1], "Staged Changes", "selected staged section is rendered")
		assert(vim.list_contains(diff_lines, "+staged line 02"), "selected staged hunk is rendered")
		assert(not vim.list_contains(diff_lines, "+unstaged line 14"), "unstaged hunk is excluded")
		assert_equal(vim.api.nvim_win_get_cursor(files_win)[1], 6, "sidebar keeps the selected staged entry")

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
