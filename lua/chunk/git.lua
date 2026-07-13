local diff_spec = require("chunk.diff_spec")

local M = {}

local function default_system(argv, opts, callback)
	local process = vim.system(argv, {
		cwd = opts.cwd,
		stdin = opts.stdin,
		text = true,
	}, callback)

	return function()
		pcall(process.kill, process, 15)
	end
end

local function default_read_file(path, callback)
	vim.uv.fs_open(path, "r", 438, function(open_err, fd)
		if open_err then
			callback(nil, open_err)
			return
		end

		vim.uv.fs_fstat(fd, function(stat_err, stat)
			if stat_err then
				vim.uv.fs_close(fd)
				callback(nil, stat_err)
				return
			end

			vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
				vim.uv.fs_close(fd)
				callback(read_err and nil or (data or ""), read_err)
			end)
		end)
	end)
end

local default_adapter = {
	system = default_system,
	read_file = default_read_file,
}

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

function M.head_lines(root, path)
	local data, err = run_git(root, { "show", "HEAD:" .. path })
	if not data then
		return nil, err
	end
	if data:find("\0", 1, true) then
		return nil, "binary baseline"
	end
	local lines = vim.split(data, "\n", { plain = true })
	if data:sub(-1) == "\n" then
		table.remove(lines)
	end
	return lines, nil
end

function M.diff_argv(spec, context_lines, cached)
	local argv = {
		"diff",
		"--no-color",
		"--no-ext-diff",
		"--unified=" .. tostring(context_lines),
	}

	if cached then
		table.insert(argv, "--cached")
	end

	if spec.mode == "revision" then
		table.insert(argv, spec.revision)
	end

	table.insert(argv, "--")
	vim.list_extend(argv, spec.pathspecs or {})
	return argv
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

local function revision_collection(root, spec, comparison)
	local description = diff_spec.describe(spec)
	return {
		root = root,
		spec = spec,
		description = description,
		mutable = diff_spec.is_mutable(spec),
		empty_message = "No changes for " .. description,
		sections = {
			{
				id = "comparison",
				title = "Comparison: " .. description,
				diff = comparison,
			},
		},
	}
end

local function working_tree_collection(root, spec, unstaged, staged)
	local description = diff_spec.describe(spec)
	local changes_title = "Changes"
	local staged_title = "Staged Changes"
	local empty_message = "No staged or unstaged changes"
	if #spec.pathspecs > 0 then
		changes_title = changes_title .. ": " .. description
		staged_title = staged_title .. ": " .. description
		empty_message = empty_message .. " for " .. description
	end

	return {
		root = root,
		spec = spec,
		description = description,
		mutable = diff_spec.is_mutable(spec),
		empty_message = empty_message,
		sections = {
			{ id = "unstaged", title = changes_title, diff = unstaged },
			{ id = "staged", title = staged_title, diff = staged },
		},
	}
end

---Collect repository changes without blocking Neovim.
---@param opts table
---@param callback fun(collected: table|nil, err: string|nil)
---@return table handle A handle with a cancellable `cancel()` method.
function M.collect(opts, callback)
	opts = opts or {}
	local adapter = opts.adapter or default_adapter
	local cancelled = false
	local completed = false
	local cancellations = {}

	local function finish(collected, err)
		if cancelled or completed then
			return
		end
		completed = true
		callback(collected, err)
	end

	local function system(argv, system_opts, done)
		if cancelled then
			return
		end
		local cancel = adapter.system(argv, system_opts or {}, function(result)
			if cancelled then
				return
			end
			if result.code ~= 0 then
				done(nil, failure_message(result))
				return
			end
			done(result.stdout or "", nil)
		end)
		if type(cancel) == "function" then
			table.insert(cancellations, cancel)
		elseif type(cancel) == "table" and type(cancel.cancel) == "function" then
			table.insert(cancellations, function()
				cancel:cancel()
			end)
		end
	end

	local function git(root, argv, done)
		system(vim.list_extend({ "git", "-C", root }, vim.deepcopy(argv)), {}, done)
	end

	local spec = opts.spec or { mode = "working_tree", pathspecs = {} }
	local context_lines = opts.context_lines or 3
	local start_dir = opts.start_dir or M.current_start_dir()

	local function assemble(root, unstaged, staged)
		finish(working_tree_collection(root, spec, unstaged, staged), nil)
	end

	local function collect_untracked(root, done)
		local argv = { "ls-files", "--others", "--exclude-standard", "-z", "--" }
		vim.list_extend(argv, spec.pathspecs or {})
		git(root, argv, function(out, err)
			if not out then
				done(nil, err)
				return
			end
			local files = {}
			for path in out:gmatch("([^%z]+)%z") do
				table.insert(files, path)
			end
			table.sort(files)
			if #files == 0 then
				done("", nil)
				return
			end

			local remaining = #files
			local chunks = {}
			for index, path in ipairs(files) do
				adapter.read_file(root .. "/" .. path, function(data)
					if cancelled then
						return
					end
					chunks[index] = data and M.synthesize_untracked_diff(path, data) or binary_untracked_diff(path)
					remaining = remaining - 1
					if remaining == 0 then
						done(table.concat(chunks, ""), nil)
					end
				end)
			end
		end)
	end

	git(start_dir, { "rev-parse", "--show-toplevel" }, function(root_out, root_err)
		if not root_out then
			finish(nil, root_err)
			return
		end
		local root = vim.trim(root_out)
		if spec.mode == "revision" then
			git(root, M.diff_argv(spec, context_lines, false), function(comparison, comparison_err)
				if not comparison then
					finish(nil, ("Git rejected revision or range %q: %s"):format(spec.revision, comparison_err))
					return
				end
				finish(revision_collection(root, spec, comparison), nil)
			end)
			return
		end

		git(root, M.diff_argv(spec, context_lines, false), function(unstaged, unstaged_err)
			if not unstaged then
				finish(nil, unstaged_err)
				return
			end
			git(root, M.diff_argv(spec, context_lines, true), function(staged, staged_err)
				if not staged then
					finish(nil, staged_err)
					return
				end
				if opts.include_untracked == false then
					assemble(root, unstaged, staged)
					return
				end
				collect_untracked(root, function(untracked, untracked_err)
					if not untracked then
						finish(nil, untracked_err)
						return
					end
					assemble(root, unstaged .. untracked, staged)
				end)
			end)
		end)
	end)

	return {
		cancel = function()
			if cancelled or completed then
				return
			end
			cancelled = true
			for _, cancel in ipairs(cancellations) do
				pcall(cancel)
			end
		end,
	}
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
