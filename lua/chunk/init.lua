local config = require("chunk.config")
local diff_spec = require("chunk.diff_spec")
local git = require("chunk.git")
local parser = require("chunk.parser")
local render = require("chunk.render")
local selected_file = require("chunk.selected_file")
local sidebar = require("chunk.sidebar")

local M = {}

local states = setmetatable({}, {
	__mode = "k",
})

local augroup = vim.api.nvim_create_augroup("chunk", {
	clear = false,
})
local status_namespace = vim.api.nvim_create_namespace("chunk_status")

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, {
		title = "chunk",
	})
end

local function valid_buf(buf)
	return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function focus_window(win)
	if valid_win(win) then
		vim.api.nvim_set_current_win(win)
	end
end

local function set_cursor_row(win, buf, row)
	if not row or not valid_win(win) or not valid_buf(buf) then
		return
	end

	local last_line = math.max(1, vim.api.nvim_buf_line_count(buf))
	pcall(vim.api.nvim_win_set_cursor, win, { math.min(math.max(1, row), last_line), 0 })
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

local function file_stats(file)
	local additions = 0
	local deletions = 0
	for _, file_line in ipairs((file and file.lines) or {}) do
		if file_line.kind == "add" then
			additions = additions + 1
		elseif file_line.kind == "delete" then
			deletions = deletions + 1
		end
	end
	return additions, deletions
end

local function append_file_to_model(model, panel_section, line)
	local file = line.file
	local additions, deletions = file_stats(file)
	local rendered_lines = {
		{
			kind = "section_heading",
			text = panel_section.title,
			section = panel_section.id,
		},
	}
	vim.list_extend(rendered_lines, file.lines)
	local file_item = {
		path = file_path_for_line(line) or "(unknown)",
		section = line.section,
		status = file and file.status or "modified",
		is_binary = file and file.is_binary or false,
		additions = additions,
		deletions = deletions,
		header_row = 2,
		rendered_lines = rendered_lines,
		file = file,
	}

	table.insert(model.file_items, file_item)
	file_item.file_index = #model.file_items
	table.insert(panel_section.files, file_item)
end

local function append_section_to_model(model, section)
	local lines = parser.flatten(parser.parse(section.diff, {
		section = section.id,
	}))
	if #lines == 0 then
		return
	end

	local panel_section = {
		id = section.id,
		title = section.title,
		files = {},
	}
	table.insert(model.panel_sections, panel_section)

	for _, line in ipairs(lines) do
		if line.kind == "file_header" then
			append_file_to_model(model, panel_section, line)
		end
	end
end

local function render_model_for_changes(collected)
	local model = {
		lines = {},
		file_items = {},
		panel_sections = {},
	}

	for _, section in ipairs(collected.sections or {}) do
		append_section_to_model(model, section)
	end

	if #model.file_items == 0 then
		model.lines = {
			{
				kind = "empty",
				text = collected.empty_message or "No staged or unstaged changes",
			},
		}
	end

	return model
end

local function collect_changes(start_dir, spec, callback)
	return git.collect({
		start_dir = start_dir,
		context_lines = config.options.context_lines,
		include_untracked = config.options.include_untracked,
		spec = spec,
	}, callback)
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
	if valid_buf(buf) then
		states[buf] = state
	end
end

local function clear_buffer_state(buf)
	if buf then
		states[buf] = nil
	end
end

local function clear_view_state(state)
	if state.request then
		state.request.cancel()
		state.request = nil
	end
	state.closed = true
	if state.file_display then
		selected_file.close(state.file_display)
		state.file_display = nil
	end
	clear_buffer_state(state.diff_buf)
	clear_buffer_state(state.files_buf)
end

local function set_collection_status(state, message)
	if not valid_buf(state.diff_buf) then
		return
	end
	vim.api.nvim_buf_clear_namespace(state.diff_buf, status_namespace, 0, -1)
	if message then
		vim.api.nvim_buf_set_extmark(state.diff_buf, status_namespace, 0, 0, {
			virt_text = { { message, "Comment" } },
			virt_text_pos = "right_align",
		})
	end
end

local function set_view_state(state)
	set_buffer_state(state.diff_buf, state)
	set_buffer_state(state.files_buf, state)
end

local function render_files_panel(state)
	if not valid_buf(state.files_buf) then
		return
	end

	state.panel_items = sidebar.build(state.panel_sections, state.collapsed_directories)
	for _, file in ipairs(state.file_items) do
		file.panel_row = nil
	end
	for row, item in ipairs(state.panel_items) do
		if item.kind == "file" then
			item.file.panel_row = row
		end
	end

	local panel = config.options.files_panel
	local configured_width = type(panel) == "table" and tonumber(panel.width) or 34
	local width = valid_win(state.files_win) and vim.api.nvim_win_get_width(state.files_win) or configured_width
	render.render_files(state.files_buf, state.panel_items, state.selected_file_index, width)
	set_buffer_state(state.files_buf, state)
end

local function render_model_into_view(state, model)
	state.empty_lines = model.lines
	state.line_map = model.lines
	state.file_items = model.file_items
	state.panel_sections = model.panel_sections
	state.selected_file_index = nil
	state.selected_file_identity = nil

	selected_file.show(state.file_display, { lines = model.lines })

	render_files_panel(state)
	set_view_state(state)
end

local function file_identity(file)
	if not file then
		return nil
	end

	return {
		section = file.section,
		path = file.path,
	}
end

local function file_index_for_identity(state, identity)
	if not identity then
		return nil
	end

	for index, file in ipairs(state.file_items) do
		if file.section == identity.section and file.path == identity.path then
			return index
		end
	end
end

local function file_index_at_panel_row(state, row)
	local item = row and state.panel_items[row] or nil
	return item and item.kind == "file" and item.file_index or nil
end

local function set_selected_file(state, index)
	local file = index and state.file_items[index] or nil

	state.selected_file_index = file and index or nil
	state.selected_file_identity = file_identity(file)

	return file
end

local function file_identity_at_panel_row(state, row)
	local item = row and state.panel_items[row] or nil
	return file_identity(item and item.file) or state.selected_file_identity
end

local function select_file(state, index, opts)
	opts = opts or {}

	local file = state.file_items[index]
	if not file then
		return
	end

	set_selected_file(state, index)
	state.line_map = file.rendered_lines
	local source_backed = selected_file.show(state.file_display, {
		root = state.root,
		spec = state.spec,
		file = file,
		lines = file.rendered_lines,
	})
	render_files_panel(state)

	set_cursor_row(state.files_win, state.files_buf, file.panel_row)

	if not source_backed and valid_win(state.diff_win) and valid_buf(state.diff_buf) then
		set_cursor_row(state.diff_win, state.diff_buf, file.header_row)
		pcall(vim.api.nvim_win_call, state.diff_win, function()
			vim.cmd("normal! zz")
		end)
	end

	if opts.focus_diff ~= false then
		focus_window(state.diff_win)
	end

	return source_backed
end

local function restore_files_panel_selection(state, row, identity)
	local selected = file_index_for_identity(state, identity)
	if not selected and row and #state.panel_items > 0 then
		local clamped_row = math.min(row, #state.panel_items)
		selected = file_index_at_panel_row(state, clamped_row)
			or file_index_at_panel_row(state, clamped_row + 1)
			or file_index_at_panel_row(state, clamped_row - 1)
	end

	if selected then
		select_file(state, selected, {
			focus_diff = false,
		})
		return
	end

	set_selected_file(state, nil)
	state.line_map = state.empty_lines
	selected_file.show(state.file_display, { lines = state.empty_lines })
	render_files_panel(state)
end

local function set_file_navigation_keymaps(buf, maps, next_file, prev_file)
	set_keymap(buf, maps.next_file, next_file, "Next file")
	set_keymap(buf, maps.prev_file, prev_file, "Previous file")
end

local function apply_diff_keymaps(buf, mutable)
	local maps = config.options.keymaps

	set_keymap(buf, maps.open_file, M.open_file_at_cursor, "Open changed file")
	set_keymap(buf, maps.refresh, M.refresh, "Refresh Chunk diff")
	if mutable then
		set_keymap(buf, maps.stage_hunk, M.stage_hunk, "Stage hunk")
		set_keymap(buf, maps.unstage_hunk, M.unstage_hunk, "Unstage hunk")
	end
	set_keymap(buf, maps.next_hunk, function()
		M.jump("hunk", 1)
	end, "Next hunk")
	set_keymap(buf, maps.prev_hunk, function()
		M.jump("hunk", -1)
	end, "Previous hunk")
	set_keymap(buf, maps.close, M.close, "Close Chunk diff")
end

local function apply_files_keymaps(buf)
	local maps = config.options.keymaps

	set_keymap(buf, maps.select_file, M.select_file_at_cursor, "Show selected file diff")
	set_keymap(buf, maps.refresh, M.refresh, "Refresh Chunk diff")
	set_file_navigation_keymaps(buf, maps, function()
		M.select_relative_file(1)
	end, function()
		M.select_relative_file(-1)
	end)
	set_keymap(buf, maps.close, M.close, "Close Chunk diff")
end

local function files_panel_config()
	local panel = config.options.files_panel
	if panel == false then
		return {
			enabled = false,
			width = 0,
		}
	end

	panel = type(panel) == "table" and panel or {}
	return {
		enabled = panel.enabled ~= false,
		width = math.max(1, math.floor(tonumber(panel.width) or 34)),
	}
end

local files_window_options = {
	{ "number", false },
	{ "relativenumber", false },
	{ "signcolumn", "no" },
	{ "foldcolumn", "0" },
	{ "wrap", false },
	{ "list", false },
	{ "cursorline", true },
	{ "cursorlineopt", "line" },
	{ "fillchars", "eob: " },
	{
		"winhighlight",
		"Normal:ChunkSidebarNormal,NormalNC:ChunkSidebarNormal,WinSeparator:ChunkSidebarBorder,CursorLine:ChunkFileSelected",
	},
	{ "winfixwidth", true },
}

local function configure_files_window(win, width)
	for _, option in ipairs(files_window_options) do
		vim.api.nvim_set_option_value(option[1], option[2], { win = win })
	end

	pcall(vim.api.nvim_win_set_width, win, width)
end

local function open_files_panel(diff_win)
	local panel = files_panel_config()
	if not panel.enabled then
		return nil, nil
	end

	vim.cmd(("leftabove vertical %dnew"):format(panel.width))

	local files_win = vim.api.nvim_get_current_win()
	local files_buf = vim.api.nvim_get_current_buf()

	configure_files_window(files_win, panel.width)
	focus_window(diff_win)

	return files_win, files_buf
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

	local diff_win = vim.api.nvim_get_current_win()
	local diff_buf = vim.api.nvim_get_current_buf()
	local files_win, files_buf = open_files_panel(diff_win)

	return {
		diff_buf = diff_buf,
		diff_win = diff_win,
		files_buf = files_buf,
		files_win = files_win,
		origin_tab = origin_tab,
		origin_win = origin_win,
	}
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

local function selection_identity_for_line(line)
	if not line or not line.section then
		return nil
	end

	local path = file_path_for_line(line)
	if not path then
		return nil
	end

	local identity = {
		section = line.section,
		path = path,
	}

	if line.hunk then
		identity.hunk = {
			old_start = line.hunk.old_start,
			old_count = line.hunk.old_count,
			new_start = line.hunk.new_start,
			new_count = line.hunk.new_count,
		}
	end

	return identity
end

local function same_hunk(left, right)
	return left
		and right
		and left.old_start == right.old_start
		and left.old_count == right.old_count
		and left.new_start == right.new_start
		and left.new_count == right.new_count
end

local function selection_row(state, identity)
	if not identity then
		return nil
	end

	local file_header_row = nil
	local nearest_hunk_row = nil
	local nearest_hunk_distance = math.huge

	for row, line in ipairs(state.line_map) do
		if line.section == identity.section and file_path_for_line(line) == identity.path then
			if line.kind == "file_header" then
				file_header_row = row
			elseif identity.hunk and line.kind == "hunk" and line.hunk then
				if same_hunk(line.hunk, identity.hunk) then
					return row
				end

				local distance = math.abs(line.hunk.old_start - identity.hunk.old_start)
					+ math.abs(line.hunk.new_start - identity.hunk.new_start)
				if distance < nearest_hunk_distance then
					nearest_hunk_row = row
					nearest_hunk_distance = distance
				end
			end
		end
	end

	return nearest_hunk_row or file_header_row
end

local function restore_diff_selection(state, identity, fallback_cursor)
	if not valid_win(state.diff_win) then
		return
	end

	local index = file_index_for_identity(state, identity) or 1
	if not state.file_items[index] then
		set_selected_file(state, nil)
		state.line_map = state.empty_lines
		selected_file.show(state.file_display, { lines = state.empty_lines })
		render_files_panel(state)
		return
	end

	local source_backed = select_file(state, index, { focus_diff = false })
	if source_backed then
		return
	end

	local row = selection_row(state, identity)
	if not row and fallback_cursor then
		row = fallback_cursor[1]
	end

	set_cursor_row(state.diff_win, state.diff_buf, row or 1)
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

local function close_window(win)
	if valid_win(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
end

local function delete_buffer(buf)
	if valid_buf(buf) then
		pcall(vim.api.nvim_buf_delete, buf, {
			force = true,
		})
	end
end

local function close_view(state)
	clear_view_state(state)
	close_window(state.files_win)
	close_window(state.diff_win)
	delete_buffer(state.files_buf)

	if state.open_mode ~= "current" then
		restore_origin_window(state)
	end
end

local function apply_autocmds(state)
	for _, buf in ipairs({ state.diff_buf, state.files_buf }) do
		if valid_buf(buf) then
			vim.api.nvim_create_autocmd("BufWipeout", {
				group = augroup,
				buffer = buf,
				callback = function(args)
					local current = states[args.buf]
					if current and current.request then
						current.request.cancel()
						current.request = nil
						current.closed = true
					end
					clear_buffer_state(args.buf)
				end,
			})
		end
	end
end

local function start_collection(state, start_dir, opts)
	opts = opts or {}
	if state.request then
		state.request.cancel()
	end
	state.generation = (state.generation or 0) + 1
	local generation = state.generation
	set_collection_status(state, opts.initial and nil or "Refreshing…")

	state.request = collect_changes(start_dir, state.spec, function(collected, err)
		vim.schedule(function()
			if state.closed or state.generation ~= generation or not valid_buf(state.diff_buf) then
				return
			end
			state.request = nil
			set_collection_status(state, nil)
			if not collected then
				if opts.initial then
					close_view(state)
				end
				notify(err, vim.log.levels.ERROR)
				return
			end

			state.root = collected.root
			state.spec = collected.spec
			state.mutable = collected.mutable
			render_model_into_view(state, render_model_for_changes(collected))
			if opts.initial then
				if #state.file_items > 0 then
					select_file(state, 1, { focus_diff = false })
				end
				return
			end
			if opts.current_is_files_panel then
				restore_files_panel_selection(state, opts.files_cursor, opts.selected_identity)
				focus_window(opts.current_win)
				return
			end
			restore_diff_selection(state, opts.diff_selection, opts.diff_cursor)
		end)
	end)
end

function M.setup(opts)
	config.setup(opts)
end

function M.open(args)
	local spec, spec_err = diff_spec.parse(args)
	if not spec then
		notify("Invalid :Chunk arguments: " .. spec_err, vim.log.levels.ERROR)
		return
	end

	local active_state = current_buffer_state()
	local start_dir = active_state and active_state.root or git.current_start_dir()
	local view = open_diff_view()
	local state = {
		root = start_dir,
		spec = spec,
		mutable = diff_spec.is_mutable(spec),
		origin_tab = view.origin_tab,
		origin_win = view.origin_win,
		open_mode = config.options.open_mode,
		diff_buf = view.diff_buf,
		diff_win = view.diff_win,
		files_buf = view.files_buf,
		files_win = view.files_win,
		line_map = {},
		file_items = {},
		panel_items = {},
		panel_sections = {},
		collapsed_directories = {},
		selected_file_index = nil,
		selected_file_identity = nil,
	}

	state.file_display = selected_file.new({
		win = state.diff_win,
		buf = state.diff_buf,
		name = ("chunk://loading/%d"):format(state.diff_buf),
		source_config = config.options.source_view,
		on_buffer = function(previous, current)
			clear_buffer_state(previous)
			state.diff_buf = current
			set_buffer_state(current, state)
		end,
		on_warning = function(message)
			notify(message, vim.log.levels.WARN)
		end,
		on_write = function()
			if not state.closed then
				M.refresh()
			end
		end,
	})
	if valid_buf(state.files_buf) then
		render.prepare_files_buffer(state.files_buf, ("chunk://loading/files/%d"):format(state.files_buf))
	end

	render_model_into_view(
		state,
		{ lines = { { kind = "empty", text = "Loading Git changes…" } }, file_items = {}, panel_sections = {} }
	)

	apply_diff_keymaps(state.diff_buf, state.mutable)
	if valid_buf(state.files_buf) then
		apply_files_keymaps(state.files_buf)
	end
	apply_autocmds(state)
	start_collection(state, start_dir, { initial = true })

	focus_window(state.diff_win)
end

function M.refresh(opts)
	opts = type(opts) == "table" and opts or {}
	local state = current_buffer_state()
	if not state or not valid_buf(state.diff_buf) then
		M.open()
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()
	local current_win = vim.api.nvim_get_current_win()
	local current_is_files_panel = current_buf == state.files_buf
	local files_cursor = current_is_files_panel and vim.api.nvim_win_get_cursor(0)[1] or nil
	local selected_identity = current_is_files_panel and file_identity_at_panel_row(state, files_cursor) or nil
	local diff_cursor = valid_win(state.diff_win) and vim.api.nvim_win_get_cursor(state.diff_win) or { 1, 0 }
	local diff_selection = opts.selection
		or selection_identity_for_line(state.line_map[diff_cursor[1]])
		or state.selected_file_identity
	start_collection(state, state.root, {
		current_is_files_panel = current_is_files_panel,
		current_win = current_win,
		files_cursor = files_cursor,
		selected_identity = selected_identity,
		diff_cursor = diff_cursor,
		diff_selection = diff_selection,
	})
end

function M.select_file_at_cursor()
	local state = current_buffer_state()
	if not state then
		return
	end

	local row = vim.api.nvim_win_get_cursor(0)[1]
	local item = state.panel_items[row]
	if item and item.kind == "folder" then
		state.collapsed_directories[item.key] = item.expanded and true or nil
		render_files_panel(state)
		for next_row, candidate in ipairs(state.panel_items) do
			if candidate.kind == "folder" and candidate.key == item.key then
				set_cursor_row(state.files_win, state.files_buf, next_row)
				break
			end
		end
		return
	end

	local index = item and item.kind == "file" and item.file_index or nil
	if not index then
		return
	end

	select_file(state, index, {
		focus_diff = true,
	})
end

function M.select_relative_file(direction)
	local state = current_buffer_state()
	if not state or vim.api.nvim_get_current_buf() ~= state.files_buf or (direction ~= 1 and direction ~= -1) then
		return
	end

	local row = vim.api.nvim_win_get_cursor(0)[1]
	for next_row = row + direction, direction > 0 and #state.panel_items or 1, direction do
		local item = state.panel_items[next_row]
		if item and item.kind == "file" then
			select_file(state, item.file_index, { focus_diff = false })
			return
		end
	end
end

function M.open_file_at_cursor()
	local state = current_buffer_state()
	if not state then
		return
	end

	if vim.api.nvim_get_current_buf() == state.files_buf then
		M.select_file_at_cursor()
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

local function apply_hunk_action(action)
	local state = current_buffer_state()
	if not state or vim.api.nvim_get_current_buf() ~= state.diff_buf then
		notify(action.cursor_message, vim.log.levels.WARN)
		return
	end
	if state.mutable == false then
		notify("Index mutation is unavailable in revision comparisons", vim.log.levels.WARN)
		return
	end

	local row = vim.api.nvim_win_get_cursor(0)[1]
	local line = state.line_map[row]
	if not line or not line.hunk or not line.file then
		notify(action.no_hunk_message, vim.log.levels.WARN)
		return
	end

	if line.section ~= action.source_section then
		notify(action.wrong_section_message, vim.log.levels.WARN)
		return
	end

	if action.source_section == "unstaged" and line.file.old_path == nil then
		notify("Untracked hunks cannot be staged individually; add the file with Git first", vim.log.levels.WARN)
		return
	end

	local selection = selection_identity_for_line(line)
	local ok, err = action.apply(state.root, line.hunk.patch)
	if not ok then
		notify(("Could not %s hunk: %s"):format(action.verb, err), vim.log.levels.ERROR)
		return
	end

	selection.section = action.target_section
	M.refresh({
		selection = selection,
	})
end

function M.stage_hunk()
	apply_hunk_action({
		verb = "stage",
		source_section = "unstaged",
		target_section = "staged",
		apply = git.stage_hunk,
		cursor_message = "Place the cursor on an unstaged text hunk to stage it",
		no_hunk_message = "No text hunk under the cursor; move into a hunk in Changes",
		wrong_section_message = "This hunk is already staged; use the unstage action instead",
	})
end

function M.unstage_hunk()
	apply_hunk_action({
		verb = "unstage",
		source_section = "staged",
		target_section = "unstaged",
		apply = git.unstage_hunk,
		cursor_message = "Place the cursor on a staged text hunk to unstage it",
		no_hunk_message = "No text hunk under the cursor; move into a hunk in Staged Changes",
		wrong_section_message = "This hunk is not staged; use the stage action instead",
	})
end

function M.jump(kind, direction)
	local state = current_buffer_state()
	if not state then
		return
	end

	if vim.api.nvim_get_current_buf() == state.files_buf and kind == "file_header" then
		M.select_relative_file(direction)
		return
	end

	local target_win = valid_win(state.diff_win) and state.diff_win or vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(target_win)
	local start = cursor[1] + direction
	local stop = direction > 0 and #state.line_map or 1

	for index = start, stop, direction do
		local line = state.line_map[index]
		if line and line.kind == kind then
			vim.api.nvim_win_set_cursor(target_win, { index, 0 })
			return
		end
	end
end

function M.close()
	local state = current_buffer_state()
	if state and state.request then
		state.request.cancel()
		state.request = nil
		state.closed = true
	end

	if state and state.open_mode == "tab" and #vim.api.nvim_list_tabpages() > 1 then
		clear_view_state(state)
		pcall(vim.cmd.tabclose)
		return
	end

	if state then
		close_view(state)
		return
	end

	pcall(vim.cmd.bwipeout)
end

function M.is_collecting()
	local state = current_buffer_state()
	return state ~= nil and state.request ~= nil
end

return M
