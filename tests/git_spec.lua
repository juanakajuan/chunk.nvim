package.path = table.concat({
	vim.fn.getcwd() .. "/lua/?.lua",
	vim.fn.getcwd() .. "/lua/?/init.lua",
	package.path,
}, ";")

local diff_spec = require("chunk.diff_spec")
local git = require("chunk.git")

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)), 2)
	end
end

local function assert_contains(value, expected, message)
	if not value:find(expected, 1, true) then
		error(("%s: expected %s to contain %s"):format(message, vim.inspect(value), vim.inspect(expected)), 2)
	end
end

local function assert_not_contains(value, unexpected, message)
	if value:find(unexpected, 1, true) then
		error(("%s: expected %s not to contain %s"):format(message, vim.inspect(value), vim.inspect(unexpected)), 2)
	end
end

local function run(argv, cwd)
	local result = vim.system(argv, {
		cwd = cwd,
		text = true,
	}):wait()

	if result.code ~= 0 then
		error(("command failed: %s\n%s"):format(table.concat(argv, " "), result.stderr or result.stdout or ""), 2)
	end
end

local function write_file(path, lines)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile(lines, path)
end

local function with_repo(fn)
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")

	local ok, err = xpcall(function()
		run({ "git", "init", "-q" }, root)
		run({ "git", "config", "user.name", "Chunk Test" }, root)
		run({ "git", "config", "user.email", "chunk@example.com" }, root)
		write_file(root .. "/lua/tracked.lua", { "return 'base'" })
		write_file(root .. "/tests/tracked.lua", { "return 'base'" })
		run({ "git", "add", "." }, root)
		run({ "git", "commit", "-qm", "initial" }, root)

		write_file(root .. "/lua/tracked.lua", { "return 'selected'" })
		write_file(root .. "/tests/tracked.lua", { "return 'ignored'" })
		write_file(root .. "/lua/untracked.lua", { "return 'selected untracked'" })
		write_file(root .. "/tests/untracked.lua", { "return 'ignored untracked'" })
		fn(root)
	end, debug.traceback)

	vim.fn.delete(root, "rf")
	if not ok then
		error(err, 0)
	end
end

local function test_working_tree_pathspec_filters_tracked_and_untracked_files()
	with_repo(function(root)
		local spec = assert(diff_spec.parse({ "--", "lua/" }))
		local collected = assert(git.collect({
			start_dir = root,
			include_untracked = true,
			spec = spec,
		}))
		local changes = collected.sections[1].diff

		assert_equal(collected.sections[1].title, "Changes: Working tree -- lua/", "visible path filter")
		assert_equal(collected.sections[2].title, "Staged Changes: Working tree -- lua/", "visible staged path filter")
		assert_contains(changes, "lua/tracked.lua", "matching tracked file")
		assert_contains(changes, "lua/untracked.lua", "matching untracked file")
		assert_not_contains(changes, "tests/tracked.lua", "non-matching tracked file")
		assert_not_contains(changes, "tests/untracked.lua", "non-matching untracked file")
	end)
end

local function test_revision_range_collects_one_filtered_readonly_comparison()
	with_repo(function(root)
		run({ "git", "add", "." }, root)
		run({ "git", "commit", "-qm", "working changes" }, root)
		run({ "git", "branch", "main" }, root)
		run({ "git", "checkout", "-qb", "feature" }, root)
		write_file(root .. "/lua/feature.lua", { "return 'feature'" })
		write_file(root .. "/tests/feature.lua", { "return 'outside filter'" })
		run({ "git", "add", "." }, root)
		run({ "git", "commit", "-qm", "feature changes" }, root)
		run({ "git", "checkout", "-q", "main" }, root)
		write_file(root .. "/lua/main.lua", { "return 'main'" })
		run({ "git", "add", "." }, root)
		run({ "git", "commit", "-qm", "main changes" }, root)
		run({ "git", "checkout", "-q", "feature" }, root)
		write_file(root .. "/lua/current-only.lua", { "return 'not historical'" })

		local spec = assert(diff_spec.parse({ "main...HEAD", "--", "lua/" }))
		local collected = assert(git.collect({
			start_dir = root,
			include_untracked = true,
			spec = spec,
		}))

		assert_equal(#collected.sections, 1, "revision comparison section count")
		assert_equal(collected.sections[1].id, "comparison", "revision comparison section identity")
		assert_equal(collected.sections[1].title, "Comparison: main...HEAD -- lua/", "visible comparison description")
		assert_contains(collected.sections[1].diff, "lua/feature.lua", "matching revision change")
		assert_not_contains(collected.sections[1].diff, "tests/feature.lua", "non-matching revision change")
		assert_not_contains(collected.sections[1].diff, "lua/current-only.lua", "untracked file is not synthesized")
	end)
end

test_working_tree_pathspec_filters_tracked_and_untracked_files()
test_revision_range_collects_one_filtered_readonly_comparison()
print("ok 2 tests")
