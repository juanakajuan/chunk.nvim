test:
	nvim --clean --headless -u NONE -l tests/parser_spec.lua
	nvim --clean --headless -u NONE -l tests/view_spec.lua
