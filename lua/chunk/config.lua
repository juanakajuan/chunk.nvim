local M = {}

M.defaults = {
	context_lines = 3,
	include_untracked = true,
	open_mode = "tab",
	files_panel = {
		enabled = true,
		width = 30,
	},
	keymaps = {
		open_file = "<CR>",
		select_file = "<CR>",
		refresh = "R",
		next_hunk = "]h",
		prev_hunk = "[h",
		next_file = "]f",
		prev_file = "[f",
		close = "q",
	},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
