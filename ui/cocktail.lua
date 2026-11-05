-- The Cocktail mixer (TOM.Cocktail): which 1-3 decks PvP's Cocktail deck
-- plays at once, and an optional name. An overlay, updated in place:
--   name      a text box (optional)
--   decks     every deck PvP allows; up to three can be on
--   CLEAR     start over
-- TOM.Cocktail.open(recipe, on_done) edits `recipe` ({ name, decks }) in
-- place, then calls on_done.

local F = TOM.Form
local UI = TOM.UI

local CK = {}
TOM.Cocktail = CK

local PER_ROW = 5
local mixing = nil -- { recipe, on_done, el }

local function TUI()
	return PVP.TUI
end

local function short(name)
	return (tostring(name):gsub(" Deck$", ""))
end

-- "Abandoned + Erratic + Checkered", or nil for an empty mix.
function CK.summary(recipe)
	if not recipe or #(recipe.decks or {}) == 0 then
		return nil
	end
	local names = {}
	for _, key in ipairs(recipe.decks) do
		names[#names + 1] = short(UI.deck_name(key))
	end
	local name = (recipe.name or ""):match("^%s*(.-)%s*$")
	return (name ~= "" and (name .. ": ") or "") .. table.concat(names, " + ")
end

local function contents()
	local recipe = mixing.recipe
	local chosen = {}
	for _, key in ipairs(recipe.decks) do
		chosen[key] = true
	end
	local full = #recipe.decks >= F.COCKTAIL_MAX
	-- The name box writes into the recipe.
	UI.target = { form = recipe, lists = {}, on_change = CK.refresh }
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { TUI().text("MIX A COCKTAIL", 0.45, G.C.PURPLE) } },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = { TUI().text("The Cocktail deck plays up to " .. F.COCKTAIL_MAX .. " decks at once.", TUI().SMALL, G.C.UI.TEXT_INACTIVE) } },
		UI.input("Name", "tom_cocktail_name", "name", { prompt = "Optional name", max_length = 32, w = 5.0 }),
	}
	local line = {}
	local function flush()
		if #line > 0 then
			rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = line }
			line = {}
		end
	end
	for _, key in ipairs(UI.decks()) do
		local on = chosen[key]
		local can = on or not full
		line[#line + 1] = {
			n = G.UIT.C,
			config = { align = "cm", padding = 0.03 },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "cm", minw = 2.1, minh = 0.45, r = 0.08, colour = on and G.C.BLUE or (can and G.C.UI.BACKGROUND_INACTIVE or mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5)), hover = can, shadow = can, button = can and "tom_cocktail_toggle" or nil, ref_table = { key = key } },
					nodes = { TUI().text(short(UI.deck_name(key)), 0.28, on and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) },
				},
			},
		}
		if #line == PER_ROW then
			flush()
		end
	end
	flush()
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = { TUI().text(CK.summary(recipe) or "Nothing mixed yet.", TUI().TEXT, #recipe.decks > 0 and G.C.GOLD or G.C.UI.TEXT_INACTIVE) } }
	rows[#rows + 1] = TUI().hbox({
		TUI().button("CLEAR", "tom_cocktail_clear", nil, G.C.RED, 1.6),
		TUI().spacer(1.0),
		TUI().button("DONE", "tom_cocktail_done", nil, G.C.GREEN, 2.2),
	}, "cm", 0.06)
	return rows
end

function CK.refresh()
	if mixing and mixing.el then
		mixing.el:update()
	end
end

function CK.open(recipe, on_done)
	mixing = { recipe = recipe, on_done = on_done }
	mixing.el = MPAPI.ui_element(function()
		return { nodes = { { n = G.UIT.C, config = { align = "cm" }, nodes = contents() } } }
	end)
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			no_back = true,
			contents = { { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { mixing.el.node } } },
		}),
	})
end

G.FUNCS.tom_cocktail_toggle = function(e)
	local key = e.config.ref_table and e.config.ref_table.key
	if not mixing or not key then
		return
	end
	local decks = mixing.recipe.decks
	for i, k in ipairs(decks) do
		if k == key then
			table.remove(decks, i)
			CK.refresh()
			return
		end
	end
	if #decks < F.COCKTAIL_MAX then
		decks[#decks + 1] = key
	end
	CK.refresh()
end

G.FUNCS.tom_cocktail_clear = function()
	if mixing then
		mixing.recipe.name = ""
		mixing.recipe.decks = {}
		CK.refresh()
	end
end

G.FUNCS.tom_cocktail_done = function()
	local done = mixing and mixing.on_done
	mixing = nil
	G.FUNCS.exit_overlay_menu()
	if done then
		done()
	end
end
