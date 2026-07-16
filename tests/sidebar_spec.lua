package.path = table.concat({
	vim.fn.getcwd() .. "/lua/?.lua",
	vim.fn.getcwd() .. "/lua/?/init.lua",
	package.path,
}, ";")

local sidebar = require("chunk.sidebar")

local function assert_equal(actual, expected, message)
	if not vim.deep_equal(actual, expected) then
		error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)), 2)
	end
end

local function assert_match(value, pattern, message)
	if not value:match(pattern) then
		error(("%s: expected %s to match %s"):format(message, vim.inspect(value), vim.inspect(pattern)), 2)
	end
end

local files = {
	{
		file_index = 1,
		path = "README.md",
		section = "unstaged",
		status = "modified",
		additions = 3,
		deletions = 1,
	},
	{
		file_index = 2,
		path = "lua/chunk/init.lua",
		section = "unstaged",
		status = "modified",
		additions = 8,
		deletions = 2,
	},
	{
		file_index = 3,
		path = "lua/chunk/render.lua",
		section = "unstaged",
		status = "added",
		additions = 12,
		deletions = 0,
	},
	{
		file_index = 4,
		path = "tests/view_spec.lua",
		section = "unstaged",
		status = "modified",
		additions = 2,
		deletions = 2,
	},
}

local sections = {
	{
		id = "unstaged",
		title = "Changes",
		files = files,
	},
}

local function item_summary(items)
	local summary = {}
	for _, item in ipairs(items) do
		table.insert(summary, {
			kind = item.kind,
			name = item.name,
			depth = item.depth,
		})
	end
	return summary
end

local function test_builds_rooted_file_first_tree()
	local items = sidebar.build(sections)
	assert_equal(item_summary(items), {
		{ kind = "section_heading" },
		{ kind = "folder", name = "", depth = 0 },
		{ kind = "file", name = "README.md", depth = 1 },
		{ kind = "folder", name = "lua", depth = 1 },
		{ kind = "folder", name = "chunk", depth = 2 },
		{ kind = "file", name = "init.lua", depth = 3 },
		{ kind = "file", name = "render.lua", depth = 3 },
		{ kind = "folder", name = "tests", depth = 1 },
		{ kind = "file", name = "view_spec.lua", depth = 2 },
	}, "directory tree order")
end

local function test_collapsed_folder_hides_children_and_carries_selection()
	local collapsed = {
		[sidebar.directory_key("unstaged", "lua")] = true,
	}
	local items = sidebar.build(sections, collapsed)
	assert_equal(item_summary(items), {
		{ kind = "section_heading" },
		{ kind = "folder", name = "", depth = 0 },
		{ kind = "file", name = "README.md", depth = 1 },
		{ kind = "folder", name = "lua", depth = 1 },
		{ kind = "folder", name = "tests", depth = 1 },
		{ kind = "file", name = "view_spec.lua", depth = 2 },
	}, "collapsed tree")

	local rendered = sidebar.render(items, 2, 28)
	assert(rendered[4].selected, "collapsed ancestor represents its hidden selected file")
	assert_match(rendered[4].text, "^  ▸ .+ lua/$", "collapsed folder appearance")
end

local function test_renders_icons_and_right_aligned_stats()
	local items = sidebar.build(sections)
	local rendered = sidebar.render(items, 1, 28)
	local readme = rendered[3]
	assert_match(readme.text, "^     README%.md%s+%+3 %-1$", "file icon and stats")
	assert_equal(vim.fn.strdisplaywidth(readme.text), 28, "stats align to panel edge")
	assert(readme.selected, "selected file row is marked")

	for _, line in ipairs(sidebar.render(items, 1, 8)) do
		assert(vim.fn.strdisplaywidth(line.text) <= 8, "narrow sidebar lines stay within the panel")
	end
end

local tests = {
	test_builds_rooted_file_first_tree,
	test_collapsed_folder_hides_children_and_carries_selection,
	test_renders_icons_and_right_aligned_stats,
}

for _, test in ipairs(tests) do
	test()
end

print(("ok %d tests"):format(#tests))
