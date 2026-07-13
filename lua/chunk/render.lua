local M = {}

local ns = vim.api.nvim_create_namespace("chunk")

local highlights = {
	ChunkFile = "Directory",
	ChunkHunk = "Title",
	ChunkMeta = "Comment",
	ChunkBinary = "WarningMsg",
	ChunkSection = "Title",
	ChunkFileSelected = "Visual",
}

local diff_highlights = {
	ChunkAdd = { bg = "#26331D" },
	ChunkDelete = { bg = "#3A2122" },
}

local line_highlights = {
	file_header = "ChunkFile",
	hunk = "ChunkHunk",
	add = "ChunkAdd",
	delete = "ChunkDelete",
	meta = "ChunkMeta",
	no_newline = "ChunkMeta",
	binary = "ChunkBinary",
	section_heading = "ChunkSection",
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

function M.set_highlights()
	for group, target in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, {
			link = target,
			default = true,
		})
	end
	for group, highlight in pairs(diff_highlights) do
		highlight.default = true
		vim.api.nvim_set_hl(0, group, highlight)
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

local function file_panel_lines(items)
	if #items == 0 then
		return { "No changed files" }
	end

	local lines = {}
	for _, item in ipairs(items) do
		if item.kind == "section_heading" then
			table.insert(lines, item.text)
		else
			local file = item.file
			local status = file_status(file.status)
			local suffix = file.is_binary and " [binary]" or ""
			table.insert(lines, (" %s %s%s"):format(status.label, file.path, suffix))
		end
	end

	return lines
end

local function render_readonly_buffer(buf, lines, apply_buffer_highlights)
	M.set_highlights()

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

local function apply_file_highlights(buf, items, selected_index)
	if #items == 0 then
		vim.api.nvim_buf_add_highlight(buf, ns, "ChunkMeta", 0, 0, -1)
		return
	end

	for row, item in ipairs(items) do
		if item.kind == "section_heading" then
			vim.api.nvim_buf_add_highlight(buf, ns, "ChunkSection", row - 1, 0, -1)
		else
			local file = item.file
			if item.file_index == selected_index then
				vim.api.nvim_buf_add_highlight(buf, ns, "ChunkFileSelected", row - 1, 0, -1)
			end

			vim.api.nvim_buf_add_highlight(buf, ns, file_status(file.status).highlight, row - 1, 1, 2)
		end
	end
end

function M.render_files(buf, items, selected_index)
	render_readonly_buffer(buf, file_panel_lines(items), function()
		apply_file_highlights(buf, items, selected_index)
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
