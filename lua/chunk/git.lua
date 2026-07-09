local M = {}

local function failure_message(result)
	for _, output in ipairs({ result.stderr or "", result.stdout or "" }) do
		if output ~= "" then
			return vim.trim(output)
		end
	end

	return "git command failed"
end

local function run(argv, opts)
	opts = opts or {}

	local result = vim.system(argv, {
		cwd = opts.cwd,
		stdin = opts.stdin,
		text = true,
	}):wait()

	if result.code ~= 0 then
		return nil, failure_message(result)
	end

	return result.stdout or "", nil
end

local function run_git(root, argv, opts)
	return run(vim.list_extend({ "git", "-C", root }, argv), opts)
end

local function dirname(path)
	return vim.fn.fnamemodify(path, ":p:h")
end

function M.repo_root(start)
	start = start or vim.fn.getcwd()

	local root, err = run_git(start, { "rev-parse", "--show-toplevel" })
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

local function tracked_diff(root, context_lines, cached)
	local argv = {
		"diff",
		"--no-color",
		"--no-ext-diff",
		"--unified=" .. tostring(context_lines),
	}

	if cached then
		table.insert(argv, "--cached")
	end

	table.insert(argv, "--")
	return run_git(root, argv)
end

local function list_untracked(root)
	local out, err = run_git(root, {
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

	local context_lines = opts.context_lines or 3
	local unstaged, unstaged_err = tracked_diff(root, context_lines, false)
	if not unstaged then
		return nil, unstaged_err
	end

	local staged, staged_err = tracked_diff(root, context_lines, true)
	if not staged then
		return nil, staged_err
	end

	if opts.include_untracked ~= false then
		local untracked, untracked_err = collect_untracked_diffs(root)
		if not untracked then
			return nil, untracked_err
		end

		unstaged = unstaged .. untracked
	end

	return {
		root = root,
		sections = {
			{
				id = "unstaged",
				title = "Changes",
				diff = unstaged,
			},
			{
				id = "staged",
				title = "Staged Changes",
				diff = staged,
			},
		},
	},
		nil
end

local function apply_cached_patch(root, patch, reverse)
	local argv = {
		"apply",
		"--cached",
	}

	if reverse then
		table.insert(argv, "--reverse")
	end

	local _, err = run_git(root, argv, {
		stdin = patch,
	})

	if err then
		return nil, err
	end

	return true, nil
end

function M.stage_hunk(root, patch)
	return apply_cached_patch(root, patch, false)
end

function M.unstage_hunk(root, patch)
	return apply_cached_patch(root, patch, true)
end

return M
