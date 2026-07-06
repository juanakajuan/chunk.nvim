# chunk.nvim

Inline Git diff review for Neovim.

`chunk` opens a readonly unified diff buffer in a dedicated tab. It compares
`HEAD` against the working tree, includes untracked files, and keeps metadata
for each rendered line so future features can open and edit real files safely.

## Requirements

- Neovim 0.12.x
- Git

## Installation

With lazy.nvim from this local checkout:

```lua
{
  dir = "/home/juanix/Projects/chunk.nvim",
  config = function()
    require("chunk").setup()
  end,
}
```

## Usage

- `:Chunk` opens the inline diff view.
- `:ChunkRefresh` refreshes the current Chunk buffer.
- `<CR>` opens the real file at the diff line.
- `R` refreshes.
- `]h` and `[h` jump between hunks.
- `]f` and `[f` jump between files.
- `q` closes the Chunk tab.

## Configuration

```lua
require("chunk").setup({
  context_lines = 3,
  include_untracked = true,
  open_mode = "tab",
  keymaps = {
    open_file = "<CR>",
    refresh = "R",
    next_hunk = "]h",
    prev_hunk = "[h",
    next_file = "]f",
    prev_file = "[f",
    close = "q",
  },
})
```

## Current Scope

This MVP intentionally renders diffs as readonly text. Direct editing and LSP
inside the diff view are future work; the parser already records file path and
line metadata to support that direction.
