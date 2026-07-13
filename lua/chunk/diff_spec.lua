local M = {}

function M.parse(args)
	args = args or {}
	local separator = nil
	for index, arg in ipairs(args) do
		if arg == "--" then
			separator = index
			break
		end
	end

	local revision_count = separator and separator - 1 or #args
	if revision_count > 1 then
		return nil, "expected at most one revision or range before '--'"
	end

	local revision = args[1]
	if separator == 1 then
		revision = nil
	end
	if revision and revision:sub(1, 1) == "-" then
		return nil, "revision or range must not start with '-'; put pathspecs after '--'"
	end

	local pathspecs = {}
	if separator then
		for index = separator + 1, #args do
			table.insert(pathspecs, args[index])
		end
	end

	return {
		mode = revision and "revision" or "working_tree",
		revision = revision,
		pathspecs = pathspecs,
	}, nil
end

local function display_token(token)
	if token == "" or token:find("%s") then
		return ("%q"):format(token)
	end

	return token
end

function M.describe(spec)
	local parts = {
		spec.mode == "revision" and spec.revision or "Working tree",
	}

	if #spec.pathspecs > 0 then
		table.insert(parts, "--")
		for _, pathspec in ipairs(spec.pathspecs) do
			table.insert(parts, display_token(pathspec))
		end
	end

	return table.concat(parts, " ")
end

function M.is_mutable(spec)
	return spec.mode == "working_tree"
end

return M
