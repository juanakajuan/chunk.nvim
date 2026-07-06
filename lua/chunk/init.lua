local config = require("chunk.config")
local git = require("chunk.git")
local parser = require("chunk.parser")
local render = require("chunk.render")

local M = {}

local states = setmetatable({}, {
	__mode = "k",
})

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, {
		title = "chunk",
	})
end

local function rendered_lines_for_diff(diff)
	if diff == "" then
		return {
			{
				kind = "empty",
				text = "No changes against HEAD",
			},
		}
	end

	return parser.flatten(parser.parse(diff))
end

local function collect_diff(start_dir)
	return git.collect({
		start_dir = start_dir,
		context_lines = config.options.context_lines,
		include_untracked = config.options.include_untracked,
	})
end

local function set_keymap(buf, lhs, rhs, desc)
	if not lhs or lhs == "" then
		return
	end

	vim.keymap.set("n", lhs, rhs, {
		buffer = buf,
		nowait = true,
		silent = true,
		desc = desc,
	})
end

local function current_buffer_state()
	return states[vim.api.nvim_get_current_buf()]
end

local function set_buffer_state(buf, state)
	states[buf] = state
end

local function apply_keymaps(buf)
	local maps = config.options.keymaps

	set_keymap(buf, maps.open_file, M.open_file_at_cursor, "Open changed file")
	set_keymap(buf, maps.refresh, M.refresh, "Refresh Chunk diff")
	set_keymap(buf, maps.next_hunk, function()
		M.jump("hunk", 1)
	end, "Next hunk")
	set_keymap(buf, maps.prev_hunk, function()
		M.jump("hunk", -1)
	end, "Previous hunk")
	set_keymap(buf, maps.next_file, function()
		M.jump("file_header", 1)
	end, "Next file")
	set_keymap(buf, maps.prev_file, function()
		M.jump("file_header", -1)
	end, "Previous file")
	set_keymap(buf, maps.close, M.close, "Close Chunk diff")
end

local function open_diff_view()
	local origin_tab = vim.api.nvim_get_current_tabpage()
	local origin_win = vim.api.nvim_get_current_win()

	if config.options.open_mode == "current" then
		vim.cmd.enew()
	elseif config.options.open_mode == "split" then
		vim.cmd.split()
		vim.cmd.enew()
	else
		vim.cmd.tabnew()
	end

	return vim.api.nvim_get_current_buf(), origin_tab, origin_win
end

local function file_path_for_line(line)
	if not line then
		return nil
	end

	if line.file then
		return line.file.new_path or line.file.old_path
	end

	return line.new_path or line.old_path
end

local function find_file_target(state, start, stop, step)
	for index = start, stop, step do
		local candidate = state.line_map[index]
		local file_path = file_path_for_line(candidate)
		if file_path then
			return candidate, file_path
		end
	end
end

local function nearest_file_target(state, row)
	local target, file_path = find_file_target(state, row, 1, -1)
	if target then
		return target, file_path
	end

	return find_file_target(state, row + 1, #state.line_map, 1)
end

local function restore_origin_window(state)
	local tab = state.origin_tab
	if not tab or not vim.api.nvim_tabpage_is_valid(tab) then
		return
	end

	vim.api.nvim_set_current_tabpage(tab)

	local win = state.origin_win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
end

local function render_lines_into_buffer(buf, state, rendered)
	state.line_map = rendered
	render.render(buf, rendered)
	set_buffer_state(buf, state)
end

function M.setup(opts)
	config.setup(opts)
end

function M.open()
	local start_dir = git.current_start_dir()
	local collected, err = collect_diff(start_dir)
	if not collected then
		notify(err, vim.log.levels.ERROR)
		return
	end

	local buf, origin_tab, origin_win = open_diff_view()
	local state = {
		root = collected.root,
		origin_tab = origin_tab,
		origin_win = origin_win,
		open_mode = config.options.open_mode,
		line_map = {},
	}

	render.prepare_buffer(buf, ("chunk://%s/%d"):format(collected.root, buf))
	local rendered = rendered_lines_for_diff(collected.diff)
	render_lines_into_buffer(buf, state, rendered)
	apply_keymaps(buf)
end

function M.refresh()
	local state = current_buffer_state()
	if not state then
		M.open()
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local collected, err = collect_diff(state.root)
	if not collected then
		notify(err, vim.log.levels.ERROR)
		return
	end

	state.root = collected.root
	local rendered = rendered_lines_for_diff(collected.diff)
	render_lines_into_buffer(vim.api.nvim_get_current_buf(), state, rendered)

	local last_line = math.max(1, vim.api.nvim_buf_line_count(0))
	cursor[1] = math.min(cursor[1], last_line)
	vim.api.nvim_win_set_cursor(0, cursor)
end

function M.open_file_at_cursor()
	local state = current_buffer_state()
	if not state then
		return
	end

	local row = vim.api.nvim_win_get_cursor(0)[1]
	local target, relative_path = nearest_file_target(state, row)

	if not relative_path then
		notify("No file target for this line", vim.log.levels.WARN)
		return
	end

	local full_path = state.root .. "/" .. relative_path
	local line = target.new_line or target.target_line or 1

	restore_origin_window(state)

	vim.cmd.edit(vim.fn.fnameescape(full_path))
	vim.api.nvim_win_set_cursor(0, { math.max(1, line), 0 })
end

function M.jump(kind, direction)
	local state = current_buffer_state()
	if not state then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(0)
	local start = cursor[1] + direction
	local stop = direction > 0 and #state.line_map or 1

	for index = start, stop, direction do
		local line = state.line_map[index]
		if line and line.kind == kind then
			vim.api.nvim_win_set_cursor(0, { index, 0 })
			return
		end
	end
end

function M.close()
	local state = current_buffer_state()

	if state and state.open_mode == "tab" and #vim.api.nvim_list_tabpages() > 1 then
		pcall(vim.cmd.tabclose)
		return
	end

	local current_tab = vim.api.nvim_get_current_tabpage()
	if state and state.open_mode == "split" and #vim.api.nvim_tabpage_list_wins(current_tab) > 1 then
		pcall(vim.cmd.close)
		return
	end

	pcall(vim.cmd.bwipeout)
end

return M
