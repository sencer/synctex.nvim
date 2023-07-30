local dbus = require("dbus_proxy")
local ctx = require("lgi").GLib.MainLoop():get_context()
local next = next

local M = { state = {} }
local timer = vim.loop.new_timer()
local running = false

local function dbus_name(path)
	if not vim.fn.filereadable(path) then
		return
	end
	local evince_daemon = dbus.Proxy:new({
		bus = dbus.Bus.SESSION,
		name = "org.gnome.evince.Daemon",
		interface = "org.gnome.evince.Daemon",
		path = "/org/gnome/evince/Daemon",
	})
	return evince_daemon:FindDocument(vim.uri_from_fname(path), true)
end

local function closed(path)
	M.state[path] = nil

	if next(M.state) == nil then
		timer:stop()
		running = false
	end
end

local function sync_source(_, p, l, _)
	vim.schedule(function()
		local tex_path = vim.uri_to_fname(p)
		if vim.api.nvim_buf_get_name(0) ~= tex_path then
			vim.api.nvim_command(":e " .. tex_path)
		end
		vim.api.nvim_win_set_cursor(0, { l[1], l[2] + 1 })
		vim.api.nvim_command("normal! zz")
	end)
end

local function get_window(tex_path, pdf_path)
	if not running then
		timer:start(0, 250, function()
			ctx:iteration()
		end)
		running = true
	end

	local name = dbus_name(pdf_path)
	if name == nil then
		return
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
	local pdf_path = tex_path:gsub(".tex$", ".pdf")

	local window = get_window(tex_path, pdf_path)

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
			print(1)
		end, {}, tex_path, pos, os.time())
	end)
end


return M
