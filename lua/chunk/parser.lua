local M = {}

local hunk_line_kinds = {
	[" "] = "context",
	["+"] = "add",
	["-"] = "delete",
}

local function strip_prefix_path(path)
	if not path or path == "/dev/null" then
		return nil
	end

	path = path:gsub('^"(.*)"$', "%1")
	return path:gsub("^[ab]/", "", 1)
end

local function parse_hunk_header(line)
	local old_start, old_count, new_start, new_count, heading = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@(.*)$")

	if not old_start then
		return nil
	end

	return {
		old_start = tonumber(old_start),
		old_count = tonumber(old_count ~= "" and old_count or "1"),
		new_start = tonumber(new_start),
		new_count = tonumber(new_count ~= "" and new_count or "1"),
		heading = vim.trim(heading or ""),
	}
end

local function build_patch(header, body)
	local lines = {}
	vim.list_extend(lines, header)
	vim.list_extend(lines, body)
	return table.concat(lines, "\n") .. "\n"
end

local function push_file(files, current)
	if current then
		for _, hunk in ipairs(current.hunks) do
			hunk.patch = build_patch(current.patch_header, hunk.patch_lines)
		end

		table.insert(files, current)
	end
end

local function append_line(file, line)
	line.old_path = file.old_path
	line.new_path = file.new_path
	line.section = file.section
	table.insert(file.lines, line)
end

local function append_meta_line(file, raw)
	append_line(file, {
		kind = "meta",
		text = raw,
	})
end

local function new_file(line, section)
	local old_path, new_path = line:match("^diff %-%-git a/(.+) b/(.+)$")

	return {
		old_path = old_path,
		new_path = new_path,
		section = section,
		status = "modified",
		is_binary = false,
		hunks = {},
		patch_header = { line },
		lines = {
			{
				kind = "file_header",
				text = line,
				old_path = old_path,
				new_path = new_path,
			},
		},
	}
end

local function append_binary_line(file, raw)
	file.is_binary = true
	append_line(file, {
		kind = "binary",
		text = raw,
		target_line = 1,
	})
end

local function append_fallback_line(file, raw, current_hunk, new_line)
	append_line(file, {
		kind = raw:sub(1, 1) == "\\" and "no_newline" or "meta",
		text = raw,
		target_line = new_line or 1,
		hunk = current_hunk,
	})
end

local function begin_hunk(file, raw, hunk)
	hunk.section = file.section
	hunk.patch_lines = { raw }
	table.insert(file.hunks, hunk)

	local old_line = hunk.old_start
	local new_line = hunk.new_start

	append_line(file, {
		kind = "hunk",
		text = raw,
		old_line = old_line,
		new_line = new_line,
		target_line = new_line,
		hunk = hunk,
	})

	return hunk, old_line, new_line
end

local function append_hunk_body_line(file, raw, hunk, old_line, new_line)
	local prefix = raw:sub(1, 1)
	local kind = hunk_line_kinds[prefix]

	if not kind then
		append_fallback_line(file, raw, hunk, new_line)
		return hunk, old_line, new_line
	end

	local line = {
		kind = kind,
		text = raw,
		target_line = new_line,
		hunk = hunk,
	}

	if prefix ~= "+" then
		line.old_line = old_line
		old_line = old_line + 1
	end

	if prefix ~= "-" then
		line.new_line = new_line
		new_line = new_line + 1
	end

	append_line(file, line)
	return hunk, old_line, new_line
end

local function parse_file_line(file, raw, current_hunk, old_line, new_line)
	local hunk = parse_hunk_header(raw)
	if hunk then
		return begin_hunk(file, raw, hunk)
	end

	if current_hunk then
		table.insert(current_hunk.patch_lines, raw)
		return append_hunk_body_line(file, raw, current_hunk, old_line, new_line)
	end

	table.insert(file.patch_header, raw)

	if raw:match("^%-%-%- ") then
		file.old_path = strip_prefix_path(raw:sub(5))
		append_meta_line(file, raw)
		return current_hunk, old_line, new_line
	end

	if raw:match("^%+%+%+ ") then
		file.new_path = strip_prefix_path(raw:sub(5))

		if file.old_path == nil and file.new_path ~= nil then
			file.status = "added"
		elseif file.new_path == nil then
			file.status = "deleted"
		end

		append_meta_line(file, raw)
		return current_hunk, old_line, new_line
	end

	if raw:match("^Binary files ") or raw:match("^Binary file ") then
		append_binary_line(file, raw)
		return current_hunk, old_line, new_line
	end

	if raw:match("^new file mode ") then
		file.status = "added"
		append_meta_line(file, raw)
		return current_hunk, old_line, new_line
	end

	if raw:match("^deleted file mode ") then
		file.status = "deleted"
		append_meta_line(file, raw)
		return current_hunk, old_line, new_line
	end

	append_fallback_line(file, raw, current_hunk, new_line)
	return current_hunk, old_line, new_line
end

function M.parse(diff, opts)
	opts = opts or {}
	local section = type(opts) == "string" and opts or opts.section
	local files = {}
	local current_file = nil
	local current_hunk = nil
	local old_line = nil
	local new_line = nil

	if diff ~= "" and diff:sub(-1) ~= "\n" then
		diff = diff .. "\n"
	end

	for raw in diff:gmatch("([^\n]*)\n") do
		if raw:match("^diff %-%-git ") then
			push_file(files, current_file)
			current_file = new_file(raw, section)
			current_hunk = nil
			old_line = nil
			new_line = nil
		elseif current_file then
			current_hunk, old_line, new_line = parse_file_line(current_file, raw, current_hunk, old_line, new_line)
		end
	end

	push_file(files, current_file)

	return {
		files = files,
	}
end

function M.flatten(parsed)
	local lines = {}

	for file_index, file in ipairs(parsed.files or {}) do
		if file_index > 1 then
			table.insert(lines, {
				kind = "blank",
				text = "",
				section = file.section,
			})
		end

		for _, line in ipairs(file.lines) do
			line.file = file
			line.section = file.section
			table.insert(lines, line)
		end
	end

	return lines
end

return M
