# chunk.nvim

Inline Git diff review for Neovim.

`chunk` opens a readonly unified diff buffer with a changed-files sidebar in a
dedicated tab. It shows unstaged and staged changes separately, includes
untracked files under `Changes`, and can move tracked text hunks between the
working tree and Git index without modifying the working file.

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
- `<CR>` in the files sidebar selects a changed file and shows its diff.
- `R` refreshes.
- `s` stages the tracked text hunk under the cursor from `Changes`.
- `u` unstages the tracked text hunk under the cursor from `Staged Changes`.
- `]h` and `[h` jump between hunks.
- `]f` and `[f` jump between files.
- `q` closes the Chunk tab.

## Configuration

```lua
require("chunk").setup({
  context_lines = 3,
  include_untracked = true,
  open_mode = "tab",
  files_panel = {
    enabled = true,
    width = 30,
  },
  keymaps = {
    open_file = "<CR>",
    select_file = "<CR>",
    refresh = "R",
    stage_hunk = "s",
    unstage_hunk = "u",
    next_hunk = "]h",
    prev_hunk = "[h",
    next_file = "]f",
    prev_file = "[f",
    close = "q",
  },
})
```

Set either mapping to `false` or an empty string to disable it. Staging and
unstaging operate on the index only and refresh the view after Git accepts the
patch. Untracked files and binary changes are displayed but do not support
hunk actions.

## Current Scope

The diff remains readonly: direct editing, LSP support, file-level actions,
visual-range staging, and discard/reset operations are outside the current
scope.
