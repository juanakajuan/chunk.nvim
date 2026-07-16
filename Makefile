test:
	nvim --clean --headless -u NONE -l tests/diff_spec_spec.lua
	nvim --clean --headless -u NONE -l tests/git_spec.lua
	nvim --clean --headless -u NONE -l tests/parser_spec.lua
	nvim --clean --headless -u NONE -l tests/sidebar_spec.lua
	nvim --clean --headless -u NONE -l tests/view_spec.lua
	nvim --clean --headless -u NONE -l tests/async_view_spec.lua
	nvim --clean --headless -u NONE -l tests/auto_refresh_spec.lua
	nvim --clean --headless -u NONE -l tests/revision_view_spec.lua
	nvim --clean --headless -u NONE -l tests/index_spec.lua
	nvim --clean --headless -u NONE -l tests/selected_file_spec.lua
	nvim --clean --headless -u NONE -l tests/source_view_spec.lua
	nvim --clean --headless -u NONE -l tests/untracked_source_view_spec.lua
