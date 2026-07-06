local M = {}

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

local function push_file(files, current)
	if current then
		table.insert(files, current)
	end
end

local function append_line(file, line)
	line.old_path = file.old_path
	line.new_path = file.new_path
	table.insert(file.lines, line)
end

local function append_meta_line(file, raw)
	append_line(file, {
		kind = "meta",
		text = raw,
	})
end

local function new_file(line)
	local old_path, new_path = line:match("^diff %-%-git a/(.+) b/(.+)$")

	return {
		old_path = old_path,
		new_path = new_path,
		status = "modified",
		is_binary = false,
		hunks = {},
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

	if prefix == " " then
		append_line(file, {
			kind = "context",
			text = raw,
			old_line = old_line,
			new_line = new_line,
			target_line = new_line,
			hunk = hunk,
		})
		return hunk, old_line + 1, new_line + 1
	end

	if prefix == "+" then
		append_line(file, {
			kind = "add",
			text = raw,
			new_line = new_line,
			target_line = new_line,
			hunk = hunk,
		})
		return hunk, old_line, new_line + 1
	end

	if prefix == "-" then
		append_line(file, {
			kind = "delete",
			text = raw,
			old_line = old_line,
			target_line = new_line,
			hunk = hunk,
		})
		return hunk, old_line + 1, new_line
	end

	append_fallback_line(file, raw, hunk, new_line)
	return hunk, old_line, new_line
end

local function parse_file_line(file, raw, current_hunk, old_line, new_line)
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

	local hunk = parse_hunk_header(raw)
	if hunk then
		return begin_hunk(file, raw, hunk)
	end

	if current_hunk then
		return append_hunk_body_line(file, raw, current_hunk, old_line, new_line)
	end

	append_fallback_line(file, raw, current_hunk, new_line)
	return current_hunk, old_line, new_line
end

function M.parse(diff)
	local files = {}
	local current_file = nil
	local current_hunk = nil
	local old_line = nil
	local new_line = nil

	for raw in (diff .. "\n"):gmatch("([^\n]*)\n") do
		if raw:match("^diff %-%-git ") then
			push_file(files, current_file)
			current_file = new_file(raw)
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
			})
		end

		for _, line in ipairs(file.lines) do
			line.file = file
			table.insert(lines, line)
		end
	end

	return lines
end

return M
