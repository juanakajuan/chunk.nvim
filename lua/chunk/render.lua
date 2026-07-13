local M = {}

local ns = vim.api.nvim_create_namespace("chunk")
local sidebar = require("chunk.sidebar")

local highlights = {
	ChunkFile = "Directory",
	ChunkHunk = "Title",
	ChunkMeta = "Comment",
	ChunkBinary = "WarningMsg",
	ChunkSection = "Title",
	ChunkFileSelected = "Visual",
	ChunkSidebarNormal = "Normal",
	ChunkSidebarBorder = "WinSeparator",
	ChunkSidebarFile = "Normal",
	ChunkSidebarFolder = "Directory",
	ChunkSidebarFolderIcon = "Directory",
	ChunkSidebarAccent = "Special",
	ChunkSidebarAdded = "DiagnosticOk",
	ChunkSidebarDeleted = "DiagnosticError",
	ChunkSidebarStaged = "DiagnosticOk",
	ChunkSidebarIconKeyword = "Keyword",
	ChunkSidebarIconType = "Type",
	ChunkSidebarIconSpecial = "Special",
	ChunkSidebarIconFunction = "Function",
	ChunkSidebarIconConstant = "Constant",
	ChunkSidebarIconString = "String",
	ChunkSidebarIconText = "Normal",
	ChunkSidebarIconMuted = "Comment",
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

local function set_range_highlight(buf, group, row, start_col, end_col)
	if end_col < 0 then
		local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
		end_col = #line
	end

	vim.api.nvim_buf_set_extmark(buf, ns, row, start_col, {
		end_col = end_col,
		hl_group = group,
	})
end

local function apply_highlights(buf, rendered)
	for index, line in ipairs(rendered) do
		local group = line_highlights[line.kind]
		if group then
			set_range_highlight(buf, group, index - 1, 0, -1)
		end
	end
end

function M.render(buf, rendered)
	render_readonly_buffer(buf, text_lines(rendered), function()
		apply_highlights(buf, rendered)
	end)
end

local function apply_file_highlights(buf, rendered)
	if #rendered == 0 then
		set_range_highlight(buf, "ChunkMeta", 0, 0, -1)
		return
	end

	for row, line in ipairs(rendered) do
		if line.selected then
			vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
				line_hl_group = "ChunkFileSelected",
				hl_eol = true,
				priority = 100,
			})
		end
		for _, highlight in ipairs(line.highlights or {}) do
			set_range_highlight(buf, highlight.group, row - 1, highlight.start_col, highlight.end_col)
		end
	end
end

function M.render_files(buf, items, selected_index, width)
	local rendered = sidebar.render(items, selected_index, width)
	local lines = #rendered == 0 and { "No changed files" } or text_lines(rendered)
	render_readonly_buffer(buf, lines, function()
		apply_file_highlights(buf, rendered)
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
