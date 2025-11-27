# lispy-helpers.nvim

A Neovim implementation of `lispy-kill` and `lispy-comment` from the Emacs [lispy](https://github.com/abo-abo/lispy) package. These provide structure-aware editing commands that keep parentheses balanced—essential for comfortable Lisp editing.

## Features

- **Balanced killing**: Never leaves unmatched parentheses, brackets, or braces
- **Sexp-aware commenting**: Comment entire s-expressions with a single keystroke
- **Context-aware**: Behaves differently in strings, comments, and code
- **Treesitter support**: Uses treesitter when available for accurate parsing
- **Graceful fallback**: Works with vim syntax highlighting when treesitter isn't available
- **Kill ring integration**: Killed text is stored in the default register for yanking

## Installation

### lazy.nvim

```lua
{
  'sundbp/lispy-helpers.nvim',
  ft = { 'lisp', 'scheme', 'clojure', 'fennel', 'racket', 'janet', 'yuck' },
  opts = {
    kill_key = '<C-k>',  -- default keybinding
    comment_key = ';',  -- default keybinding
  },
}
```

Or with more explicit configuration:

```lua
{
  'sundbp/lispy-helpers.nvim',
  ft = { 'lisp', 'scheme', 'clojure', 'fennel', 'racket' },
  config = function()
    require('lispy-helpers').setup({
      kill_key = '<C-k>',
      filetypes = { 'lisp', 'scheme', 'clojure', 'fennel', 'racket', 'janet', 'yuck' },
    })
  end,
}
```

### packer.nvim

```lua
use {
  'sundbp/lispy-helpers.nvim',
  ft = { 'lisp', 'scheme', 'clojure', 'fennel', 'racket' },
  config = function()
    require('lispy-helpers').setup()
  end,
}
```

### Manual installation

1. Clone or copy to your Neovim packages directory:

   ```bash
   mkdir -p ~/.local/share/nvim/site/pack/plugins/start
   cd ~/.local/share/nvim/site/pack/plugins/start
   git clone https://github.com/sundbp/lispy-helpers.nvim
   ```

2. Add to your `init.lua`:

   ```lua
   require('lispy-helpers').setup()
   ```

## Usage

By default:

- `<C-k>` is bound for `lispy-kill` in normal and insert mode
- `;` is bound for `lispy-comment` in normal and visual mode

You can also call the functions directly:

```lua
-- In a keymap
vim.keymap.set('n', '<leader>k', require('lispy-helpers').kill)
vim.keymap.set('n', '<leader>;', require('lispy-helpers').comment)

-- Or use the commands
:LispyKill
:LispyComment
:3LispyComment  " Comment 3 sexps
```

## lispy-kill Behavior

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

## lispy-comment Behavior

The comment command (`;` by default) intelligently comments s-expressions:

| Condition | Action |
|-----------|--------|
| At opening delimiter `(`, `[`, `{` | Comment entire sexp (all lines it spans) |
| With count (e.g., `3;`) | Comment that many consecutive sexps |
| Inside a comment | Uncomment the current line |
| Visual selection | Comment/uncomment selected lines |
| Otherwise | Comment current line |

If the target lines are already commented, the command will uncomment them instead (toggle behavior).

### Comment a sexp

```lisp
;; Before (cursor on opening paren):
(defun foo ()
  |(bar)
  (baz))

;; After ;:
(defun foo ()
  ;; (bar)
  (baz))
```

### Comment multiple sexps

```lisp
;; Before (cursor on opening paren):
|(foo)
(bar)
(baz)

;; After 2;:
;; (foo)
;; (bar)
(baz)
```

### Uncomment

```lisp
;; Before (cursor inside comment):
;; |(foo)

;; After ;:
(foo)
```

## Configuration

```lua
require('lispy-helpers').setup({
  -- Keybinding for kill (set to false to disable automatic binding)
  kill_key = '<C-k>',
  
  -- Keybinding for comment (set to false to disable)
  comment_key = ';',
  
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
local lispy = require('lispy-helpers')

-- Kill function
lispy.kill()

-- Comment function (optionally pass count for multiple sexps)
lispy.comment()      -- comment 1 sexp
lispy.comment(3)     -- comment 3 sexps

-- Default filetypes (can be referenced in config)
lispy.default_filetypes
```

## Related Projects

- [lispy](https://github.com/abo-abo/lispy) - The original Emacs package this is based on
- [nvim-paredit](https://github.com/julienvincent/nvim-paredit) - Structural editing for Neovim
- [vim-sexp](https://github.com/guns/vim-sexp) - Precision editing for S-expressions

## License

MIT
