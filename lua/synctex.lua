local has_dbus, dbus = pcall(require, "dbus_proxy")
local has_lgi, lgi = pcall(require, "lgi")

if not has_dbus or not has_lgi then
	vim.notify(
		"synctex.nvim requires dbus_proxy and lgi. Plugin not loaded.",
		vim.log.levels.WARN
	)
	return
end

local ctx = lgi.GLib.MainLoop():get_context()
local next = next

local M = { state = {} }
local uv = vim.uv or vim.loop
local timer = uv.new_timer()
local running = false

local function dbus_name(pdf_path)
	if vim.fn.filereadable(pdf_path) == 0 then
		return
	end
	local evince_daemon = dbus.Proxy:new({
		bus = dbus.Bus.SESSION,
		name = "org.gnome.evince.Daemon",
		interface = "org.gnome.evince.Daemon",
		path = "/org/gnome/evince/Daemon",
	})
	return evince_daemon:FindDocument(vim.uri_from_fname(pdf_path), true)
end

local function closed(tex_path)
	M.state[tex_path] = nil

	if next(M.state) == nil then
		timer:stop()
		running = false
	end
end

local function sync_source(_, p, l, _)
	vim.schedule(function()
		local tex_path = vim.uri_to_fname(p)
		if vim.api.nvim_buf_get_name(0) ~= tex_path then
			vim.cmd({ cmd = "edit", args = { tex_path } })
		end
		-- Wrap cursor positioning in pcall to avoid out-of-bounds errors
		pcall(vim.api.nvim_win_set_cursor, 0, { l[1], l[2] + 1 })
		vim.cmd("normal! zz")
	end)
end

local function get_window(tex_path)
	-- Support for multi-file projects (VimTeX integration)
	local pdf_path
	if vim.b.vimtex and vim.b.vimtex.tex then
		pdf_path = vim.b.vimtex.tex:gsub("%.tex$", ".pdf")
	else
		pdf_path = tex_path:gsub("%.tex$", ".pdf")
	end

	local name = dbus_name(pdf_path)
	if name == nil then
		return
	end

	if not running then
		timer:start(0, 250, function()
			ctx:iteration(false) -- Non-blocking
		end)
		running = true
	end

	local window = dbus.Proxy:new({
		bus = dbus.Bus.SESSION,
		name = name,
		interface = "org.gnome.evince.Window",
		path = "/org/gnome/evince/Window/0",
	})

	window:connect_signal(function(_)
		closed(tex_path)
	end, "Closed")

	window:connect_signal(sync_source, "SyncSource")
	return window
end

local function init()
	local tex_path = vim.api.nvim_buf_get_name(0)
	local window = get_window(tex_path)
	if window == nil then
		return
	end
	M.state[tex_path] = window
end

M.sync_view = function()
	local tex_path = vim.api.nvim_buf_get_name(0)
	if M.state[tex_path] == nil then
		init()
	end
	local window = M.state[tex_path]
	vim.schedule(function()
		local pos = vim.api.nvim_win_get_cursor(0)
		window:SyncViewAsync(function(_, _, _, _)
			-- Removed debug print(1)
		end, {}, tex_path, pos, os.time())
	end)
end

return M
