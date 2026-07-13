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

```text
:Chunk [<revision-or-range>] [-- <pathspec>...]
```

Examples:

```vim
:Chunk
:Chunk main...HEAD
:Chunk HEAD~3..HEAD -- lua/ tests/
:Chunk -- lua/
```

With no arguments, `:Chunk` opens the existing working-tree view with unstaged,
staged, and configured untracked changes. Put Git pathspecs after `--` to limit
that view; matching untracked files are included when `include_untracked` is
enabled.

One revision or range may appear before `--`. Revision views show a single
read-only comparison, do not synthesize untracked files, and do not provide the
stage or unstage actions. The active revision and pathspecs are shown in the
view and retained when it is refreshed.

- `:Chunk` opens the inline diff view using the syntax above.
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
