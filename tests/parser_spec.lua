package.path = table.concat({
	vim.fn.getcwd() .. "/lua/?.lua",
	vim.fn.getcwd() .. "/lua/?/init.lua",
	package.path,
}, ";")

local parser = require("chunk.parser")
local git = require("chunk.git")

local function assert_equal(actual, expected, message)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)), 2)
	end
end

local function find_line(lines, kind, text)
	for _, line in ipairs(lines) do
		if line.kind == kind and (not text or line.text == text) then
			return line
		end
	end
end

local function test_parser_metadata()
	local diff = [[diff --git a/foo.txt b/foo.txt
index 1234567..abcdef0 100644
--- a/foo.txt
+++ b/foo.txt
@@ -1,3 +1,4 @@
 one
-old
+new
+extra
 three
diff --git a/bin.dat b/bin.dat
Binary files a/bin.dat and b/bin.dat differ
]]

	local parsed = parser.parse(diff)
	assert_equal(#parsed.files, 2, "file count")
	assert_equal(parsed.files[1].old_path, "foo.txt", "old path")
	assert_equal(parsed.files[1].new_path, "foo.txt", "new path")
	assert_equal(parsed.files[2].is_binary, true, "binary marker")

	local lines = parser.flatten(parsed)
	assert_equal(find_line(lines, "delete", "-old").old_line, 2, "deleted old line")
	assert_equal(find_line(lines, "delete", "-old").target_line, 2, "deleted target line")
	assert_equal(find_line(lines, "add", "+new").new_line, 2, "added new line")
	assert_equal(find_line(lines, "add", "+extra").new_line, 3, "second added new line")
	assert_equal(find_line(lines, "context", " three").new_line, 4, "context new line")
end

local function test_untracked_synthetic_diff()
	local diff = git.synthesize_untracked_diff("notes.txt", "alpha\nbeta\n")
	local parsed = parser.parse(diff)
	local lines = parser.flatten(parsed)

	assert_equal(#parsed.files, 1, "untracked file count")
	assert_equal(parsed.files[1].status, "added", "untracked status")
	assert_equal(parsed.files[1].old_path, nil, "untracked old path")
	assert_equal(parsed.files[1].new_path, "notes.txt", "untracked new path")
	assert_equal(find_line(lines, "add", "+alpha").new_line, 1, "first untracked line")
	assert_equal(find_line(lines, "add", "+beta").new_line, 2, "second untracked line")
end

local function test_untracked_binary_placeholder()
	local diff = git.synthesize_untracked_diff("asset.bin", "abc\0def")
	local parsed = parser.parse(diff)
	local lines = parser.flatten(parsed)

	assert_equal(parsed.files[1].is_binary, true, "binary untracked file")
	assert_equal(find_line(lines, "binary", "Binary file asset.bin added").target_line, 1, "binary target line")
end

local tests = {
	test_parser_metadata,
	test_untracked_synthetic_diff,
	test_untracked_binary_placeholder,
}

for _, test in ipairs(tests) do
	test()
end

print(("ok %d tests"):format(#tests))
