if vim.g.loaded_chunk == 1 then
	return
end

vim.g.loaded_chunk = 1

vim.api.nvim_create_user_command("Chunk", function()
	require("chunk").open()
end, {
	desc = "Open Chunk inline git diff view",
})

vim.api.nvim_create_user_command("ChunkRefresh", function()
	require("chunk").refresh()
end, {
	desc = "Refresh the current Chunk diff view",
})
