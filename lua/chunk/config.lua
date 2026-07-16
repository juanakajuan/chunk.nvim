local M = {}

M.defaults = {
	context_lines = 3,
	include_untracked = true,
	open_mode = "tab",
	source_view = {
		enabled = false,
		debounce_ms = 120,
		fold_unchanged = false,
		context_lines = 3,
	},
	files_panel = {
		enabled = true,
		width = 34,
	},
	keymaps = {
		open_file = "<CR>",
		select_file = "<CR>",
		stage_hunk = "s",
		unstage_hunk = "u",
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
