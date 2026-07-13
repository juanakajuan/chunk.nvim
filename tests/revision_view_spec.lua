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

local function assert_contains(lines, expected, message)
	if not vim.list_contains(lines, expected) then
		error(("%s: expected %s to contain %s"):format(message, vim.inspect(lines), vim.inspect(expected)), 2)
	end
end

local function assert_lines_exclude(lines, unexpected, message)
	local rendered = table.concat(lines, "\n")
	if rendered:find(unexpected, 1, true) then
		error(("%s: expected rendered lines not to contain %s"):format(message, vim.inspect(unexpected)), 2)
	end
end

local function assert_text_contains(value, expected, message)
	if not value:find(expected, 1, true) then
		error(("%s: expected %s to contain %s"):format(message, vim.inspect(value), vim.inspect(expected)), 2)
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

local function setup_diverging_repo(root)
	run({ "git", "init", "-q" }, root)
	run({ "git", "config", "user.name", "Chunk Test" }, root)
	run({ "git", "config", "user.email", "chunk@example.com" }, root)
	run({ "git", "checkout", "-qb", "main" }, root)
	write_file(root .. "/inside/base.lua", { "return 'base'" })
	write_file(root .. "/outside/base.lua", { "return 'base'" })
	run({ "git", "add", "." }, root)
	run({ "git", "commit", "-qm", "base" }, root)

	run({ "git", "checkout", "-qb", "feature" }, root)
	write_file(root .. "/inside/selected.lua", { "return 'feature'" })
	write_file(root .. "/outside/ignored.lua", { "return 'feature'" })
	run({ "git", "add", "." }, root)
	run({ "git", "commit", "-qm", "feature changes" }, root)

	run({ "git", "checkout", "-q", "main" }, root)
	write_file(root .. "/inside/main-only.lua", { "return 'main'" })
	run({ "git", "add", "." }, root)
	run({ "git", "commit", "-qm", "main changes" }, root)
	run({ "git", "checkout", "-q", "feature" }, root)

	write_file(root .. "/inside/current-only.lua", { "return 'working tree'" })
	write_file(root .. "/outside/current-only.lua", { "return 'working tree'" })
end

local function with_diverging_repo(fn)
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")

	local ok, err = xpcall(function()
		setup_diverging_repo(root)
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
		local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
		if filetype == "diff" then
			diff_win = win
		elseif filetype == "chunkfiles" then
			files_win = win
		end
	end

	return diff_win, files_win
end

local function window_lines(win)
	return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
end

local function buffer_keymap(buf, lhs)
	for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
		if keymap.lhs == lhs then
			return keymap
		end
	end
end

local function find_line(win, text)
	for row, line in ipairs(window_lines(win)) do
		if line == text then
			return row
		end
	end
end

local function capture_notification(fn)
	local original_notify = vim.notify
	local notification = nil
	vim.notify = function(message, level)
		notification = {
			message = message,
			level = level,
		}
	end

	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		vim.wait(5000, function()
			return notification ~= nil
		end, 10)
	end
	vim.notify = original_notify
	if not ok then
		error(err, 0)
	end

	return notification
end

local function open_revision_view(root, pathspec)
	chunk.setup({
		include_untracked = true,
		open_mode = "tab",
	})
	vim.cmd.edit(vim.fn.fnameescape(root .. "/inside/base.lua"))
	vim.cmd("Chunk main...HEAD -- " .. (pathspec or "inside/"))
	assert(
		vim.wait(5000, function()
			return not chunk.is_collecting()
		end, 10),
		"Chunk collection completed"
	)
	return find_chunk_windows()
end

local function test_chunk_command_renders_filtered_revision_range()
	with_diverging_repo(function(root)
		local diff_win, files_win = open_revision_view(root)
		assert(diff_win, "revision diff window exists")
		assert(files_win, "revision files window exists")

		local diff_lines = window_lines(diff_win)
		local file_lines = window_lines(files_win)
		assert_equal(diff_lines[1], "Comparison: main...HEAD -- inside/", "diff comparison description")
		assert_equal(file_lines[1], "Comparison: main...HEAD -- inside/", "files comparison description")
		assert_contains(diff_lines, "+return 'feature'", "matching revision content")
		assert_lines_exclude(diff_lines, "outside/ignored.lua", "outside revision path is filtered")
		assert_lines_exclude(diff_lines, "inside/current-only.lua", "working-tree files are excluded")
		assert_equal(#file_lines, 2, "filtered revision file row count")
		assert(file_lines[2]:match("inside/selected%.lua$"), "matching revision file is rendered")

		chunk.close()
	end)
end

local function test_refresh_preserves_revision_range_and_pathspecs()
	with_diverging_repo(function(root)
		local diff_win = open_revision_view(root)
		chunk.refresh()
		assert(
			vim.wait(5000, function()
				return not chunk.is_collecting()
			end, 10),
			"Chunk refresh completed"
		)

		local diff_lines = window_lines(diff_win)
		assert_equal(diff_lines[1], "Comparison: main...HEAD -- inside/", "refreshed comparison description")
		assert_contains(diff_lines, "+return 'feature'", "refreshed revision content")
		assert_lines_exclude(diff_lines, "outside/ignored.lua", "refresh preserves path filter")
		assert_lines_exclude(diff_lines, "inside/current-only.lua", "refresh preserves revision mode")

		chunk.close()
	end)
end

local function test_revision_view_disables_index_mutation_actions()
	with_diverging_repo(function(root)
		local diff_win = open_revision_view(root)
		local diff_buf = vim.api.nvim_win_get_buf(diff_win)
		assert_equal(buffer_keymap(diff_buf, "s"), nil, "stage mapping is unavailable")
		assert_equal(buffer_keymap(diff_buf, "u"), nil, "unstage mapping is unavailable")

		local index_before = run({ "git", "diff", "--cached" }, root)
		local row = assert(find_line(diff_win, "+return 'feature'"), "revision hunk line exists")
		vim.api.nvim_set_current_win(diff_win)
		vim.api.nvim_win_set_cursor(diff_win, { row, 0 })
		local notification = capture_notification(chunk.stage_hunk)

		assert_equal(notification.level, vim.log.levels.WARN, "direct mutation warns")
		assert_text_contains(
			notification.message,
			"unavailable in revision comparisons",
			"direct mutation explains the view is read-only"
		)
		assert_equal(run({ "git", "diff", "--cached" }, root), index_before, "direct mutation leaves index unchanged")

		chunk.close()
	end)
end

local function test_invalid_revision_reports_error_without_replacing_current_view()
	with_diverging_repo(function(root)
		chunk.setup({ open_mode = "tab" })
		vim.cmd.edit(vim.fn.fnameescape(root .. "/inside/base.lua"))
		local origin_tab = vim.api.nvim_get_current_tabpage()
		local origin_buf = vim.api.nvim_get_current_buf()
		local tab_count = #vim.api.nvim_list_tabpages()

		local notification = capture_notification(function()
			vim.cmd("Chunk definitely-not-a-revision -- inside/")
		end)

		assert_equal(notification.level, vim.log.levels.ERROR, "invalid revision reports an error")
		assert_text_contains(
			notification.message,
			"Git rejected revision or range",
			"error identifies revision failure"
		)
		assert_text_contains(notification.message, "definitely-not-a-revision", "error includes rejected revision")
		assert_equal(vim.api.nvim_get_current_tabpage(), origin_tab, "invalid revision preserves current tab")
		assert_equal(vim.api.nvim_get_current_buf(), origin_buf, "invalid revision preserves current buffer")
		assert_equal(#vim.api.nvim_list_tabpages(), tab_count, "invalid revision does not create a tab")
	end)
end

local function test_malformed_arguments_report_command_contract_error()
	with_diverging_repo(function(root)
		chunk.setup({ open_mode = "tab" })
		vim.cmd.edit(vim.fn.fnameescape(root .. "/inside/base.lua"))
		local tab_count = #vim.api.nvim_list_tabpages()

		local notification = capture_notification(function()
			vim.cmd("Chunk main HEAD")
		end)

		assert_equal(notification.level, vim.log.levels.ERROR, "malformed arguments report an error")
		assert_text_contains(notification.message, "Invalid :Chunk arguments", "error identifies malformed command")
		assert_text_contains(notification.message, "at most one revision or range", "error explains accepted syntax")
		assert_equal(#vim.api.nvim_list_tabpages(), tab_count, "malformed arguments do not create a tab")
	end)
end

local function test_empty_revision_view_keeps_comparison_visible()
	with_diverging_repo(function(root)
		local diff_win = open_revision_view(root, "missing/")
		assert_equal(
			window_lines(diff_win)[1],
			"No changes for main...HEAD -- missing/",
			"empty comparison description"
		)
		chunk.close()
	end)
end

local function test_invalid_revision_preserves_existing_chunk_view()
	with_diverging_repo(function(root)
		chunk.setup({
			include_untracked = true,
			open_mode = "tab",
		})
		vim.cmd.edit(vim.fn.fnameescape(root .. "/inside/base.lua"))
		vim.cmd("Chunk")
		assert(
			vim.wait(5000, function()
				return not chunk.is_collecting()
			end, 10),
			"Chunk collection completed"
		)
		local diff_win = assert(find_chunk_windows(), "working-tree diff window exists")
		local diff_buf = vim.api.nvim_win_get_buf(diff_win)
		local rendered_before = table.concat(window_lines(diff_win), "\n")
		local tab_count = #vim.api.nvim_list_tabpages()

		local notification = capture_notification(function()
			vim.cmd("Chunk definitely-not-a-revision -- inside/")
		end)

		assert_text_contains(
			notification.message,
			"Git rejected revision or range",
			"existing view uses its repository"
		)
		assert_equal(vim.api.nvim_get_current_buf(), diff_buf, "invalid revision preserves Chunk buffer")
		assert_equal(
			table.concat(window_lines(diff_win), "\n"),
			rendered_before,
			"invalid revision preserves rendered diff"
		)
		assert_equal(#vim.api.nvim_list_tabpages(), tab_count, "invalid revision does not replace Chunk tab")

		chunk.close()
	end)
end

vim.cmd.source(vim.fn.fnameescape(vim.fn.getcwd() .. "/plugin/chunk.lua"))
test_chunk_command_renders_filtered_revision_range()
test_refresh_preserves_revision_range_and_pathspecs()
test_revision_view_disables_index_mutation_actions()
test_invalid_revision_reports_error_without_replacing_current_view()
test_malformed_arguments_report_command_contract_error()
test_empty_revision_view_keeps_comparison_visible()
test_invalid_revision_preserves_existing_chunk_view()
print("ok 7 tests")
