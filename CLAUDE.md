# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A Neovim plugin providing `lispy-kill` and `lispy-comment` from the Emacs [lispy](https://github.com/abo-abo/lispy) package. These are structure-aware editing commands that keep parentheses balanced for Lisp-family languages.

## Architecture

The entire plugin is a single Lua module at `lua/lispy-helpers/init.lua`. It exports:

- `M.kill()` — balanced kill command with 9 ordered conditions (comment → string → whitespace → empty list → balanced EOL → opening delimiter → containing list end → sexp fallback)
- `M.comment(count?)` — sexp-aware comment/uncomment toggle
- `M.setup(opts?)` — plugin initialization, registers FileType autocmds and user commands (`:LispyKill`, `:LispyComment`)

Context detection (string/comment) uses treesitter first with fallback to vim syntax groups. Delimiter balancing is done with manual scanning that skips string/comment regions.

## Development

There is no build step, test suite, or linter configured. To test changes, load the plugin in Neovim and exercise the keybindings on Lisp files.

The plugin uses tabs for indentation throughout.

## Key Conventions

- All positions use Neovim's convention: rows are 1-indexed, columns are 0-indexed
- `open_delims` / `close_delims` tables map between matching delimiter pairs
- Killed text is stored in the default register (`"`) for yanking
- Backward-compat aliases exist: `M.lispy_kill` and `M.lispy_comment`
- LuaCATS `---@class`/`---@field`/`---@param`/`---@return` annotations are used for type documentation
