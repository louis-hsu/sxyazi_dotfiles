local M = {}

local state = {}

local function clear_selection(bufnr) state[bufnr or vim.api.nvim_get_current_buf()] = nil end

local function get_selection(bufnr)
	local mode = vim.api.nvim_get_mode().mode
	if mode == "v" or mode == "V" or mode == "\22" then -- \22 is Ctrl-V (visual block mode)
		return state[bufnr]
	end

	clear_selection(bufnr)
end

local function get_named_node_at_cursor(bufnr)
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	row = row - 1

	local parser = vim.treesitter.get_parser(bufnr)
	local tree = parser:tree_for_range { row, col, row, col }
	if not tree then
		return nil
	end

	return tree:root():named_descendant_for_range(row, col, row, col)
end

local function is_same_range(left, right)
	local lsrow, lscol, lerow, lecol = left:range()
	local rsrow, rscol, rerow, recol = right:range()

	return lsrow == rsrow and lscol == rscol and lerow == rerow and lecol == recol
end

local function get_next_parent(node)
	local parent = node:parent()
	while parent do
		if parent:named() and not is_same_range(parent, node) then
			return parent
		end

		parent = parent:parent()
	end

	return nil
end

local function select_node(node)
	local bufnr = vim.api.nvim_get_current_buf()
	local start_row, start_col, end_row, end_col = node:range()

	if end_col == 0 and end_row > start_row then
		end_row = end_row - 1
		end_col = #vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, true)[1]
	else
		end_col = math.max(end_col - 1, start_col)
	end

	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
	vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
	vim.cmd.normal { bang = true, args = { "v" } }
	vim.api.nvim_win_set_cursor(0, { end_row + 1, end_col })
end

function M.increment()
	local bufnr = vim.api.nvim_get_current_buf()
	local selection = get_selection(bufnr)
	local node = selection and selection[#selection] or get_named_node_at_cursor(bufnr)

	if not node then
		return
	end

	if selection then
		node = get_next_parent(node)
		if not node then
			return
		end
		table.insert(selection, node)
	else
		selection = { node }
		state[bufnr] = selection
	end

	select_node(node)
end

function M.decrement()
	local bufnr = vim.api.nvim_get_current_buf()
	local selection = get_selection(bufnr)
	if not selection or #selection <= 1 then
		return
	end

	table.remove(selection)
	select_node(selection[#selection])
end

function M.setup()
	vim.api.nvim_create_autocmd("BufDelete", {
		group = vim.api.nvim_create_augroup("user_treesitter_selection", { clear = true }),
		callback = function(args) clear_selection(args.buf) end,
	})
end

function M.attach(bufnr)
	vim.keymap.set({ "n", "x" }, "<CR>", M.increment, { buffer = bufnr })
	vim.keymap.set({ "n", "x" }, "<S-CR>", M.decrement, { buffer = bufnr })
end

return M
