-- lispy-helpers.nvim
-- Neovim implementation of lispy-kill and lispy-comment from the Emacs lispy package
-- Provides structure-aware editing commands for Lisp code

local M = {}

---@class LispyKillOpts
---@field key? string Keymap to bind (default: '<C-k>')
---@field filetypes? string[] Filetypes to enable for (default: lisp-like languages)

-- Default filetypes for lisp-like languages
M.default_filetypes = {
	"lisp",
	"scheme",
	"clojure",
	"fennel",
	"janet",
	"racket",
	"elisp",
	"commonlisp",
	"hy",
	"lfe",
	"query",
	"yuck",
}

-- Delimiter matching tables
local open_delims = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local close_delims = { [")"] = "(", ["]"] = "[", ["}"] = "{" }

---Get character at 0-indexed column in line
---@param line string
---@param col number 0-indexed
---@return string|nil
local function char_at(line, col)
	if col < 0 or col >= #line then
		return nil
	end
	return line:sub(col + 1, col + 1)
end

---Get cursor position
---@return number row (1-indexed)
---@return number col (0-indexed)
local function get_cursor()
	local pos = vim.api.nvim_win_get_cursor(0)
	return pos[1], pos[2]
end

---Check if we're in a string using syntax or treesitter
---@return boolean
local function in_string()
	-- Try treesitter first
	local ok, result = pcall(function()
		local node = vim.treesitter.get_node()
		while node do
			local type = node:type()
			if type:match("string") or type == "str_lit" then
				return true
			end
			node = node:parent()
		end
		return false
	end)

	if ok then
		return result
	end

	-- Fall back to syntax groups
	local syngroup = vim.fn.synIDattr(vim.fn.synID(vim.fn.line("."), vim.fn.col("."), 1), "name")
	return syngroup:lower():find("string") ~= nil
end

---Check if we're in a comment using syntax or treesitter
---@return boolean
local function in_comment()
	-- Try treesitter first
	local ok, result = pcall(function()
		local node = vim.treesitter.get_node()
		while node do
			local type = node:type()
			if type:match("comment") then
				return true
			end
			node = node:parent()
		end
		return false
	end)

	if ok then
		return result
	end

	-- Fall back to syntax groups
	local syngroup = vim.fn.synIDattr(vim.fn.synID(vim.fn.line("."), vim.fn.col("."), 1), "name")
	return syngroup:lower():find("comment") ~= nil
end

---Check if line contains only whitespace
---@return boolean
local function on_whitespace_line()
	return vim.api.nvim_get_current_line():match("^%s*$") ~= nil
end

---Check if we're positioned inside an empty list like ()
---@return boolean
local function in_empty_list()
	local line = vim.api.nvim_get_current_line()
	local _, col = get_cursor()

	local prev = char_at(line, col - 1)
	local curr = char_at(line, col)

	if prev and curr and open_delims[prev] == curr then
		return true
	end
	return false
end

---Check if parens are balanced from cursor to end of line
---Skips delimiters inside strings and comments
---@return boolean
local function parens_balanced_to_eol()
	local line = vim.api.nvim_get_current_line()
	local _, col = get_cursor()

	local balance = { ["("] = 0, ["["] = 0, ["{"] = 0 }
	local in_str = false
	local str_char = nil

	for i = col + 1, #line do
		local c = line:sub(i, i)
		local prev = i > 1 and line:sub(i - 1, i - 1) or ""

		-- Comment to end of line (skip rest)
		if not in_str and c == ";" then
			break
		end

		-- Handle string boundaries
		if (c == '"' or c == "'") and prev ~= "\\" then
			if not in_str then
				in_str = true
				str_char = c
			elseif c == str_char then
				in_str = false
				str_char = nil
			end
		elseif not in_str then
			-- Only count delimiters outside of strings
			if c == "(" then
				balance["("] = balance["("] + 1
			elseif c == ")" then
				balance["("] = balance["("] - 1
			elseif c == "[" then
				balance["["] = balance["["] + 1
			elseif c == "]" then
				balance["["] = balance["["] - 1
			elseif c == "{" then
				balance["{"] = balance["{"] + 1
			elseif c == "}" then
				balance["{"] = balance["{"] - 1
			end

			-- If any balance goes negative before we're done, unbalanced
			if balance["("] < 0 or balance["["] < 0 or balance["{"] < 0 then
				return false
			end
		end
	end

	return balance["("] == 0 and balance["["] == 0 and balance["{"] == 0
end

---Find end of string on current line
---@return number|nil column position of closing quote, or nil if extends past line
local function find_string_end()
	local line = vim.api.nvim_get_current_line()
	local _, col = get_cursor()

	-- Determine quote character by looking backward
	local quote_char = '"'
	for i = col - 1, 0, -1 do
		local c = char_at(line, i)
		if c == '"' or c == "'" then
			local prev = char_at(line, i - 1)
			if prev ~= "\\" then
				quote_char = c
				break
			end
		end
	end

	-- Find closing quote
	local i = col
	while i < #line do
		local c = char_at(line, i)
		if c == quote_char and char_at(line, i - 1) ~= "\\" then
			return i
		end
		i = i + 1
	end

	return nil
end

---Find the closing delimiter of the containing list
---Skips delimiters inside strings and comments
---@return number|nil row
---@return number|nil col (0-indexed position of closing delimiter)
local function find_list_end()
	local row, col = get_cursor()
	local total_lines = vim.api.nvim_buf_line_count(0)

	local depth = { ["("] = 0, ["["] = 0, ["{"] = 0 }
	local current_row = row
	local in_str = false
	local str_char = nil

	while current_row <= total_lines do
		local line = vim.api.nvim_buf_get_lines(0, current_row - 1, current_row, false)[1] or ""
		local start = (current_row == row) and col or 0

		for i = start, #line - 1 do
			local c = line:sub(i + 1, i + 1)
			local prev = i > 0 and line:sub(i, i) or ""

			-- Comment to end of line (skip rest of this line)
			if not in_str and c == ";" then
				break
			end

			-- Handle string boundaries
			if (c == '"' or c == "'") and prev ~= "\\" then
				if not in_str then
					in_str = true
					str_char = c
				elseif c == str_char then
					in_str = false
					str_char = nil
				end
			elseif not in_str then
				-- Only process delimiters outside of strings
				if open_delims[c] then
					depth[c] = depth[c] + 1
				elseif close_delims[c] then
					local open = close_delims[c]
					if depth[open] > 0 then
						depth[open] = depth[open] - 1
					else
						-- Unmatched close = end of containing list
						return current_row, i
					end
				end
			end
		end
		-- String doesn't continue across lines in most lisps (except with escapes)
		-- Reset string state at end of line for safety
		in_str = false
		str_char = nil
		current_row = current_row + 1
	end

	return nil, nil
end

---Find the end of sexp starting at cursor (using % motion)
---@return number|nil row
---@return number|nil col
local function find_sexp_end()
	local saved = vim.fn.getpos(".")

	local ok = pcall(vim.cmd, "normal! %")
	if ok then
		local new_pos = vim.fn.getpos(".")
		vim.fn.setpos(".", saved)

		if new_pos[2] ~= saved[2] or new_pos[3] ~= saved[3] then
			return new_pos[2], new_pos[3] - 1
		end
	end

	return nil, nil
end

---Store text in register and delete from buffer
---@param start_row number
---@param start_col number
---@param end_row number
---@param end_col number (inclusive)
local function kill_region(start_row, start_col, end_row, end_col)
	local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
	if #lines == 0 then
		return
	end

	-- Extract killed text
	local killed
	if #lines == 1 then
		killed = lines[1]:sub(start_col + 1, end_col + 1)
		local new_line = lines[1]:sub(1, start_col) .. lines[1]:sub(end_col + 2)
		vim.api.nvim_buf_set_lines(0, start_row - 1, start_row, false, { new_line })
	else
		local first = lines[1]:sub(start_col + 1)
		local last = lines[#lines]:sub(1, end_col + 1)
		lines[1] = first
		lines[#lines] = last
		killed = table.concat(lines, "\n")

		local before = vim.api.nvim_buf_get_lines(0, start_row - 1, start_row, false)[1]:sub(1, start_col)
		local after = vim.api.nvim_buf_get_lines(0, end_row - 1, end_row, false)[1]:sub(end_col + 2)
		vim.api.nvim_buf_set_lines(0, start_row - 1, end_row, false, { before .. after })
	end

	vim.fn.setreg('"', killed)
end

---Standard kill-line behavior
local function kill_line()
	local row, col = get_cursor()
	local line = vim.api.nvim_get_current_line()

	if col >= #line then
		-- At EOL, join with next line
		local next = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
		if next then
			vim.fn.setreg('"', "\n")
			vim.api.nvim_buf_set_lines(0, row - 1, row + 1, false, { line .. next })
		end
	else
		local killed = line:sub(col + 1)
		vim.fn.setreg('"', killed)
		vim.api.nvim_set_current_line(line:sub(1, col))
	end
end

---Kill entire whitespace line
local function kill_whole_line()
	local row = vim.fn.line(".")
	local killed = vim.api.nvim_get_current_line() .. "\n"
	vim.fn.setreg('"', killed)

	if vim.api.nvim_buf_line_count(0) > 1 then
		vim.api.nvim_buf_set_lines(0, row - 1, row, false, {})
		-- Re-indent current line
		pcall(vim.cmd, "normal! ==")
	else
		vim.api.nvim_set_current_line("")
	end
end

---Delete empty list like ()
local function delete_empty_list()
	local line = vim.api.nvim_get_current_line()
	local _, col = get_cursor()

	local killed = line:sub(col, col + 1)
	vim.fn.setreg('"', killed)

	local new_line = line:sub(1, col - 1) .. line:sub(col + 2)
	vim.api.nvim_set_current_line(new_line)
	vim.api.nvim_win_set_cursor(0, { vim.fn.line("."), col - 1 })
end

---Kill current sexp (when at opening delimiter)
local function kill_sexp()
	local line = vim.api.nvim_get_current_line()
	local row, col = get_cursor()
	local c = char_at(line, col)

	if open_delims[c] then
		local end_row, end_col = find_sexp_end()
		if end_row and end_col then
			kill_region(row, col, end_row, end_col)
			return
		end
	end

	-- Not at paren - kill word/symbol to next delimiter or whitespace
	local end_col = col
	while end_col < #line do
		local ch = char_at(line, end_col)
		if not ch or ch:match("%s") or close_delims[ch] or open_delims[ch] then
			break
		end
		end_col = end_col + 1
	end

	if end_col > col then
		kill_region(row, col, row, end_col - 1)
	end
end

---Main lispy-kill function implementing all conditions from the Emacs version
---
---Conditions (tried in order):
---1. Inside comment -> kill-line
---2. Inside string extending past line -> kill-line
---3. Inside string ending on this line -> delete up to closing quote
---4. On whitespace-only line -> delete whole line, re-indent
---5. Inside empty list () -> delete the empty list
---6. Balanced parens to EOL -> kill-line
---7. At an opening delimiter -> kill entire sexp
---8. Can find end of containing list -> delete from point to end of list
---9. Otherwise -> delete current sexp
function M.kill()
	local row, col = get_cursor()

	-- Condition 1: Inside comment -> kill-line
	if in_comment() then
		kill_line()
		return
	end

	-- Condition 2-3: Inside string
	if in_string() then
		local string_end = find_string_end()
		if string_end then
			-- String ends on this line: delete up to (but not including) closing quote
			if string_end > col then
				kill_region(row, col, row, string_end - 1)
			end
		else
			-- String extends past line: standard kill-line
			kill_line()
		end
		return
	end

	-- Condition 4: Line is only whitespace -> delete whole line and re-indent
	if on_whitespace_line() then
		kill_whole_line()
		return
	end

	-- Condition 5: Inside empty list -> delete the empty list
	if in_empty_list() then
		delete_empty_list()
		return
	end

	-- Condition 6: Balanced parens to EOL -> standard kill-line
	if parens_balanced_to_eol() then
		kill_line()
		return
	end

	-- Condition 6.5: At an opening delimiter -> kill the entire sexp
	-- This must come before condition 7, because find_list_end would find
	-- the containing list's end, not the sexp we're looking at
	local line = vim.api.nvim_get_current_line()
	local char_at_cursor = char_at(line, col)
	if open_delims[char_at_cursor] then
		kill_sexp()
		return
	end

	-- Condition 7: Can up-list -> delete from point to end of list
	local end_row, end_col = find_list_end()
	if end_row and end_col then
		if end_row > row or (end_row == row and end_col > col) then
			kill_region(row, col, end_row, end_col - 1)
			return
		end
	end

	-- Condition 8: Otherwise -> delete current sexp
	kill_sexp()
end

-- Alias for backwards compatibility
M.lispy_kill = M.kill

---Get the comment string for the current buffer
---@return string
local function get_comment_string()
	local cs = vim.filetype.get_option(vim.bo.filetype, "commentstring")
	if cs and cs ~= "" then
		-- commentstring is like ";; %s" or "# %s" or "// %s"
		-- Extract just the comment prefix
		local prefix = cs:match("^(.-)%%s")
		if prefix then
			return vim.trim(prefix)
		end
	end
	-- Default to Lisp-style comments
	return ";"
end

---Check if a line is commented (starts with comment after optional whitespace)
---@param line string
---@return boolean
---@return string|nil prefix The whitespace before the comment
---@return string|nil comment_prefix The comment characters
local function is_line_commented(line)
	local comment_str = get_comment_string()
	-- Escape special pattern characters in comment string
	local escaped = comment_str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
	local ws, cp = line:match("^(%s*)(" .. escaped .. "+)")
	if cp then
		return true, ws, cp
	end
	return false, nil, nil
end

---Comment a range of lines
---@param start_row number (1-indexed)
---@param end_row number (1-indexed)
local function comment_lines(start_row, end_row)
	local comment_str = get_comment_string()
	local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)

	-- Find minimum indentation across all non-empty lines
	local min_indent = math.huge
	for _, line in ipairs(lines) do
		if line:match("%S") then
			local indent = #(line:match("^%s*") or "")
			min_indent = math.min(min_indent, indent)
		end
	end
	if min_indent == math.huge then
		min_indent = 0
	end

	-- Add comment prefix after the minimum indentation
	local new_lines = {}
	for _, line in ipairs(lines) do
		if line:match("%S") then
			-- Insert comment after min_indent spaces
			local before = line:sub(1, min_indent)
			local after = line:sub(min_indent + 1)
			table.insert(new_lines, before .. comment_str .. " " .. after)
		else
			-- Empty or whitespace-only line, just add comment
			table.insert(new_lines, line .. comment_str)
		end
	end

	vim.api.nvim_buf_set_lines(0, start_row - 1, end_row, false, new_lines)
end

---Uncomment a range of lines
---@param start_row number (1-indexed)
---@param end_row number (1-indexed)
local function uncomment_lines(start_row, end_row)
	local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
	local new_lines = {}

	for _, line in ipairs(lines) do
		local is_commented, ws, cp = is_line_commented(line)
		if is_commented then
			-- Remove comment prefix and optional single space after it
			local rest = line:sub(#ws + #cp + 1)
			if rest:sub(1, 1) == " " then
				rest = rest:sub(2)
			end
			table.insert(new_lines, ws .. rest)
		else
			table.insert(new_lines, line)
		end
	end

	vim.api.nvim_buf_set_lines(0, start_row - 1, end_row, false, new_lines)
end

---Check if all lines in range are commented
---@param start_row number
---@param end_row number
---@return boolean
local function all_lines_commented(start_row, end_row)
	local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)
	for _, line in ipairs(lines) do
		if line:match("%S") then -- non-empty line
			local is_commented = is_line_commented(line)
			if not is_commented then
				return false
			end
		end
	end
	return true
end

---Lispy comment function
---Comment current expression or region. With count, comment that many expressions.
---If already commented, uncomment instead.
---@param count? number Number of sexps to comment (default 1)
function M.comment(count)
	count = count or 1

	-- Check if we're in visual mode or have a region
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "" then
		-- Visual mode: comment the selected region
		local start_row = vim.fn.line("'<")
		local end_row = vim.fn.line("'>")

		-- Exit visual mode
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)

		if all_lines_commented(start_row, end_row) then
			uncomment_lines(start_row, end_row)
		else
			comment_lines(start_row, end_row)
		end
		return
	end

	-- Check if we're inside a comment already
	if in_comment() then
		-- Uncomment current line
		local row = vim.fn.line(".")
		uncomment_lines(row, row)
		return
	end

	local row, col = get_cursor()
	local line = vim.api.nvim_get_current_line()
	local c = char_at(line, col)

	-- At opening delimiter: comment the sexp(s)
	if open_delims[c] then
		local start_row = row
		local end_row = row

		-- Find bounds of count sexps
		local saved_pos = vim.fn.getpos(".")
		for _ = 1, count do
			local sexp_end_row, _ = find_sexp_end()
			if sexp_end_row then
				end_row = math.max(end_row, sexp_end_row)
				-- Move to end and try to find next sexp
				vim.cmd("normal! %")
				local next_line = vim.api.nvim_get_current_line()
				local _, next_col = get_cursor()
				-- Skip whitespace to find next sexp
				while next_col < #next_line do
					local nc = char_at(next_line, next_col)
					if nc and not nc:match("%s") then
						if open_delims[nc] then
							break
						else
							-- Not at a sexp, stop
							break
						end
					end
					next_col = next_col + 1
				end
				if next_col < #next_line and open_delims[char_at(next_line, next_col)] then
					vim.api.nvim_win_set_cursor(0, { vim.fn.line("."), next_col })
				else
					break
				end
			else
				break
			end
		end
		vim.fn.setpos(".", saved_pos)

		if all_lines_commented(start_row, end_row) then
			uncomment_lines(start_row, end_row)
		else
			comment_lines(start_row, end_row)
		end
		return
	end

	-- Not at a sexp - just comment current line
	if all_lines_commented(row, row) then
		uncomment_lines(row, row)
	else
		comment_lines(row, row)
	end
end

-- Alias for backwards compatibility
M.lispy_comment = M.comment

---@class LispyOpts
---@field kill_key? string Keymap for kill (default: '<C-k>')
---@field comment_key? string Keymap for comment (default: ';')
---@field filetypes? string[] Filetypes to enable for (default: lisp-like languages)

---Setup function for lazy.nvim and other plugin managers
---@param opts? LispyOpts
function M.setup(opts)
	opts = opts or {}
	local kill_key = opts.kill_key or "<C-k>"
	local comment_key = opts.comment_key or ";"
	local filetypes = opts.filetypes or M.default_filetypes

	-- Create autocommand to set up keybindings for lisp filetypes
	vim.api.nvim_create_autocmd("FileType", {
		pattern = filetypes,
		callback = function(args)
			local buf = args.buf

			-- Kill binding
			vim.keymap.set({ "n", "i" }, kill_key, function()
				M.kill()
			end, { buffer = buf, desc = "Lispy kill (balanced)" })

			-- Comment binding (normal mode only, since ; is useful in insert mode)
			vim.keymap.set("n", comment_key, function()
				M.comment(vim.v.count1)
			end, { buffer = buf, desc = "Lispy comment sexp" })

			-- Visual mode comment
			vim.keymap.set("v", comment_key, function()
				M.comment()
			end, { buffer = buf, desc = "Lispy comment region" })
		end,
		desc = "Setup lispy keybindings for lisp filetypes",
	})

	-- Create global commands
	vim.api.nvim_create_user_command("LispyKill", function()
		M.kill()
	end, { desc = "Execute lispy-kill at cursor" })

	vim.api.nvim_create_user_command("LispyComment", function(cmd_opts)
		M.comment(cmd_opts.count > 0 and cmd_opts.count or 1)
	end, { count = true, desc = "Comment sexp(s) at cursor" })
end

return M
