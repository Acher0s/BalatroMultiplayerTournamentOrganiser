-- Ban-and-pick pools (TOM.Pools): the "Pool" row with DECK POOL and STAKE
-- POOL, and the two overlays they open (updated in place).
--   deck pool    every deck PvP plays, and Cocktails: each its own mix (MIX
--                opens the Cocktail mixer), up to 8
--   stake pool   every stake the game has
-- Both have presets: STANDARD (the base game's), EXPANDED RANKED (read from
-- PvP's Expanded ruleset, so it follows that ruleset's changes), ALL, NONE.
-- They edit a form or a round (poolDecks: nil = every deck, draftStakes,
-- poolCocktails); `after` runs when the overlay closes.

local F = TOM.Form
local UI = TOM.UI

local P = {}
TOM.Pools = P

local COCKTAILS_MAX = 8
local open = nil -- { kind = "decks" | "stakes", settings, after, el }

local function TUI()
	return PVP.TUI
end

local function short(name)
	return (tostring(name):gsub(" Deck$", ""):gsub(" Stake$", ""))
end

-- Presets -------------------------------------------------------------------

local EXPANDED = "ruleset_mp_expanded"
-- If the Expanded ruleset can't be read (PvP changed): what it was.
local EXPANDED_DECKS_FALLBACK = { "b_mp_orange", "b_mp_violet" }
local EXPANDED_STAKES_FALLBACK = { "stake_white", "stake_green", "stake_black", "stake_purple", "stake_gold", "stake_mp_spectralplus" }

local function ruleset_field(key)
	if not MPAPI.resolve_ruleset_field or not (MPAPI.Rulesets and MPAPI.Rulesets[EXPANDED]) then
		return nil
	end
	local ok, value = pcall(MPAPI.resolve_ruleset_field, EXPANDED, key)
	return ok and type(value) == "table" and value or nil
end

local function in_list(list)
	local set = {}
	for _, v in ipairs(list) do
		set[v] = true
	end
	return set
end

-- The base game's decks (no modded ones), from the decks PvP plays.
local function standard_decks()
	local out = {}
	for _, key in ipairs(UI.decks()) do
		local center = G.P_CENTERS[key]
		if center and not center.mod then
			out[#out + 1] = key
		end
	end
	return out
end

-- Expanded ranked's decks: the base game's plus the ruleset's allowed decks,
-- minus its banned ones (as PvP's own draft builds them, lib/draft.lua). The
-- Cocktail isn't a pool deck here: add it with ADD COCKTAIL.
local function expanded_decks()
	local allowed = ruleset_field("allowed_backs") or EXPANDED_DECKS_FALLBACK
	local banned = in_list(ruleset_field("banned_backs") or {})
	local extra = in_list(allowed)
	local out = {}
	for _, key in ipairs(UI.decks()) do
		local center = G.P_CENTERS[key]
		if center and (not center.mod or extra[key]) and not banned[key] then
			out[#out + 1] = key
		end
	end
	return out
end

-- The base game's stakes (White to Gold).
local function standard_stakes()
	local out = {}
	for i, center in ipairs(G.P_CENTER_POOLS.Stake or {}) do
		if not center.mod then
			out[#out + 1] = i
		end
	end
	return out
end

-- Expanded ranked's stakes: the ruleset's allowed stakes, as indices.
local function expanded_stakes()
	local allowed = in_list(ruleset_field("allowed_stakes") or EXPANDED_STAKES_FALLBACK)
	local out = {}
	for i, center in ipairs(G.P_CENTER_POOLS.Stake or {}) do
		if allowed[center.key] then
			out[#out + 1] = i
		end
	end
	return out
end

local function presets_row()
	return TUI().hbox({
		TUI().text(TOM.T("k_tom_presets"), TUI().SMALL, G.C.UI.TEXT_INACTIVE),
		TUI().button(TOM.T("k_tom_standard"), "tom_pool_preset", { name = "standard" }, G.C.UI.BACKGROUND_INACTIVE, 2.0, 0.3),
		TUI().button(TOM.T("k_tom_expanded_ranked"), "tom_pool_preset", { name = "expanded" }, G.C.UI.BACKGROUND_INACTIVE, 3.0, 0.3),
		TUI().button(TOM.T("k_tom_all"), "tom_pool_preset", { name = "all" }, G.C.UI.BACKGROUND_INACTIVE, 1.2, 0.3),
		TUI().button(TOM.T("k_tom_none"), "tom_pool_preset", { name = "none" }, G.C.UI.BACKGROUND_INACTIVE, 1.2, 0.3),
	}, "cm", 0.04)
end

local function toggle_button(label, on, fn, ref, w)
	return {
		n = G.UIT.C,
		config = { align = "cm", padding = 0.03 },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "cm", minw = w or 2.1, minh = 0.45, r = 0.08, colour = on and G.C.BLUE or G.C.UI.BACKGROUND_INACTIVE, hover = true, shadow = true, button = fn, ref_table = ref },
				nodes = { TUI().text(label, 0.28, on and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) },
			},
		},
	}
end

local function grid(nodes, per_row)
	local rows, line = {}, {}
	for _, node in ipairs(nodes) do
		line[#line + 1] = node
		if #line == per_row then
			rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = line }
			line = {}
		end
	end
	if #line > 0 then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = line }
	end
	return rows
end

local function set_of(list)
	local out = {}
	for _, v in ipairs(list or {}) do
		out[v] = true
	end
	return out
end

local function deck_contents()
	local s = open.settings
	local chosen = set_of(s.poolDecks)
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { TUI().text(TOM.T("k_tom_deck_pool"), 0.45, G.C.PURPLE) } },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = { TUI().text(TOM.T("k_tom_the_decks_players_ban_and_pick_from"), TUI().SMALL, G.C.UI.TEXT_INACTIVE) } },
	}
	local buttons = {}
	for _, key in ipairs(UI.decks()) do
		buttons[#buttons + 1] = toggle_button(short(UI.deck_name(key)), chosen[key], "tom_pool_deck", { key = key })
	end
	for _, r in ipairs(grid(buttons, 5)) do
		rows[#rows + 1] = r
	end
	rows[#rows + 1] = presets_row()
	-- Cocktails: items of the pool, each its own mix.
	if UI.has_cocktail() then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = { TUI().text(TOM.T("k_tom_cocktails_in_the_pool"), TUI().TEXT, G.C.GOLD) } }
		local cocktails = s.poolCocktails or {}
		for i, c in ipairs(cocktails) do
			local summary = TOM.Cocktail.summary(c)
			rows[#rows + 1] = {
				n = G.UIT.R,
				config = { align = "cm", padding = 0.02 },
				nodes = {
					{ n = G.UIT.C, config = { align = "cl", minw = 7.4 }, nodes = { TUI().text(i .. ".  " .. (summary or "Nothing mixed yet"), TUI().SMALL, summary and G.C.UI.TEXT_LIGHT or G.C.RED) } },
					{ n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { TUI().button(TOM.T("k_tom_mix"), "tom_pool_mix", { index = i }, G.C.PURPLE, 1.2, 0.28) } },
					{ n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { TUI().button(TOM.T("k_tom_remove"), "tom_pool_remove", { index = i }, G.C.RED, 1.5, 0.28) } },
				},
			}
		end
		if #cocktails == 0 then
			rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(TOM.T("k_tom_none_add_one_to_put_a_cocktail_in_th"), TUI().SMALL, G.C.UI.TEXT_INACTIVE) } }
		end
		if #cocktails < COCKTAILS_MAX then
			rows[#rows + 1] = TUI().hbox({ TUI().button(TOM.T("k_tom_add_cocktail"), "tom_pool_add", nil, G.C.PURPLE, 2.8, 0.3) }, "cm", 0.04)
		end
	end
	local problem = F.pool_problem({ poolDecks = s.poolDecks, poolCocktails = s.poolCocktails, draftStakes = { 1 } })
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = { TUI().text(problem or F.pool_text(s), TUI().TEXT, problem and G.C.RED or G.C.GOLD) } }
	rows[#rows + 1] = TUI().hbox({ TUI().button(TOM.T("k_tom_done"), "tom_pool_done", nil, G.C.GREEN, 2.2) }, "cm", 0.06)
	return rows
end

local function stake_contents()
	local s = open.settings
	local chosen = set_of(s.draftStakes)
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { TUI().text(TOM.T("k_tom_stake_pool"), 0.45, G.C.PURPLE) } },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = { TUI().text(TOM.T("k_tom_each_deck_in_the_pool_comes_with_one"), TUI().SMALL, G.C.UI.TEXT_INACTIVE) } },
	}
	local buttons = {}
	for _, entry in ipairs(UI.stakes()) do
		buttons[#buttons + 1] = toggle_button(TOM.Form.text(entry[2]), chosen[entry[1]], "tom_pool_stake", { index = entry[1] }, 1.8)
	end
	for _, r in ipairs(grid(buttons, 6)) do
		rows[#rows + 1] = r
	end
	rows[#rows + 1] = presets_row()
	local n = #(s.draftStakes or {})
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = { TUI().text(n == 0 and "Pick at least one stake." or (n .. " stake" .. (n == 1 and "" or "s")), TUI().TEXT, n == 0 and G.C.RED or G.C.GOLD) } }
	rows[#rows + 1] = TUI().hbox({ TUI().button(TOM.T("k_tom_done"), "tom_pool_done", nil, G.C.GREEN, 2.2) }, "cm", 0.06)
	return rows
end

local function refresh()
	if open and open.el then
		open.el:update()
	end
end

local function show(kind, settings, after)
	open = { kind = kind, settings = settings, after = after }
	open.el = MPAPI.ui_element(function()
		return { nodes = { { n = G.UIT.C, config = { align = "cm" }, nodes = kind == "decks" and deck_contents() or stake_contents() } } }
	end)
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			no_back = true,
			contents = { { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { open.el.node } } },
		}),
	})
end

function P.open_decks(settings, after)
	-- "Every deck" becomes the full list once it is edited.
	if not settings.poolDecks then
		settings.poolDecks = {}
		for i, key in ipairs(UI.decks()) do
			settings.poolDecks[i] = key
		end
	end
	settings.poolCocktails = settings.poolCocktails or {}
	show("decks", settings, after)
end

function P.open_stakes(settings, after)
	settings.draftStakes = settings.draftStakes or {}
	show("stakes", settings, after)
end

-- The "Pool" row: DECK POOL, STAKE POOL and what is in them.
function P.row(settings, after)
	P.row_settings, P.row_after = settings, after
	local problem = F.pool_problem(settings)
	return UI.row(TOM.T("k_tom_pool"), {
		TUI().button(TOM.T("k_tom_deck_pool"), "tom_pool_open_decks", nil, G.C.BLUE, 2.2, 0.3),
		TUI().button(TOM.T("k_tom_stake_pool"), "tom_pool_open_stakes", nil, G.C.BLUE, 2.2, 0.3),
		TUI().spacer(0.1),
		TUI().text(problem and TOM.T("k_tom_fix_the_pool") or F.pool_text(settings), TUI().SMALL, problem and G.C.RED or G.C.GOLD),
	}, UI.lines("k_tom_help_pool"))
end

G.FUNCS.tom_pool_open_decks = function()
	if P.row_settings then
		P.open_decks(P.row_settings, P.row_after)
	end
end

G.FUNCS.tom_pool_open_stakes = function()
	if P.row_settings then
		P.open_stakes(P.row_settings, P.row_after)
	end
end

local function toggle(list, value)
	for i, v in ipairs(list) do
		if v == value then
			table.remove(list, i)
			return
		end
	end
	list[#list + 1] = value
end

G.FUNCS.tom_pool_deck = function(e)
	local key = e.config.ref_table and e.config.ref_table.key
	if open and key then
		toggle(open.settings.poolDecks, key)
		refresh()
	end
end

G.FUNCS.tom_pool_stake = function(e)
	local index = e.config.ref_table and e.config.ref_table.index
	if open and index then
		toggle(open.settings.draftStakes, index)
		table.sort(open.settings.draftStakes)
		refresh()
	end
end

G.FUNCS.tom_pool_preset = function(e)
	local name = e.config.ref_table and e.config.ref_table.name
	if not open or not name then
		return
	end
	if open.kind == "decks" then
		local list = {}
		if name == "standard" then
			list = standard_decks()
		elseif name == "expanded" then
			list = expanded_decks()
		elseif name == "all" then
			for i, key in ipairs(UI.decks()) do
				list[i] = key
			end
		end
		open.settings.poolDecks = list
	else
		local list = {}
		if name == "standard" then
			list = standard_stakes()
		elseif name == "expanded" then
			list = expanded_stakes()
		elseif name == "all" then
			for i, entry in ipairs(UI.stakes()) do
				list[i] = entry[1]
			end
		end
		open.settings.draftStakes = list
	end
	refresh()
end

-- The mixer replaces this overlay; coming back reopens the deck pool.
local function mix(recipe)
	local settings, after = open.settings, open.after
	TOM.Cocktail.open(recipe, function()
		show("decks", settings, after)
	end)
end

G.FUNCS.tom_pool_add = function()
	if open and #open.settings.poolCocktails < COCKTAILS_MAX then
		local recipe = F.new_recipe()
		table.insert(open.settings.poolCocktails, recipe)
		mix(recipe)
	end
end

G.FUNCS.tom_pool_mix = function(e)
	local i = e.config.ref_table and e.config.ref_table.index
	local recipe = open and i and open.settings.poolCocktails[i]
	if recipe then
		mix(recipe)
	end
end

G.FUNCS.tom_pool_remove = function(e)
	local i = e.config.ref_table and e.config.ref_table.index
	if open and i then
		table.remove(open.settings.poolCocktails, i)
		refresh()
	end
end

G.FUNCS.tom_pool_done = function()
	local s, after = open and open.settings, open and open.after
	-- Every deck picked reads as "every deck" again.
	if s and s.poolDecks and #s.poolDecks == #UI.decks() then
		s.poolDecks = nil
	end
	open = nil
	G.FUNCS.exit_overlay_menu()
	if after then
		after()
	end
end
