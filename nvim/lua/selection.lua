local M = {}
local state = {}

local function clear_selection(bufnr) state[bufnr or vim.api.nvim_get_current_buf()] = nil end

local function get_root_parser(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, nil, {})
	if ok and parser then
		parser:parse { vim.fn.line("w0") - 1, vim.fn.line("w$") }
		return parser
	end
end

local function get_selection(bufnr)
	local mode = vim.api.nvim_get_mode().mode
	if mode == "v" or mode == "V" or mode == "\22" then -- \22 is Ctrl-V
		return state[bufnr]
	end
	clear_selection(bufnr)
end

local function get_node_at_cursor(bufnr)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	local parser = get_root_parser(bufnr)
	if not parser then
		return
	end

	local function at(target_col)
		if target_col < 0 then
			return
		end
		local range = { row - 1, target_col, row - 1, target_col }
		local tree = parser:language_for_range(range)
		return tree and tree:named_node_for_range(range, { ignore_injections = false }) or nil
	end

	return at(col) or at(col - 1)
end

local function get_next_parent(node, bufnr)
	local current, root_searched = node, false
	while current do
		local parent = current:parent()
		if not parent then
			if root_searched then
				return
			end

			local parser = get_root_parser(bufnr)
			if not parser then
				return
			end

			local range = { current:range() }
			local tree = parser:language_for_range(range)
			if parser ~= tree then
				tree = tree and tree:parent() or nil
			else
				root_searched = true
			end

			parent = tree and tree:named_node_for_range(range) or nil
			if not parent then
				return
			end
		end

		if parent:named() and not vim.deep_equal({ current:range() }, { parent:range() }) then
			return parent
		end
		current = parent
	end
end

local function in_fallback_buffer(mapped_key)
	local buftype = vim.api.nvim_get_option_value("buftype", {})
	if buftype ~= "quickfix" and vim.fn.getcmdwintype() == "" then
		return false
	end

	local key = vim.api.nvim_replace_termcodes(mapped_key, true, false, true)
	vim.api.nvim_feedkeys(key, "n", false)
	return true
end

local function select_node(node)
	if not node then
		return
	end

	local start_row, start_col, end_row, end_col = node:range()
	local end_row_pos, end_col_pos = end_row + 1, end_col
	local last_line = vim.api.nvim_buf_line_count(0)

	if end_row_pos > last_line then
		end_row_pos = last_line
		local line = vim.api.nvim_buf_get_lines(0, last_line - 1, last_line, true)[1] or ""
		end_col_pos = #line
	end

	if vim.api.nvim_get_mode().mode ~= "v" then
		vim.api.nvim_cmd({ cmd = "normal", bang = true, args = { "v" } }, {})
	end

	vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
	vim.cmd("normal! o")
	vim.api.nvim_win_set_cursor(0, { end_row_pos, end_col_pos > 0 and end_col_pos - 1 or 0 })
end

function M.increment(mapped_key)
	if in_fallback_buffer(mapped_key) then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local selection = get_selection(bufnr)
	if selection and #selection > 0 then
		local node = get_next_parent(selection[#selection], bufnr)
		if not node then
			return
		end
		selection[#selection + 1] = node
		return select_node(node)
	end

	local node = get_node_at_cursor(bufnr)
	if not node then
		return
	end

	state[bufnr] = { node }
	select_node(node)
end

function M.decrement(mapped_key)
	if in_fallback_buffer(mapped_key) then
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local selection = get_selection(bufnr)
	if not selection or #selection <= 1 then
		return
	end

	selection[#selection] = nil
	select_node(selection[#selection])
end

function M.setup()
	vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = vim.api.nvim_create_augroup("user_treesitter_selection", { clear = true }),
		callback = function(args) clear_selection(args.buf) end,
	})
end

function M.attach(bufnr)
	vim.keymap.set({ "n", "x" }, "<CR>", function() M.increment("<CR>") end, { buffer = bufnr })
	vim.keymap.set({ "n", "x" }, "<S-CR>", function() M.decrement("<S-CR>") end, { buffer = bufnr })
end

return M
