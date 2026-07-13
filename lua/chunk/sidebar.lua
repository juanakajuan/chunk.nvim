local M = {}

local icons = {
	rust = { "", "ChunkSidebarIconKeyword" },
	typescript = { "", "ChunkSidebarIconType" },
	react = { "", "ChunkSidebarIconSpecial" },
	javascript = { "", "ChunkSidebarIconType" },
	json = { "", "ChunkSidebarIconConstant" },
	lua = { "", "ChunkSidebarIconFunction" },
	python = { "", "ChunkSidebarIconFunction" },
	go = { "", "ChunkSidebarIconType" },
	ruby = { "", "ChunkSidebarIconSpecial" },
	java = { "", "ChunkSidebarIconSpecial" },
	c = { "", "ChunkSidebarIconType" },
	cheader = { "", "ChunkSidebarIconType" },
	cpp = { "", "ChunkSidebarIconType" },
	csharp = { "", "ChunkSidebarIconFunction" },
	markdown = { "", "ChunkSidebarIconSpecial" },
	html = { "", "ChunkSidebarIconSpecial" },
	css = { "", "ChunkSidebarIconFunction" },
	sass = { "", "ChunkSidebarIconSpecial" },
	vue = { "", "ChunkSidebarIconString" },
	shell = { "", "ChunkSidebarIconString" },
	config = { "", "ChunkSidebarIconMuted" },
	yaml = { "", "ChunkSidebarIconConstant" },
	text = { "", "ChunkSidebarIconText" },
	image = { "", "ChunkSidebarIconConstant" },
	lock = { "", "ChunkSidebarIconMuted" },
	generic = { "", "ChunkSidebarIconMuted" },
}

local extension_kinds = {
	rs = "rust",
	ts = "typescript",
	tsx = "react",
	jsx = "react",
	js = "javascript",
	mjs = "javascript",
	cjs = "javascript",
	json = "json",
	lua = "lua",
	py = "python",
	go = "go",
	rb = "ruby",
	java = "java",
	c = "c",
	h = "cheader",
	hpp = "cheader",
	hh = "cheader",
	cpp = "cpp",
	cc = "cpp",
	cxx = "cpp",
	cs = "csharp",
	md = "markdown",
	markdown = "markdown",
	html = "html",
	htm = "html",
	css = "css",
	scss = "sass",
	sass = "sass",
	vue = "vue",
	sh = "shell",
	bash = "shell",
	zsh = "shell",
	toml = "config",
	ini = "config",
	cfg = "config",
	conf = "config",
	yaml = "yaml",
	yml = "yaml",
	txt = "text",
	png = "image",
	jpg = "image",
	jpeg = "image",
	gif = "image",
	svg = "image",
	webp = "image",
	lock = "lock",
}

local function basename(path)
	return path:match("([^/]+)$") or path
end

local function file_icon(path)
	local name = basename(path):lower()
	local extension = name:match("%.([^.]*)$")
	local kind = extension_kinds[extension] or "generic"
	return unpack(icons[kind])
end

local function directory_key(section, path)
	return (section or "") .. "\31" .. path
end

local function new_tree_node()
	return {
		directories = {},
		files = {},
		file_indices = {},
	}
end

local function path_parts(path)
	local parts = {}
	for part in path:gmatch("[^/]+") do
		table.insert(parts, part)
	end
	return parts
end

local function insert_file(root, file)
	local parts = path_parts(file.path)
	local name = table.remove(parts) or file.path
	local node = root
	node.file_indices[file.file_index] = true

	for _, directory in ipairs(parts) do
		if not node.directories[directory] then
			node.directories[directory] = new_tree_node()
		end
		node = node.directories[directory]
		node.file_indices[file.file_index] = true
	end

	table.insert(node.files, {
		name = name,
		file = file,
	})
end

local function sorted_keys(values)
	local keys = {}
	for key in pairs(values) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function child_path(parent, name)
	if parent == "" then
		return name
	end
	return parent .. "/" .. name
end

local function flatten_tree(items, node, section, parent_path, depth, collapsed_directories)
	for _, name in ipairs(sorted_keys(node.directories)) do
		local child = node.directories[name]
		local path = child_path(parent_path, name)
		local key = directory_key(section.id, path)
		local expanded = collapsed_directories[key] ~= true

		table.insert(items, {
			kind = "folder",
			section = section.id,
			name = name,
			path = path,
			key = key,
			depth = depth,
			expanded = expanded,
			file_indices = child.file_indices,
		})

		if expanded then
			flatten_tree(items, child, section, path, depth + 1, collapsed_directories)
		end
	end

	table.sort(node.files, function(left, right)
		if left.name == right.name then
			return left.file.file_index < right.file.file_index
		end
		return left.name < right.name
	end)

	for _, entry in ipairs(node.files) do
		table.insert(items, {
			kind = "file",
			section = section.id,
			name = entry.name,
			depth = depth,
			file_index = entry.file.file_index,
			file = entry.file,
		})
	end
end

function M.build(sections, collapsed_directories)
	collapsed_directories = collapsed_directories or {}
	local items = {}

	for _, section in ipairs(sections or {}) do
		table.insert(items, {
			kind = "section_heading",
			text = section.title,
			section = section.id,
		})

		local root = new_tree_node()
		for _, file in ipairs(section.files or {}) do
			insert_file(root, file)
		end
		flatten_tree(items, root, section, "", 0, collapsed_directories)
	end

	return items
end

local function display_width(text)
	return vim.fn.strdisplaywidth(text)
end

local function truncate_to_width(text, max_width)
	if max_width <= 0 then
		return ""
	end
	if display_width(text) <= max_width then
		return text
	end
	if max_width == 1 then
		return "…"
	end

	local available = max_width - 1
	local result = {}
	local width = 0
	for index = 0, vim.fn.strchars(text) - 1 do
		local character = vim.fn.strcharpart(text, index, 1)
		local character_width = display_width(character)
		if width + character_width > available then
			break
		end
		table.insert(result, character)
		width = width + character_width
	end
	return table.concat(result) .. "…"
end

local function line_builder()
	return {
		parts = {},
		highlights = {},
		byte_length = 0,
		display_width = 0,
	}
end

local function append(builder, text, highlight)
	if text == "" then
		return
	end

	local start_col = builder.byte_length
	table.insert(builder.parts, text)
	builder.byte_length = builder.byte_length + #text
	builder.display_width = builder.display_width + display_width(text)
	if highlight then
		table.insert(builder.highlights, {
			group = highlight,
			start_col = start_col,
			end_col = builder.byte_length,
		})
	end
end

local function finish(builder, selected)
	return {
		text = table.concat(builder.parts),
		highlights = builder.highlights,
		selected = selected,
	}
end

local function file_name_highlight(file)
	if file.section == "staged" then
		return "ChunkSidebarStaged"
	end
	if file.status == "added" then
		return "ChunkSidebarAdded"
	end
	if file.status == "deleted" then
		return "ChunkSidebarDeleted"
	end
	return "ChunkSidebarFile"
end

local function stats(file)
	if file.is_binary then
		return {
			{ text = "binary", group = "ChunkBinary" },
		}
	end

	local result = {}
	if (file.additions or 0) > 0 then
		table.insert(result, {
			text = "+" .. file.additions,
			group = "ChunkSidebarAdded",
		})
	end
	if (file.deletions or 0) > 0 then
		if #result > 0 then
			table.insert(result, { text = " " })
		end
		table.insert(result, {
			text = "-" .. file.deletions,
			group = "ChunkSidebarDeleted",
		})
	end
	return result
end

local function parts_width(parts)
	local width = 0
	for _, part in ipairs(parts) do
		width = width + display_width(part.text)
	end
	return width
end

local function render_file(item, selected_index, width)
	local builder = line_builder()
	local prefix = string.rep("  ", item.depth) .. "  "
	local icon, icon_highlight = file_icon(item.file.path)
	local fixed = prefix .. icon .. " "
	local stat_parts = stats(item.file)
	local stat_width = parts_width(stat_parts)
	if display_width(fixed) + stat_width + 1 > width then
		stat_parts = {}
		stat_width = 0
	end

	if display_width(fixed) >= width then
		append(builder, truncate_to_width(fixed, width), "ChunkMeta")
		return finish(builder, item.file_index == selected_index)
	end

	append(builder, prefix, "ChunkMeta")
	append(builder, icon, icon_highlight)
	append(builder, " ")

	local reserved = stat_width > 0 and stat_width + 1 or 0
	local name_width = math.max(0, width - builder.display_width - reserved)
	append(builder, truncate_to_width(item.name, name_width), file_name_highlight(item.file))

	if stat_width > 0 then
		local padding = math.max(1, width - builder.display_width - stat_width)
		append(builder, string.rep(" ", padding))
		for _, part in ipairs(stat_parts) do
			append(builder, part.text, part.group)
		end
	end

	return finish(builder, item.file_index == selected_index)
end

local function render_folder(item, selected_index, width)
	local builder = line_builder()
	local prefix = string.rep("  ", item.depth)
	local chevron = item.expanded and "▾" or "▸"
	local folder_icon = item.expanded and "" or ""
	local fixed = prefix .. chevron .. " " .. folder_icon .. " "
	local selected = not item.expanded and item.file_indices[selected_index] == true

	if display_width(fixed) >= width then
		append(builder, truncate_to_width(fixed, width), "ChunkMeta")
		return finish(builder, selected)
	end

	append(builder, prefix, "ChunkMeta")
	append(builder, chevron, "ChunkSidebarAccent")
	append(builder, " ")
	local folder_highlight = item.section == "staged" and "ChunkSidebarStaged" or "ChunkSidebarFolder"
	append(builder, folder_icon, folder_highlight)
	append(builder, " ")
	append(builder, truncate_to_width(item.name .. "/", width - builder.display_width), folder_highlight)
	return finish(builder, selected)
end

function M.render(items, selected_index, width)
	width = math.max(1, math.floor(tonumber(width) or 34))
	local rendered = {}

	for _, item in ipairs(items) do
		if item.kind == "section_heading" then
			table.insert(rendered, {
				text = truncate_to_width(item.text, width),
				highlights = {
					{
						group = "ChunkSection",
						start_col = 0,
						end_col = -1,
					},
				},
			})
		elseif item.kind == "folder" then
			table.insert(rendered, render_folder(item, selected_index, width))
		else
			table.insert(rendered, render_file(item, selected_index, width))
		end
	end

	return rendered
end

M.directory_key = directory_key

return M
