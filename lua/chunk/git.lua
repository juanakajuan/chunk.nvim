local M = {}

local function run(argv, opts)
	opts = opts or {}

	local result = vim.system(argv, {
		cwd = opts.cwd,
		text = true,
	}):wait()

	if result.code ~= 0 then
		return nil, vim.trim(result.stderr or result.stdout or "git command failed")
	end

	return result.stdout or "", nil
end

local function dirname(path)
	return vim.fn.fnamemodify(path, ":p:h")
end

function M.repo_root(start)
	start = start or vim.fn.getcwd()

	local root, err = run({ "git", "-C", start, "rev-parse", "--show-toplevel" })
	if not root then
		return nil, err
	end

	return vim.trim(root), nil
end

function M.current_start_dir()
	local name = vim.api.nvim_buf_get_name(0)
	if name ~= "" then
		return dirname(name)
	end

	return vim.fn.getcwd()
end

local function shell_out_diff(root, context_lines)
	local has_head = run({ "git", "-C", root, "rev-parse", "--verify", "HEAD" })
	if not has_head then
		return "", nil
	end

	return run({
		"git",
		"-C",
		root,
		"diff",
		"--no-color",
		"--no-ext-diff",
		"--unified=" .. tostring(context_lines),
		"HEAD",
		"--",
	})
end

local function list_untracked(root)
	local out, err = run({
		"git",
		"-C",
		root,
		"ls-files",
		"--others",
		"--exclude-standard",
		"-z",
	})

	if not out then
		return nil, err
	end

	local files = {}
	for path in out:gmatch("([^%z]+)%z") do
		table.insert(files, path)
	end

	table.sort(files)
	return files, nil
end

local function read_file(path)
	local file, err = io.open(path, "rb")
	if not file then
		return nil, err
	end

	local data = file:read("*a")
	file:close()

	return data or "", nil
end

local function is_binary(data)
	return data:find("\0", 1, true) ~= nil
end

local function split_lines(data)
	if data == "" then
		return {}, true
	end

	local has_final_newline = data:sub(-1) == "\n"
	data = data:gsub("\r\n", "\n")

	if has_final_newline then
		data = data:sub(1, -2)
	end

	local lines = {}
	for line in (data .. "\n"):gmatch("([^\n]*)\n") do
		table.insert(lines, line)
	end

	return lines, has_final_newline
end

local function untracked_diff_header(path)
	return {
		"diff --git a/" .. path .. " b/" .. path,
		"new file mode 100644",
		"--- /dev/null",
		"+++ b/" .. path,
	}
end

local function finish_diff(diff_lines)
	return table.concat(diff_lines, "\n") .. "\n"
end

local function binary_untracked_diff(path)
	local diff_lines = untracked_diff_header(path)
	table.insert(diff_lines, "Binary file " .. path .. " added")

	return finish_diff(diff_lines)
end

local function text_untracked_diff(path, data)
	local lines, has_final_newline = split_lines(data)
	local diff_lines = untracked_diff_header(path)
	table.insert(diff_lines, ("@@ -0,0 +1,%d @@"):format(#lines))

	for _, line in ipairs(lines) do
		table.insert(diff_lines, "+" .. line)
	end

	if not has_final_newline and #lines > 0 then
		table.insert(diff_lines, "\\ No newline at end of file")
	end

	return finish_diff(diff_lines)
end

function M.synthesize_untracked_diff(path, data)
	if is_binary(data) then
		return binary_untracked_diff(path)
	end

	return text_untracked_diff(path, data)
end

local function synthesize_untracked_file(root, path)
	local data = read_file(root .. "/" .. path)
	if not data then
		return binary_untracked_diff(path)
	end

	return M.synthesize_untracked_diff(path, data)
end

local function collect_untracked_diffs(root)
	local files, err = list_untracked(root)
	if not files then
		return nil, err
	end

	local chunks = {}
	for _, path in ipairs(files) do
		table.insert(chunks, synthesize_untracked_file(root, path))
	end

	return table.concat(chunks, ""), nil
end

function M.collect(opts)
	opts = opts or {}

	local root, root_err = M.repo_root(opts.start_dir or M.current_start_dir())
	if not root then
		return nil, root_err
	end

	local tracked, tracked_err = shell_out_diff(root, opts.context_lines or 3)
	if not tracked then
		return nil, tracked_err
	end

	if opts.include_untracked == false then
		return {
			root = root,
			diff = tracked,
		}, nil
	end

	local untracked, untracked_err = collect_untracked_diffs(root)
	if not untracked then
		return nil, untracked_err
	end

	return {
		root = root,
		diff = tracked .. untracked,
	}, nil
end

return M
