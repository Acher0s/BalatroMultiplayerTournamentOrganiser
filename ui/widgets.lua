-- Form rows for the organiser pages (TOM.UI), built on PvP's tournament UI
-- helpers (PVP.TUI): a label on the left and a control on the right.
--   choice    < value >   steps through TOM.Form.CHOICES[key] (or a list)
--   input     a text field
--   toggles   a row of on/off buttons (draft stakes)
-- Every change calls the page's on_change (it rebuilds its form).

TOM.UI = TOM.UI or {}
local UI = TOM.UI

UI.LABEL_W = 3.4
UI.VALUE_W = 6.4

-- The page whose form the controls change: { form, on_change, lists }.
UI.target = nil

local function TUI()
	return PVP.TUI
end

-- A help text key -> its lines (one per \n), for the tooltips.
function UI.lines(key)
	local out = {}
	for line in (TOM.T(key) .. "\n"):gmatch("([^\n]*)\n") do
		out[#out + 1] = line
	end
	return out
end

-- A small "?" that explains something when hovered (Balatro's own tooltip
-- popup). lines: short sentences, one per line.
function UI.help(lines, title)
	return {
		n = G.UIT.C,
		config = { align = "cm", minw = 0.34, minh = 0.34, r = 0.17, colour = G.C.UI.BACKGROUND_INACTIVE, tooltip = { title = title, text = lines } },
		nodes = { TUI().text("?", 0.26, G.C.UI.TEXT_LIGHT) },
	}
end

local function label_col(text, help)
	local nodes = { TUI().text(text, TUI().TEXT, G.C.UI.TEXT_INACTIVE) }
	if help then
		nodes[#nodes + 1] = TUI().spacer(0.1)
		nodes[#nodes + 1] = UI.help(help)
	end
	return { n = G.UIT.C, config = { align = "cl", minw = UI.LABEL_W }, nodes = { { n = G.UIT.R, config = { align = "cl" }, nodes = nodes } } }
end

-- One form row: label (with an optional "?" tooltip, help = lines) + control nodes.
function UI.row(label, controls, help)
	local nodes = { label_col(label, help) }
	for _, c in ipairs(controls) do
		nodes[#nodes + 1] = { n = G.UIT.C, config = { align = "cm", padding = 0.03 }, nodes = { c } }
	end
	return { n = G.UIT.R, config = { align = "cl", padding = 0.03 }, nodes = nodes }
end

local function arrow(text, key, dir, list_key)
	return {
		n = G.UIT.C,
		config = { align = "cm", minw = 0.5, minh = 0.45, r = 0.08, colour = G.C.RED, hover = true, shadow = true, button = "tom_step", ref_table = { key = key, dir = dir, list = list_key } },
		nodes = { TUI().text(text, 0.34) },
	}
end

-- < value > for form[key]. list_key: a list in UI.target.lists instead of
-- TOM.Form.CHOICES[key]. extra: more nodes after the control (a button).
function UI.choice(label, key, list_key, help, extra)
	local t = UI.target
	local list = list_key and t.lists[list_key] or nil
	local value = TOM.Form.label(t.form, key, list)
	local controls = {
		{
			n = G.UIT.R,
			config = { align = "cm" },
			nodes = {
				arrow("<", key, -1, list_key),
				{ n = G.UIT.C, config = { align = "cm", minw = UI.VALUE_W - 1.2, minh = 0.45 }, nodes = { TUI().text(value, TUI().TEXT) } },
				arrow(">", key, 1, list_key),
			},
		},
	}
	for _, node in ipairs(extra or {}) do
		controls[#controls + 1] = node
	end
	return UI.row(label, controls, help)
end

G.FUNCS.tom_step = function(e)
	local t, ref = UI.target, e.config.ref_table
	if not t or not ref then
		return
	end
	TOM.Form.step(t.form, ref.key, ref.dir, ref.list and t.lists[ref.list] or nil)
	t.on_change()
end

-- A text box. Balatro's own only takes letters and numbers (and turns 0 into
-- o), so these take what is typed (love.textinput: any keyboard layout),
-- Ctrl+V pastes. charset: "text" (printable ASCII, the game's font) or
-- "digits".
function UI.text_box(id, key, opts)
	opts = opts or {}
	return create_text_input({
		id = id,
		ref_table = UI.target.form,
		ref_value = key,
		prompt_text = opts.prompt or "",
		max_length = opts.max_length or 48,
		w = opts.w or UI.VALUE_W,
		h = 0.5,
		text_scale = opts.text_scale or 0.32,
		all_caps = false,
		tom_charset = opts.charset or "text",
	})
end

function UI.input(label, id, key, opts)
	opts = opts or {}
	return UI.row(label, { UI.text_box(id, key, opts) }, opts.help)
end

local function hooked_charset()
	local hook = G.CONTROLLER and G.CONTROLLER.text_input_hook
	local cfg = hook and hook.config and hook.config.ref_table
	return cfg and cfg.tom_charset, cfg
end

local function allowed(charset, c)
	local b = c:byte()
	if charset == "digits" then
		return b >= 48 and b <= 57
	end
	return b >= 32 and b <= 126
end

-- The same steps as the game's own insert (G.FUNCS.text_input_key).
local function insert(cfg, c)
	local text = cfg.text
	TRANSPOSE_TEXT_INPUT(0)
	if cfg.max_length > string.len(text.ref_table[text.ref_value]) then
		MODIFY_TEXT_INPUT({ letter = c, text_table = text, pos = text.current_position + 1 })
		TRANSPOSE_TEXT_INPUT(1)
	end
end

local function insert_all(charset, cfg, str)
	for i = 1, #str do
		local c = str:sub(i, i)
		if allowed(charset, c) then
			insert(cfg, c)
		end
	end
end

local original_key = G.FUNCS.text_input_key
G.FUNCS.text_input_key = function(args)
	local charset, cfg = hooked_charset()
	local key = args and args.key
	if charset and key then
		local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
		if ctrl then
			if key == "v" then
				insert_all(charset, cfg, (G.F_LOCAL_CLIPBOARD and G.CLIPBOARD or love.system.getClipboardText()) or "")
			end
			return
		end
		-- Characters come through love.textinput below.
		if #key == 1 or key == "space" then
			return
		end
	end
	return original_key(args)
end

local original_textinput = love.textinput
love.textinput = function(t)
	local charset, cfg = hooked_charset()
	if charset then
		insert_all(charset, cfg, t)
		return
	end
	if original_textinput then
		return original_textinput(t)
	end
end

-- On/off buttons for the values of a list held in form[key] (a set as a
-- list), per_row to a row.
function UI.toggles(label, key, list, per_row, help)
	local chosen = {}
	for _, v in ipairs(UI.target.form[key]) do
		chosen[v] = true
	end
	local nodes = {}
	for _, entry in ipairs(list) do
		local on = chosen[entry[1]]
		nodes[#nodes + 1] = {
			n = G.UIT.C,
			config = { align = "cm", padding = 0.02 },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "cm", minw = 0.95, minh = 0.42, r = 0.08, colour = on and G.C.BLUE or G.C.UI.BACKGROUND_INACTIVE, hover = true, shadow = true, button = "tom_toggle", ref_table = { key = key, value = entry[1] } },
					nodes = { TUI().text(TOM.Form.text(entry[2]), 0.26, on and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) },
				},
			},
		}
	end
	per_row = per_row or #nodes
	local rows = {}
	for i = 1, #nodes, per_row do
		local row = {}
		for j = i, math.min(#nodes, i + per_row - 1) do
			row[#row + 1] = nodes[j]
		end
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cl" }, nodes = row }
	end
	return UI.row(label, { { n = G.UIT.C, config = { align = "cl" }, nodes = rows } }, help)
end

G.FUNCS.tom_toggle = function(e)
	local t, ref = UI.target, e.config.ref_table
	if not t or not ref then
		return
	end
	local list, found = t.form[ref.key], nil
	for i, v in ipairs(list) do
		if v == ref.value then
			found = i
		end
	end
	if found then
		table.remove(list, found)
	else
		list[#list + 1] = ref.value
	end
	t.on_change()
end

-- A plain on/off for a boolean form field.
function UI.switch(label, key, help)
	local on = UI.target.form[key] and true or false
	return UI.row(label, {
		{
			n = G.UIT.C,
			config = { align = "cm", minw = 1.6, minh = 0.45, r = 0.08, colour = on and G.C.GOLD or G.C.UI.BACKGROUND_INACTIVE, hover = true, shadow = true, button = "tom_switch", ref_table = { key = key } },
			nodes = { TUI().text(TOM.T(on and "k_tom_yes" or "k_tom_no"), 0.3, on and G.C.BLACK or G.C.UI.TEXT_INACTIVE) },
		},
	}, help)
end

G.FUNCS.tom_switch = function(e)
	local t, ref = UI.target, e.config.ref_table
	if t and ref then
		t.form[ref.key] = not t.form[ref.key]
		t.on_change()
	end
end

-- A grey explanation line under a row.
function UI.note(text)
	return { n = G.UIT.R, config = { align = "cl", padding = 0.02 }, nodes = { { n = G.UIT.C, config = { minw = UI.LABEL_W } }, TUI().text(text, TUI().SMALL, G.C.UI.TEXT_INACTIVE) } }
end

-- Whether this player may create official tournaments (server privilege
-- tournament_official). The server checks again either way.
function UI.may_create_official()
	local p = MPAPI.get_privileges and MPAPI.get_privileges()
	if type(p) ~= "table" then
		return false
	end
	if p.tournament_official then
		return true
	end
	for _, v in ipairs(p) do
		if v == "tournament_official" then
			return true
		end
	end
	return false
end

-- Display names for keys the server stores.
function UI.deck_name(key)
	local ok, name = pcall(localize, { type = "name_text", set = "Back", key = key })
	return ok and type(name) == "string" and name ~= "ERROR" and name or tostring(key)
end

-- Every stake the game has, easiest first, as { index, short name }: the
-- base eight, then PvP's Planet, Spectral and Spectral+ (and any other mod's).
-- The index is what the server stores (the game's stake number).
function UI.stakes()
	local out = {}
	for i, center in ipairs(G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake or {}) do
		local ok, name = pcall(localize, { type = "name_text", set = "Stake", key = center.key })
		name = (ok and type(name) == "string" and name ~= "ERROR") and name or center.key
		out[#out + 1] = { i, (name:gsub(" Stake$", "")) }
	end
	if #out == 0 then
		return TOM.Form.CHOICES.stake
	end
	return out
end

-- Every deck PvP plays (the base game's, PvP's own and the mods it allows),
-- in collection order, without the Cocktail (PVP.get_cocktail_decks: the
-- decks a Cocktail can mix, which is the same list).
function UI.decks()
	local ok, decks = pcall(PVP.get_cocktail_decks, false)
	if ok and type(decks) == "table" and #decks > 0 then
		return decks
	end
	local out = {}
	for _, center in ipairs(G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back or {}) do
		if not center.mod and center.key ~= "b_challenge" then
			out[#out + 1] = center.key
		end
	end
	return out
end

-- Whether PvP's Cocktail deck is there.
function UI.has_cocktail()
	return G.P_CENTERS and G.P_CENTERS[TOM.Form.COCKTAIL] ~= nil
end

-- The Cocktail rows under a deck choice (GAMES step or a round): MIX opens
-- the mixer for settings.cocktail. after: what to do when it closes.
function UI.cocktail_rows(settings, after)
	local F = TOM.Form
	local rows = {}
	if not F.uses_cocktail(settings) then
		return rows
	end
	settings.cocktail = settings.cocktail or F.new_recipe()
	UI.cocktail_after = after
	UI.cocktail_settings = settings
	local summary = TOM.Cocktail.summary(settings.cocktail)
	rows[#rows + 1] = UI.row(TOM.T("k_tom_cocktail"), {
		TUI().button(TOM.T("k_tom_mix"), "tom_cocktail_open", nil, G.C.PURPLE, 1.4, 0.3),
		TUI().spacer(0.1),
		TUI().text(summary or TOM.T("k_tom_nothing_mixed"), TUI().SMALL, summary and G.C.GOLD or G.C.RED),
	}, UI.lines("k_tom_help_cocktail"))
	return rows
end

G.FUNCS.tom_cocktail_open = function()
	local settings, after = UI.cocktail_settings, UI.cocktail_after
	if settings then
		TOM.Cocktail.open(settings.cocktail, after)
	end
end

-- Short sentence for an RPC refusal.
function UI.error_text(err)
	if type(err) == "table" then
		err = err.message or err.error
	end
	return tostring(err or TOM.T("k_tom_went_wrong"))
end
