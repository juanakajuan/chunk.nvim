local M = {}

local ns = vim.api.nvim_create_namespace("chunk")

local highlights = {
	ChunkFile = "Directory",
	ChunkHunk = "Title",
	ChunkAdd = "DiffAdd",
	ChunkDelete = "DiffDelete",
	ChunkMeta = "Comment",
	ChunkBinary = "WarningMsg",
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

local function apply_highlights(buf, rendered)
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	for index, line in ipairs(rendered) do
		local group = line_highlights[line.kind]
		if group then
			vim.api.nvim_buf_add_highlight(buf, ns, group, index - 1, 0, -1)
		end
	end
end

function M.render(buf, rendered)
	set_highlights()

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_set_option_value("readonly", false, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, text_lines(rendered))
	apply_highlights(buf, rendered)
	vim.api.nvim_set_option_value("modified", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
end

function M.prepare_buffer(buf, name)
	vim.api.nvim_buf_set_name(buf, name)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("filetype", "diff", { buf = buf })
end

return M
