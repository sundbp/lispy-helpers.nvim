# lispy-kill.nvim

A Neovim implementation of `lispy-kill` from the Emacs [lispy](https://github.com/abo-abo/lispy) package. This provides a structure-aware kill command that keeps parentheses balanced—essential for comfortable Lisp editing.

## Features

- **Balanced killing**: Never leaves unmatched parentheses, brackets, or braces
- **Context-aware**: Behaves differently in strings, comments, and code
- **Treesitter support**: Uses treesitter when available for accurate parsing
- **Graceful fallback**: Works with vim syntax highlighting when treesitter isn't available
- **Kill ring integration**: Killed text is stored in the default register for yanking

## Installation

### lazy.nvim

```lua
{
  'sundbp/lispy-kill.nvim',
  ft = { 'lisp', 'scheme', 'clojure', 'fennel', 'racket', 'janet', 'yuck' },
  opts = {
    key = '<C-k>',  -- default keybinding
  },
}
```

Or with more explicit configuration:

```lua
{
  'sundbp/lispy-kill.nvim',
  ft = { 'lisp', 'scheme', 'clojure', 'fennel', 'racket' },
  config = function()
    require('lispy-kill').setup({
      key = '<C-k>',
      filetypes = { 'lisp', 'scheme', 'clojure', 'fennel', 'racket', 'janet', 'yuck' },
    })
  end,
}
```

### packer.nvim

```lua
use {
  'sundbp/lispy-kill.nvim',
  ft = { 'lisp', 'scheme', 'clojure', 'fennel', 'racket' },
  config = function()
    require('lispy-kill').setup()
  end,
}
```

### Manual installation

1. Clone or copy to your Neovim packages directory:

   ```bash
   mkdir -p ~/.local/share/nvim/site/pack/plugins/start
   cd ~/.local/share/nvim/site/pack/plugins/start
   git clone https://github.com/sundbp/lispy-kill.nvim
   ```

2. Add to your `init.lua`:

   ```lua
   require('lispy-kill').setup()
   ```

## Usage

By default, `<C-k>` is bound in normal and insert mode for lisp filetypes.

You can also call the function directly:

```lua
-- In a keymap
vim.keymap.set('n', '<leader>k', require('lispy-kill').kill)

-- Or use the command
:LispyKill
```

## Behavior

The kill command tries these conditions in order (matching the original Emacs behavior):

| Condition | Action |
|-----------|--------|
| Inside a comment | Standard `kill-line` (kill to end of line) |
| Inside a string that extends past line | Standard `kill-line` |
| Inside a string that ends on this line | Delete up to (but not including) closing quote |
| On a whitespace-only line | Delete entire line, move to next, re-indent |
| Inside an empty list `()` | Delete the empty list |
| Parens balanced from cursor to EOL | Standard `kill-line` |
| At an opening delimiter `(`, `[`, `{` | Kill entire sexp (including closing delimiter) |
| Inside a list (can find closing paren) | Delete from cursor to end of list (before closing paren) |
| Otherwise | Delete current sexp |

## Examples

### Kill to end of list

```lisp
;; Before (| = cursor):
(defun test ()
  |(foo bar baz)
  (qux))

;; After <C-k>:
(defun test ()
  |
  (qux))
```

### Kill sexp at opening paren

```lisp
;; Before (cursor ON the opening paren of (bar)):
(foo |(bar))

;; After <C-k>:
(foo |)
```

### Preserve balanced structure

```lisp
;; Before:
(foo bar| baz quux)

;; After <C-k>:
(foo bar|)
```

### Kill in string

```lisp
;; Before:
(message "hello |world")

;; After <C-k>:
(message "hello |")
```

### Delete empty list

```lisp
;; Before:
(foo (|) bar)

;; After <C-k>:
(foo | bar)
```

## Configuration

```lua
require('lispy-kill').setup({
  -- Keybinding (set to false to disable automatic binding)
  key = '<C-k>',
  
  -- Filetypes to enable for
  filetypes = {
    'lisp',
    'scheme', 
    'clojure',
    'fennel',
    'janet',
    'racket',
    'elisp',
    'commonlisp',
    'hy',
    'lfe',
    'query',
    'yuck',
  },
})
```

## API

```lua
local lispy = require('lispy-kill')

-- Main kill function
lispy.kill()

-- Default filetypes (can be referenced in config)
lispy.default_filetypes
```

## Related Projects

- [lispy](https://github.com/abo-abo/lispy) - The original Emacs package this is based on
- [nvim-paredit](https://github.com/julienvincent/nvim-paredit) - Structural editing for Neovim
- [vim-sexp](https://github.com/guns/vim-sexp) - Precision editing for S-expressions

## License

MIT
