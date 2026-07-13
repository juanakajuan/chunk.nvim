local M = {}

local namespace = vim.api.nvim_create_namespace("chunk_source")
local render = require("chunk.render")

local function text(lines)
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n") .. "\n"
end

local function changed_ranges(changes, line_count, context_lines)
	local ranges = {}
	for _, change in ipairs(changes) do
		local _, _, new_start, new_count = unpack(change)
		local first = math.max(1, new_start - context_lines)
		local last = math.min(line_count, new_start + math.max(new_count, 1) - 1 + context_lines)
		if #ranges > 0 and first <= ranges[#ranges][2] + 1 then
			ranges[#ranges][2] = math.max(ranges[#ranges][2], last)
		else
			table.insert(ranges, { first, last })
		end
	end
	return ranges
end

local function update_folds(view, changes, line_count)
	if not view.fold_unchanged or not vim.api.nvim_win_is_valid(view.win) then
		return
	end
	if vim.api.nvim_win_get_buf(view.win) ~= view.buf then
		return
	end

	local ranges = changed_ranges(changes, line_count, view.context_lines)
	vim.api.nvim_win_call(view.win, function()
		vim.cmd("silent! normal! zE")
		local next_line = 1
		for _, range in ipairs(ranges) do
			if next_line < range[1] then
				vim.cmd(("silent! %d,%dfold"):format(next_line, range[1] - 1))
			end
			next_line = range[2] + 1
		end
		if next_line <= line_count then
			vim.cmd(("silent! %d,%dfold"):format(next_line, line_count))
		end
	end)
end

local function decorate(view)
	if view.closed or not vim.api.nvim_buf_is_valid(view.buf) then
		return
	end
	render.set_highlights()

	local current = vim.api.nvim_buf_get_lines(view.buf, 0, -1, false)
	local changes = vim.diff(text(view.baseline), text(current), { result_type = "indices" })
	vim.api.nvim_buf_clear_namespace(view.buf, namespace, 0, -1)

	for _, change in ipairs(changes) do
		local old_start, old_count, new_start, new_count = unpack(change)
		for row = new_start, new_start + new_count - 1 do
			vim.api.nvim_buf_set_extmark(view.buf, namespace, row - 1, 0, {
				line_hl_group = "ChunkAdd",
				hl_eol = true,
			})
		end

		if old_count > 0 then
			local deleted = {}
			for row = old_start, old_start + old_count - 1 do
				table.insert(deleted, { { view.baseline[row], "ChunkDelete" } })
			end
			local line_count = vim.api.nvim_buf_line_count(view.buf)
			local anchor = math.min(math.max(new_start - 1, 0), math.max(line_count - 1, 0))
			vim.api.nvim_buf_set_extmark(view.buf, namespace, anchor, 0, {
				virt_lines = deleted,
				virt_lines_above = new_start <= line_count,
				right_gravity = false,
			})
		end
	end

	update_folds(view, changes, #current)
end

function M.open(opts)
	local buf = vim.fn.bufadd(opts.path)
	vim.fn.bufload(buf)

	local view = {
		buf = buf,
		win = opts.win,
		baseline = opts.baseline,
		fold_unchanged = opts.fold_unchanged == true,
		context_lines = math.max(0, math.floor(tonumber(opts.context_lines) or 3)),
		closed = false,
		generation = 0,
		group = vim.api.nvim_create_augroup(("chunk_source_%d_%d"):format(buf, opts.win), { clear = true }),
	}
	if view.fold_unchanged then
		view.fold_options = {}
		for _, option in ipairs({ "foldmethod", "foldenable", "foldlevel" }) do
			view.fold_options[option] = vim.api.nvim_get_option_value(option, { win = opts.win })
		end
		vim.api.nvim_set_option_value("foldmethod", "manual", { win = opts.win })
		vim.api.nvim_set_option_value("foldenable", true, { win = opts.win })
		vim.api.nvim_set_option_value("foldlevel", 0, { win = opts.win })
	end

	local function schedule()
		view.generation = view.generation + 1
		local generation = view.generation
		vim.defer_fn(function()
			if generation == view.generation then
				decorate(view)
			end
		end, opts.debounce_ms)
	end

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = view.group,
		buffer = buf,
		callback = schedule,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = view.group,
		buffer = buf,
		callback = function()
			decorate(view)
			if opts.on_write then
				opts.on_write()
			end
		end,
	})

	vim.api.nvim_win_set_buf(opts.win, buf)
	decorate(view)
	return view
end

function M.refresh(view, baseline)
	if view then
		view.baseline = baseline or view.baseline
		decorate(view)
	end
end

function M.close(view)
	if not view or view.closed then
		return
	end
	view.closed = true
	view.generation = view.generation + 1
	pcall(vim.api.nvim_del_augroup_by_id, view.group)
	if vim.api.nvim_buf_is_valid(view.buf) then
		vim.api.nvim_buf_clear_namespace(view.buf, namespace, 0, -1)
	end
	if view.fold_options and vim.api.nvim_win_is_valid(view.win) then
		if vim.api.nvim_win_get_buf(view.win) == view.buf then
			vim.api.nvim_win_call(view.win, function()
				vim.cmd("silent! normal! zE")
			end)
		end
		for option, value in pairs(view.fold_options) do
			vim.api.nvim_set_option_value(option, value, { win = view.win })
		end
	end
end

M.namespace = namespace

return M
