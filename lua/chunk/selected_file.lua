local git = require("chunk.git")
local render = require("chunk.render")
local source_view = require("chunk.source_view")

local M = {}

local function valid_buf(buf)
	return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function source_config(value)
	value = type(value) == "table" and value or {}
	return {
		enabled = value.enabled == true,
		debounce_ms = math.max(0, math.floor(tonumber(value.debounce_ms) or 120)),
		fold_unchanged = value.fold_unchanged == true,
		context_lines = math.max(0, math.floor(tonumber(value.context_lines) or 3)),
	}
end

local function activate(display, buf)
	local previous = display.current_buf
	if previous == buf then
		return
	end

	display.current_buf = buf
	if display.on_buffer then
		display.on_buffer(previous, buf)
	end
end

local function close_source(display)
	if not display.source then
		return
	end

	source_view.close(display.source)
	display.source = nil
end

local function show_unified(display, lines)
	close_source(display)
	if valid_buf(display.unified_buf) then
		render.render(display.unified_buf, lines or {})
	end
	if valid_win(display.win) and valid_buf(display.unified_buf) then
		vim.api.nvim_win_set_buf(display.win, display.unified_buf)
	end
	activate(display, display.unified_buf)
end

local function supports_source(display, request)
	local file = request.file
	return display.source_config.enabled
		and file
		and request.spec
		and request.spec.mode == "working_tree"
		and file.section == "unstaged"
		and (file.status == "modified" or file.status == "added")
		and not file.is_binary
		and valid_win(display.win)
end

function M.new(opts)
	local config = source_config(opts.source_config)
	local display = {
		win = opts.win,
		unified_buf = opts.buf,
		current_buf = opts.buf,
		source_config = config,
		on_buffer = opts.on_buffer,
		on_warning = opts.on_warning,
		on_write = opts.on_write,
		closed = false,
	}

	render.prepare_buffer(display.unified_buf, opts.name)
	if config.enabled then
		vim.api.nvim_set_option_value("bufhidden", "hide", { buf = display.unified_buf })
	end

	return display
end

function M.show(display, request)
	if display.closed then
		return false
	end

	request = request or {}
	show_unified(display, request.lines)
	if not supports_source(display, request) then
		return false
	end

	local file = request.file
	local baseline, baseline_err
	if file.status == "added" then
		baseline = {}
	else
		baseline, baseline_err = git.head_lines(request.root, file.path)
	end
	if not baseline then
		if display.on_warning then
			display.on_warning("Could not open source-backed diff: " .. baseline_err)
		end
		return false
	end

	display.source = source_view.open({
		win = display.win,
		path = request.root .. "/" .. file.path,
		baseline = baseline,
		debounce_ms = display.source_config.debounce_ms,
		fold_unchanged = display.source_config.fold_unchanged,
		context_lines = display.source_config.context_lines,
		on_write = display.on_write,
	})
	activate(display, display.source.buf)
	return true
end

function M.close(display)
	if not display or display.closed then
		return
	end

	close_source(display)
	display.closed = true
	activate(display, nil)
	if valid_buf(display.unified_buf) then
		pcall(vim.api.nvim_buf_delete, display.unified_buf, { force = true })
	end
end

return M
