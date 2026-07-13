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

local function assert_contains(value, expected, message)
	if not value:find(expected, 1, true) then
		error(("%s: expected %s to contain %s"):format(message, vim.inspect(value), vim.inspect(expected)), 2)
	end
end

local function assert_not_contains(value, unexpected, message)
	if value:find(unexpected, 1, true) then
		error(("%s: expected %s not to contain %s"):format(message, vim.inspect(value), vim.inspect(unexpected)), 2)
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

local function read_file(path)
	return table.concat(vim.fn.readfile(path), "\n") .. "\n"
end

local function setup_repo(root)
	run({ "git", "init", "-q" }, root)
	run({ "git", "config", "user.name", "Chunk Test" }, root)
	run({ "git", "config", "user.email", "chunk@example.com" }, root)

	local lines = {}
	for index = 1, 18 do
		lines[index] = ("line %02d"):format(index)
	end

	write_file(root .. "/shared.txt", lines)
	run({ "git", "add", "shared.txt" }, root)
	run({ "git", "commit", "-qm", "initial" }, root)

	lines[2] = "staged line 02"
	write_file(root .. "/shared.txt", lines)
	run({ "git", "add", "shared.txt" }, root)

	lines[9] = "unrelated unstaged line 09"
	lines[16] = "unstaged line 16"
	write_file(root .. "/shared.txt", lines)
end

local function with_repo(fn)
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")

	local ok, err = xpcall(function()
		setup_repo(root)
		fn(root)
	end, debug.traceback)

	vim.fn.delete(root, "rf")
	if not ok then
		error(err, 0)
	end
end

local function find_diff_window()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage())) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.api.nvim_get_option_value("filetype", { buf = buf }) == "diff" then
			return win
		end
	end
end

local function find_line(win, text)
	local buf = vim.api.nvim_win_get_buf(win)
	for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if line == text then
			return row
		end
	end
end

local function window_lines(win)
	return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

local function capture_notification(fn)
	local original_notify = vim.notify
	local notification = nil
	rawset(vim, "notify", function(message, level)
		notification = {
			message = message,
			level = level,
		}
	end)

	local ok, err = xpcall(fn, debug.traceback)
	rawset(vim, "notify", original_notify)
	if not ok then
		error(err, 0)
	end

	return notification
end

local function open_chunk_view(root, selected_line)
	chunk.setup({
		context_lines = 1,
		open_mode = "tab",
	})
	vim.cmd.edit(vim.fn.fnameescape(root .. "/shared.txt"))
	chunk.open()
	assert(
		vim.wait(5000, function()
			return not chunk.is_collecting()
		end, 10),
		"Chunk collection completed"
	)

	local diff_win = assert(find_diff_window(), "diff window was not opened")
	local row = assert(find_line(diff_win, selected_line), "selected line was not rendered")
	vim.api.nvim_set_current_win(diff_win)
	vim.api.nvim_win_set_cursor(diff_win, { row, 0 })
	return diff_win
end

local function test_stage_and_unstage_hunk_update_only_index_and_follow_selection()
	with_repo(function(root)
		local working_before = read_file(root .. "/shared.txt")
		local index_before = run({ "git", "show", ":shared.txt" }, root)
		assert_contains(index_before, "staged line 02", "fixture has an existing staged hunk")
		assert_not_contains(index_before, "unrelated unstaged line 09", "fixture has an unrelated unstaged hunk")
		assert_not_contains(index_before, "unstaged line 16", "fixture keeps target hunk unstaged")

		local diff_win = open_chunk_view(root, "+unstaged line 16")
		chunk.stage_hunk()
		assert(
			vim.wait(5000, function()
				return not chunk.is_collecting()
			end, 10),
			"Chunk refresh completed"
		)

		assert_equal(read_file(root .. "/shared.txt"), working_before, "staging leaves working file unchanged")
		local index_after_stage = run({ "git", "show", ":shared.txt" }, root)
		assert_contains(index_after_stage, "unstaged line 16", "staging puts the target hunk in the index")
		assert_not_contains(
			index_after_stage,
			"unrelated unstaged line 09",
			"staging leaves the unrelated hunk out of the index"
		)

		local unstaged_after_stage = run({ "git", "diff", "--", "shared.txt" }, root)
		assert_contains(unstaged_after_stage, "+unrelated unstaged line 09", "unrelated hunk remains unstaged")
		assert_not_contains(unstaged_after_stage, "+unstaged line 16", "target hunk is no longer unstaged")

		local lines = window_lines(diff_win)
		assert(not vim.list_contains(lines, "Changes"), "unselected unstaged entry is excluded after refresh")
		assert(vim.list_contains(lines, "Staged Changes"), "staged section remains after refresh")

		local cursor_row = vim.api.nvim_win_get_cursor(diff_win)[1]
		local nearby = table.concat(vim.list_slice(lines, cursor_row, cursor_row + 4), "\n")
		assert_contains(nearby, "unstaged line 16", "selection follows the staged hunk")

		chunk.unstage_hunk()
		assert(
			vim.wait(5000, function()
				return not chunk.is_collecting()
			end, 10),
			"Chunk refresh completed"
		)

		assert_equal(read_file(root .. "/shared.txt"), working_before, "unstaging leaves working file unchanged")
		assert_equal(
			run({ "git", "show", ":shared.txt" }, root),
			index_before,
			"unstaging restores only the target index state"
		)
		assert_contains(
			run({ "git", "diff", "--", "shared.txt" }, root),
			"+unstaged line 16",
			"target hunk is unstaged again"
		)

		lines = window_lines(diff_win)
		assert(vim.list_contains(lines, "Changes"), "unstaged section returns after refresh")
		assert(not vim.list_contains(lines, "Staged Changes"), "unselected staged entry is excluded")

		cursor_row = vim.api.nvim_win_get_cursor(diff_win)[1]
		nearby = table.concat(vim.list_slice(lines, cursor_row, cursor_row + 4), "\n")
		assert_contains(nearby, "unstaged line 16", "selection follows the unstaged hunk")

		local notification = capture_notification(chunk.unstage_hunk)
		assert(notification, "inapplicable action sends a notification")
		assert_equal(notification.level, vim.log.levels.WARN, "inapplicable action warns")
		assert_contains(notification.message, "not staged", "warning explains why action is unavailable")
		assert_equal(
			run({ "git", "show", ":shared.txt" }, root),
			index_before,
			"inapplicable action leaves index unchanged"
		)
		assert_equal(
			read_file(root .. "/shared.txt"),
			working_before,
			"inapplicable action leaves working file unchanged"
		)

		chunk.close()
	end)
end

local function test_rejected_patch_reports_git_error_without_refreshing()
	with_repo(function(root)
		local diff_win = open_chunk_view(root, "+unstaged line 16")
		local rendered_before = table.concat(window_lines(diff_win), "\n")

		run({ "git", "add", "shared.txt" }, root)
		local index_before_action = run({ "git", "show", ":shared.txt" }, root)
		local notification = capture_notification(chunk.stage_hunk)

		assert(notification, "rejected patch sends a notification")
		assert_equal(notification.level, vim.log.levels.ERROR, "rejected patch reports an error")
		assert_contains(notification.message, "Could not stage hunk:", "error identifies the failed action")
		assert(#notification.message > #"Could not stage hunk: ", "error includes Git's rejection reason")
		assert_equal(
			run({ "git", "show", ":shared.txt" }, root),
			index_before_action,
			"rejected patch leaves index unchanged"
		)
		assert_equal(
			table.concat(window_lines(diff_win), "\n"),
			rendered_before,
			"rejected patch does not refresh the view"
		)

		chunk.close()
	end)
end

test_stage_and_unstage_hunk_update_only_index_and_follow_selection()
test_rejected_patch_reports_git_error_without_refreshing()
print("ok 2 tests")
