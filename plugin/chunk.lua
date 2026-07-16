if vim.g.loaded_chunk == 1 then
	return
end

vim.g.loaded_chunk = 1

vim.api.nvim_create_user_command("Chunk", function(args)
	require("chunk").open(args.fargs)
end, {
	desc = "Open Chunk inline git diff view",
	nargs = "*",
})
