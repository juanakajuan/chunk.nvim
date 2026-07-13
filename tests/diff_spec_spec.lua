package.path = table.concat({
	vim.fn.getcwd() .. "/lua/?.lua",
	vim.fn.getcwd() .. "/lua/?/init.lua",
	package.path,
}, ";")

local diff_spec = require("chunk.diff_spec")
local git = require("chunk.git")

local function assert_deep_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)), 2)
	end
end

local function test_parses_revision_and_pathspecs()
	local spec, err = diff_spec.parse({ "main...HEAD", "--", "lua/", "tests/a file.lua" })

	assert_deep_equal(err, nil, "valid arguments have no error")
	assert_deep_equal(spec, {
		mode = "revision",
		revision = "main...HEAD",
		pathspecs = { "lua/", "tests/a file.lua" },
	}, "revision and pathspecs")
end

local function test_parses_working_tree_views()
	local unfiltered = assert(diff_spec.parse({}))
	local filtered = assert(diff_spec.parse({ "--", "lua/", "notes with spaces.txt" }))

	assert_deep_equal(unfiltered, {
		mode = "working_tree",
		pathspecs = {},
	}, "default working-tree view")
	assert_deep_equal(filtered, {
		mode = "working_tree",
		pathspecs = { "lua/", "notes with spaces.txt" },
	}, "path-filtered working-tree view")
end

local function test_rejects_malformed_revision_arguments()
	local too_many, too_many_err = diff_spec.parse({ "main", "HEAD", "--", "lua/" })
	local option, option_err = diff_spec.parse({ "--stat" })

	assert_deep_equal(too_many, nil, "multiple revisions are rejected")
	assert(
		too_many_err:find("at most one revision or range", 1, true),
		"multiple-revision error explains the command contract"
	)
	assert_deep_equal(option, nil, "Git options are rejected as revisions")
	assert(option_err:find("must not start with '-'", 1, true), "option-like revision error explains the restriction")
end

local function test_describes_views_and_reports_mutability()
	local working_tree = assert(diff_spec.parse({ "--", "lua/" }))
	local revision = assert(diff_spec.parse({ "main...HEAD", "--", "lua/", "tests/" }))

	assert_deep_equal(diff_spec.describe(working_tree), "Working tree -- lua/", "working-tree description")
	assert_deep_equal(diff_spec.describe(revision), "main...HEAD -- lua/ tests/", "revision description")
	assert_deep_equal(diff_spec.is_mutable(working_tree), true, "working-tree view is mutable")
	assert_deep_equal(diff_spec.is_mutable(revision), false, "revision view is non-mutable")
end

local function test_builds_git_diff_argv_without_shell_parsing()
	local revision = assert(diff_spec.parse({ "main...HEAD", "--", "lua/", "tests/a file.lua", "; touch nope" }))
	local working_tree = assert(diff_spec.parse({ "--", "lua/" }))

	assert_deep_equal(git.diff_argv(revision, 5, false), {
		"diff",
		"--no-color",
		"--no-ext-diff",
		"--unified=5",
		"main...HEAD",
		"--",
		"lua/",
		"tests/a file.lua",
		"; touch nope",
	}, "revision diff argv")
	assert_deep_equal(git.diff_argv(working_tree, 3, true), {
		"diff",
		"--no-color",
		"--no-ext-diff",
		"--unified=3",
		"--cached",
		"--",
		"lua/",
	}, "staged working-tree diff argv")
end

test_parses_revision_and_pathspecs()
test_parses_working_tree_views()
test_rejects_malformed_revision_arguments()
test_describes_views_and_reports_mutability()
test_builds_git_diff_argv_without_shell_parsing()
print("ok 5 tests")
