local M = {}

local ns = vim.api.nvim_create_namespace("chunk")

local highlights = {
	ChunkFile = "Directory",
	ChunkHunk = "Title",
	ChunkAdd = "DiffAdd",
	ChunkDelete = "DiffDelete",
	ChunkMeta = "Comment",
	ChunkBinary = "WarningMsg",
	ChunkFileSelected = "Visual",
}

local line_highlights = {
	file_header = "ChunkFile",
	hunk = "ChunkHunk",
	add = "ChunkAdd",
	delete = "ChunkDelete",
	meta = "ChunkMeta",
	no_newline = "ChunkMeta",
	binary = "ChunkBinary",
	empty = "ChunkMeta",
}

local default_file_status = {
	label = "M",
	highlight = "ChunkMeta",
}

local file_statuses = {
	added = {
		label = "A",
		highlight = "ChunkAdd",
	},
	deleted = {
		label = "D",
		highlight = "ChunkDelete",
	},
}

local function set_highlights()
	for group, target in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, {
			link = target,
			default = true,
		})
	end
end

local function text_lines(rendered)
	local lines = {}
	for _, line in ipairs(rendered) do
		table.insert(lines, line.text)
	end
	return lines
end

local function file_status(status)
	return file_statuses[status] or default_file_status
end

local function file_panel_lines(files)
	if #files == 0 then
		return { "No changed files" }
	end

	local lines = {}
	for _, file in ipairs(files) do
		local status = file_status(file.status)
		local suffix = file.is_binary and " [binary]" or ""
		table.insert(lines, (" %s %s%s"):format(status.label, file.path, suffix))
	end

	return lines
end

local function render_readonly_buffer(buf, lines, apply_buffer_highlights)
	set_highlights()

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_set_option_value("readonly", false, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	apply_buffer_highlights()
	vim.api.nvim_set_option_value("modified", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
end

local function apply_highlights(buf, rendered)
	for index, line in ipairs(rendered) do
		local group = line_highlights[line.kind]
		if group then
			vim.api.nvim_buf_add_highlight(buf, ns, group, index - 1, 0, -1)
		end
	end
end

function M.render(buf, rendered)
	render_readonly_buffer(buf, text_lines(rendered), function()
		apply_highlights(buf, rendered)
	end)
end

local function apply_file_highlights(buf, files, selected_index)
	if #files == 0 then
		vim.api.nvim_buf_add_highlight(buf, ns, "ChunkMeta", 0, 0, -1)
		return
	end

	for index, file in ipairs(files) do
		if index == selected_index then
			vim.api.nvim_buf_add_highlight(buf, ns, "ChunkFileSelected", index - 1, 0, -1)
		end

		vim.api.nvim_buf_add_highlight(buf, ns, file_status(file.status).highlight, index - 1, 1, 2)
	end
end

function M.render_files(buf, files, selected_index)
	render_readonly_buffer(buf, file_panel_lines(files), function()
		apply_file_highlights(buf, files, selected_index)
	end)
end

local function prepare_named_buffer(buf, name, filetype)
	vim.api.nvim_buf_set_name(buf, name)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })
end

function M.prepare_buffer(buf, name)
	prepare_named_buffer(buf, name, "diff")
end

function M.prepare_files_buffer(buf, name)
	prepare_named_buffer(buf, name, "chunkfiles")
end

return M
