# chunk.nvim

Inline Git diff review for Neovim.

`chunk` opens a readonly unified diff buffer with a changed-files sidebar in a
dedicated tab. It shows unstaged and staged changes separately, includes
untracked files under `Changes`, and can move tracked text hunks between the
working tree and Git index without modifying the working file.

An opt-in source-backed mode displays a selected modified or untracked file in
its real buffer, with working-tree changes decorated inline against `HEAD` or
an empty baseline.

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
view and retained as it updates.

- `:Chunk` opens the inline diff view with initial focus on the sidebar's `/` root.
- `<CR>` opens the real file at the diff line.
- The diff pane shows only the file selected in the files sidebar.
- Moving the cursor in the files sidebar selects a changed file and shows its diff.
- `<CR>` in the files sidebar focuses the selected file's diff.
- `s` stages the tracked text hunk under the cursor from `Changes`.
- `u` unstages the tracked text hunk under the cursor from `Staged Changes`.
- `]h` and `[h` jump between hunks.
- `]f` and `[f` move between files while the files sidebar is focused.
- `q` closes the Chunk tab.

## Configuration

```lua
require("chunk").setup({
  context_lines = 3,
  include_untracked = true,
  open_mode = "tab",
  source_view = {
    enabled = false,
    debounce_ms = 120,
    fold_unchanged = false,
    context_lines = 3,
  },
  files_panel = {
    enabled = true,
    width = 34,
  },
  keymaps = {
    open_file = "<CR>",
    select_file = "<CR>",
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

Set any mapping to `false` or an empty string to disable it. Open Chunk views
refresh automatically after files are written, Neovim regains focus, terminal
or shell commands finish, and you return to a Chunk window. Staging and
unstaging operate on the index only. Untracked files and binary changes are
displayed but do not support hunk actions.

The files sidebar groups paths under an expandable `/` root and shows file-type
icons with per-file addition and deletion totals. A folder previews its first
changed descendant while keeping the folder selected. Press `<CR>` on a folder
to collapse or expand it. The icons are designed for a Nerd Font.

## Source-backed mode

Set `source_view.enabled = true` to make a selected modified or untracked text
file replace the unified pane with its canonical source buffer. Added and changed
lines use diff highlights; deleted `HEAD` lines are readonly virtual lines.
Unsaved edits participate in the comparison, and normal filetype, Tree-sitter,
diagnostics, LSP, editing, and `:write` behavior are preserved.
Set `fold_unchanged = true` to fold unchanged regions in the Chunk window while
keeping `context_lines` visible around each change. These folds are window-local
and do not affect another window displaying the same source buffer.

This mode currently supports one unstaged modified or untracked text file at a
time in the default working-tree comparison. Deleted, renamed, binary,
staged-only, revision/range, and multi-file source views remain in the readonly
unified mode. Hunk staging actions are only available in that unified view.
