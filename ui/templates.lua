-- Template files (TOM.Templates): SAVE TEMPLATE and LOAD TEMPLATE in the
-- create wizard. Templates are JSON files in Balatro's save folder
-- (%AppData%/Balatro/mp_tournament_templates), so they can be shared by
-- copying the file; OPEN FOLDER shows them. The format is lib/template.lua.

local T = TOM.Template
local UI = TOM.UI

local TP = {}
TOM.Templates = TP

TP.FOLDER = "mp_tournament_templates"
local PER_PAGE = 7

local state = nil -- the open overlay: { kind = "save" | "load", ... , el }

local function TUI()
	return PVP.TUI
end

local function json()
	local ok, lib = pcall(require, "json")
	return ok and lib or nil
end

local function path_of(file)
	return TP.FOLDER .. "/" .. file
end

-- The saved templates, by name: { { file, name } }.
function TP.list()
	local out = {}
	if not love.filesystem.getInfo(TP.FOLDER) then
		return out
	end
	local lib = json()
	for _, file in ipairs(love.filesystem.getDirectoryItems(TP.FOLDER)) do
		if file:match("%.json$") then
			local name = file:gsub("%.json$", "")
			local text = love.filesystem.read(path_of(file))
			local ok, data = pcall(function()
				return lib and text and lib.decode(text)
			end)
			if ok and type(data) == "table" and type(data.name) == "string" and data.name ~= "" then
				name = data.name
			end
			out[#out + 1] = { file = file, name = name }
		end
	end
	table.sort(out, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return out
end

-- Saves a form as a template; returns nil or why not.
function TP.save(form, name)
	local lib = json()
	if not lib then
		return "Couldn't save: no JSON library."
	end
	love.filesystem.createDirectory(TP.FOLDER)
	local ok, text = pcall(lib.encode, T.from_form(form, name))
	if not ok then
		return "Couldn't save: " .. tostring(text)
	end
	local written, err = love.filesystem.write(path_of(T.file_name(name)), text)
	if not written then
		return "Couldn't save: " .. tostring(err)
	end
	return nil
end

-- Loads a template file into a fresh form: form, skipped (or nil, why).
function TP.load(file, now_ms)
	local lib = json()
	local text = love.filesystem.read(path_of(file))
	if not lib or not text then
		return nil, "Couldn't read " .. file .. "."
	end
	local ok, data = pcall(lib.decode, text)
	if not ok then
		return nil, file .. " isn't valid JSON."
	end
	return T.to_form(data, now_ms)
end

local function open_folder()
	love.filesystem.createDirectory(TP.FOLDER)
	love.system.openURL("file:///" .. (love.filesystem.getSaveDirectory() .. "/" .. TP.FOLDER):gsub("\\", "/"))
end

-- Overlays ----------------------------------------------------------------

local function refresh()
	if state and state.el then
		state.el:update()
	end
end

local function show(contents)
	state.el = MPAPI.ui_element(function()
		return { nodes = { { n = G.UIT.C, config = { align = "cm" }, nodes = contents() } } }
	end)
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			no_back = true,
			contents = { { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { state.el.node } } },
		}),
	})
end

local function message_row()
	if not state.message then
		return nil
	end
	return { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = { TUI().text(state.message, TUI().TEXT, state.message_colour or G.C.UI.TEXT_INACTIVE) } }
end

local function save_contents()
	UI.target = { form = state, lists = {}, on_change = refresh }
	local exists = love.filesystem.getInfo(path_of(T.file_name(state.name))) ~= nil
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { TUI().text("SAVE TEMPLATE", 0.45, G.C.PURPLE) } },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = { TUI().text("Every setting but the date: start your next one from it.", TUI().SMALL, G.C.UI.TEXT_INACTIVE) } },
		UI.input("Template name", "tom_template_name", "name", { prompt = "e.g. Friday Weekly", max_length = 40, w = 5.4 }),
	}
	local m = message_row()
	if m then
		rows[#rows + 1] = m
	elseif exists then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = { TUI().text("A template with this name exists: saving replaces it.", TUI().SMALL, G.C.ORANGE) } }
	end
	rows[#rows + 1] = TUI().hbox({
		TUI().button("CANCEL", "tom_template_close", nil, G.C.ORANGE, 1.8),
		TUI().button("OPEN FOLDER", "tom_template_folder", nil, G.C.UI.BACKGROUND_INACTIVE, 2.4),
		TUI().spacer(0.6),
		TUI().button(state.confirm and "SURE? REPLACE" or "SAVE", "tom_template_save", nil, G.C.GREEN, 2.6),
	}, "cm", 0.06)
	return rows
end

local function load_contents()
	local templates = TP.list()
	local pages = math.max(1, math.ceil(#templates / PER_PAGE))
	state.page = math.max(1, math.min(state.page or 1, pages))
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { TUI().text("LOAD TEMPLATE", 0.45, G.C.PURPLE) } },
	}
	if #templates == 0 then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { TUI().text("No templates yet: save one from the wizard.", TUI().TEXT, G.C.UI.TEXT_INACTIVE) } }
	end
	for i = (state.page - 1) * PER_PAGE + 1, math.min(#templates, state.page * PER_PAGE) do
		local t = templates[i]
		local sure = state.confirm == t.file
		rows[#rows + 1] = {
			n = G.UIT.R,
			config = { align = "cm", padding = 0.03 },
			nodes = {
				{ n = G.UIT.C, config = { align = "cl", minw = 6.0 }, nodes = { TUI().text(t.name, TUI().TEXT) } },
				{ n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { TUI().button("LOAD", "tom_template_load", { file = t.file }, G.C.GREEN, 1.4, 0.3) } },
				{ n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { TUI().button(sure and "SURE?" or "DELETE", "tom_template_delete", { file = t.file }, G.C.RED, 1.4, 0.3) } },
			},
		}
	end
	if pages > 1 then
		rows[#rows + 1] = TUI().hbox({
			TUI().button("<", "tom_template_page", { delta = -1 }, G.C.RED, 0.7, 0.36),
			TUI().text(state.page .. " / " .. pages, TUI().TEXT),
			TUI().button(">", "tom_template_page", { delta = 1 }, G.C.RED, 0.7, 0.36),
		}, "cm", 0.06)
	end
	local m = message_row()
	if m then
		rows[#rows + 1] = m
	end
	rows[#rows + 1] = TUI().hbox({
		TUI().button("CANCEL", "tom_template_close", nil, G.C.ORANGE, 1.8),
		TUI().button("OPEN FOLDER", "tom_template_folder", nil, G.C.UI.BACKGROUND_INACTIVE, 2.4),
	}, "cm", 0.06)
	return rows
end

-- SAVE TEMPLATE for `form`; after() when it closes.
function TP.open_save(form, after)
	state = { kind = "save", form = form, name = form.name or "", after = after }
	show(save_contents)
end

-- LOAD TEMPLATE; on_load(form, name, skipped) with the loaded form.
function TP.open_load(on_load, after)
	state = { kind = "load", on_load = on_load, after = after, page = 1 }
	show(load_contents)
end

-- Closes the overlay; after(text) gets what to tell the wizard (or nil).
local function close(text)
	local after = state and state.after
	state = nil
	G.FUNCS.exit_overlay_menu()
	if after then
		after(type(text) == "string" and text or nil)
	end
end

G.FUNCS.tom_template_close = function()
	close()
end

G.FUNCS.tom_template_folder = function()
	pcall(open_folder)
end

G.FUNCS.tom_template_save = function()
	if not state or state.kind ~= "save" then
		return
	end
	local name = (state.name or ""):match("^%s*(.-)%s*$")
	if name == "" then
		state.message, state.message_colour = "Give the template a name.", G.C.RED
		refresh()
		return
	end
	local exists = love.filesystem.getInfo(path_of(T.file_name(name))) ~= nil
	if exists and not state.confirm then
		state.confirm = true
		refresh()
		return
	end
	local err = TP.save(state.form, name)
	if err then
		state.message, state.message_colour, state.confirm = err, G.C.RED, nil
		refresh()
		return
	end
	close("Saved the template " .. T.file_name(name) .. ".")
end

G.FUNCS.tom_template_load = function(e)
	local file = e.config.ref_table and e.config.ref_table.file
	if not state or not file then
		return
	end
	local form, skipped = TP.load(file, PVP.TournamentTime.now_ms())
	if not form then
		state.message, state.message_colour = skipped, G.C.RED
		refresh()
		return
	end
	local on_load = state.on_load
	state.after = nil
	close()
	if on_load then
		on_load(form, file:gsub("%.json$", ""), skipped)
	end
end

G.FUNCS.tom_template_delete = function(e)
	local file = e.config.ref_table and e.config.ref_table.file
	if not state or not file then
		return
	end
	if state.confirm ~= file then
		state.confirm = file
		refresh()
		return
	end
	love.filesystem.remove(path_of(file))
	state.confirm = nil
	state.message, state.message_colour = "Deleted " .. file .. ".", G.C.UI.TEXT_INACTIVE
	refresh()
end

G.FUNCS.tom_template_page = function(e)
	local delta = e.config.ref_table and e.config.ref_table.delta
	if state and delta then
		state.page = (state.page or 1) + delta
		state.confirm = nil
		refresh()
	end
end
