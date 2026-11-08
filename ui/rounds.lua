-- The wizard's ROUNDS step (TOM.RoundsStep): round-by-round settings.
--   preview   "with N players": which rounds are played and which of them
--             are the semifinals, final...
--   rounds    Round 1, Round 2... (as many as the player limit allows): what
--             each plays, with EDIT
--   named     the format's named rounds (Final, Semifinals...; Grand final,
--             Winners final, Losers final): they win over the round number
-- EDIT opens an overlay where every field starts as "Same as defaults".
-- The rules are in lib/form.lua (round_plan, effective, overrides).

local F = TOM.Form
local UI = TOM.UI

local RS = {}
TOM.RoundsStep = RS

local ROW_W = 11.2
local ctx = nil -- { form, lists, rebuild } from the wizard
local list = nil -- the scroll list (one per wizard visit)
local editing = nil -- { key, title } while the editor is open

local function TUI()
	return PVP.TUI
end

-- Player counts to preview with: a few up to the limit, and the limit.
local function preview_choices(max)
	local out = {}
	for _, n in ipairs({ 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128 }) do
		if n < max then
			out[#out + 1] = { n, TOM.T("k_tom_n_players", n) }
		end
	end
	out[#out + 1] = { max, TOM.T("k_tom_n_players", max) }
	return out
end

local function preview_players(form)
	if not form.previewPlayers or form.previewPlayers > form.maxPlayers then
		form.previewPlayers = form.maxPlayers
	end
	return form.previewPlayers
end

local function names_text(format, names)
	local out = {}
	for _, key in ipairs(names) do
		out[#out + 1] = F.named_label(format, key)
	end
	return table.concat(out, ", ")
end

-- The rows of the list: numbered rounds, then the named ones.
local function items()
	if not ctx then
		return {}
	end
	local form = ctx.form
	local plan = F.round_plan(form, preview_players(form))
	local most = #F.round_plan(form, form.maxPlayers)
	local out = {}
	for n = 1, most do
		local p = plan[n]
		out[#out + 1] = { key = "R" .. n, title = TOM.T("k_tom_round_n", n), plan = p or { n = n, names = {} }, played = p ~= nil }
	end
	local named = F.NAMED[form.format]
	if named then
		out[#out + 1] = { heading = TOM.T("k_tom_named_rounds") }
		for _, entry in ipairs(named) do
			-- Shown with its own settings only (on top of the defaults).
			out[#out + 1] = { key = entry[1], title = TOM.Form.text(entry[2]), named = true }
		end
	end
	return out
end

local function row(item)
	local form = ctx.form
	if item.heading then
		return { n = G.UIT.R, config = { align = "cl", minw = ROW_W, minh = 0.4 }, nodes = { TUI().text(item.heading, TUI().SMALL, G.C.GOLD) } }
	end
	local own = form.rounds[item.key]
	local summary, tag
	if item.named then
		-- The defaults plus this named round only (there is no round 0).
		summary = F.describe(F.effective(form, { n = 0, names = { item.key } }), form, ctx.lists)
	else
		summary = F.describe(F.effective(form, item.plan), form, ctx.lists)
		if not item.played then
			tag = TOM.T("k_tom_not_played_with", form.previewPlayers)
		elseif #item.plan.names > 0 then
			tag = "= " .. names_text(form.format, item.plan.names)
		end
	end
	local changed = F.round_override(own) ~= nil
	local title_nodes = { TUI().text(item.title, TUI().TEXT, changed and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) }
	if tag then
		title_nodes[#title_nodes + 1] = TUI().spacer(0.1)
		title_nodes[#title_nodes + 1] = TUI().text(tag, TUI().SMALL, item.played == false and G.C.UI.TEXT_INACTIVE or G.C.GOLD)
	end
	return {
		n = G.UIT.R,
		config = { align = "cm", minh = 0.5, r = 0.08, colour = changed and mix_colours(G.C.BLUE, G.C.BLACK, 0.25) or nil },
		nodes = {
			{ n = G.UIT.C, config = { align = "cl", minw = 4.2, padding = 0.04 }, nodes = { { n = G.UIT.R, config = { align = "cl" }, nodes = title_nodes } } },
			{ n = G.UIT.C, config = { align = "cl", minw = 5.2 }, nodes = { TUI().text(summary, TUI().SMALL, item.played == false and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT) } },
			{ n = G.UIT.C, config = { align = "cr", minw = 1.6 }, nodes = { TUI().button(TOM.T("k_tom_edit"), "tom_round_edit", { key = item.key, title = item.title }, G.C.BLUE, 1.2, 0.28) } },
		},
	}
end

-- The step's rows; ctx: { form, lists, rebuild }.
function RS.rows(context)
	ctx = context
	local form = ctx.form
	if not list then
		list = TUI().scroll_list({ items = items, build_row = row, visible = 6, row_h = 0.52, width = ROW_W, empty = TOM.T("k_tom_no_rounds_to_set") })
	end
	local rows = {}
	ctx.lists.previewPlayers = preview_choices(form.maxPlayers)
	preview_players(form)
	rows[#rows + 1] = UI.choice(TOM.T("k_tom_preview_with"), "previewPlayers", "previewPlayers", UI.lines("k_tom_help_which_rounds_are_played_and_which"), { TUI().button(TOM.T("k_tom_bracket"), "tom_round_bracket", nil, G.C.BLUE, 1.8, 0.3) })
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = { list.el.node } }
	return rows
end

function RS.dispose()
	if list then
		list:dispose()
		list = nil
	end
	editing = nil
end

-- The bracket preview ------------------------------------------------------

-- Asks the server for the bracket these settings make with the preview's
-- player count, played up to round `step` with made-up results.
local function fetch_preview(step, done)
	local form = ctx.form
	local body = { settings = F.payload(form, UI.decks()), players = preview_players(form), step = step }
	PVP.Tournaments.call("tournament_preview", body, function(err, data)
		if err or not data or not data.tournament then
			if ctx and ctx.say then
				ctx.say(TOM.T("k_tom_preview_failed", UI.error_text(err or TOM.T("k_tom_no_answer"))))
			end
			return
		end
		done(data)
	end)
end

G.FUNCS.tom_round_bracket = function()
	if not ctx then
		return
	end
	local players = preview_players(ctx.form)
	fetch_preview(0, function(data)
		local spec
		spec = {
			view = data.tournament,
			step = data.step,
			steps = data.steps,
			title = TOM.T("k_tom_preview_title", players),
			on_step = function(delta)
				local want = math.max(0, math.min(spec.steps, spec.step + delta))
				if want == spec.step then
					return
				end
				fetch_preview(want, function(next_data)
					PVP.update_tournament_bracket_preview(next_data.tournament, next_data.step, next_data.steps)
				end)
			end,
		}
		PVP.open_tournament_bracket_preview(spec)
	end)
end

-- The editor ---------------------------------------------------------------

local SAME = { false, "k_tom_opt_same_as_defaults" }

local function with_same(entries)
	local out = { SAME }
	for _, e in ipairs(entries or {}) do
		out[#out + 1] = e
	end
	return out
end

local function editor_lists()
	return {
		ruleset = with_same(ctx.lists.ruleset),
		bestOf = with_same(F.CHOICES.bestOf),
		deckKind = { SAME, { "locked", "k_tom_opt_one_deck_for_everyone" }, { "draft", "k_tom_opt_ban_and_pick_from_a_pool" } },
		deck = ctx.lists.deck,
		stake = ctx.lists.stake,
		banOrder = F.CHOICES.banOrder,
	}
end

local editor_el = nil -- the editor's contents, updated in place
local refresh_editor
local open_editor

-- Fills in what a deck choice needs when it is first picked.
local function complete(round)
	local form = ctx.form
	if round.deckKind == "locked" then
		round.deck = round.deck or form.deck or "b_red"
		round.stake = round.stake or form.stake or 1
	elseif round.deckKind == "draft" then
		-- A round's pool starts as a copy of the defaults' pool.
		if not round.draftStakes then
			F.copy_pool(form, round)
		end
		round.banOrder = round.banOrder or form.banOrder or "lower_seed_first"
	end
end

-- A deep copy (a round's pool holds Cocktails, which hold deck lists).
local function copy_round(from)
	if type(from) ~= "table" then
		return from
	end
	local out = {}
	for k, v in pairs(from) do
		out[k] = copy_round(v)
	end
	return out
end

local function editor_contents()
	local form = ctx.form
	local key = editing.key
	form.rounds[key] = form.rounds[key] or {}
	local round = form.rounds[key]
	UI.target = {
		form = round,
		lists = editor_lists(),
		on_change = function()
			complete(round)
			refresh_editor()
		end,
	}
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { TUI().text(string.upper(editing.title), 0.45, G.C.PURPLE) } },
		UI.choice(TOM.T("k_tom_ruleset"), "ruleset", "ruleset"),
		UI.choice(TOM.T("k_tom_series"), "bestOf", "bestOf"),
		UI.choice(TOM.T("k_tom_decks_stakes"), "deckKind", "deckKind", UI.lines("k_tom_help_same_as_defaults_what_the_games_step")),
	}
	if round.deckKind == "locked" then
		rows[#rows + 1] = UI.choice(TOM.T("k_tom_deck"), "deck", "deck")
		rows[#rows + 1] = UI.choice(TOM.T("k_tom_stake"), "stake", "stake")
	elseif round.deckKind == "draft" then
		rows[#rows + 1] = TOM.Pools.row(round, function()
			open_editor()
		end)
		rows[#rows + 1] = UI.choice(TOM.T("k_tom_ban_order"), "banOrder", "banOrder")
	end
	if UI.has_cocktail() then
		for _, r in ipairs(UI.cocktail_rows(round, function()
			open_editor()
		end)) do
			rows[#rows + 1] = r
		end
		-- The mixer and the switch change UI.target: point it back here.
		UI.target = { form = round, lists = editor_lists(), on_change = function()
			complete(round)
			refresh_editor()
		end }
	end
	-- Copy another round's settings in one press.
	local copies = {}
	for _, k in ipairs(F.round_keys(form)) do
		if k ~= key and F.round_override(form.rounds[k]) then
			local label = k:match("^R(%d+)$") and ("ROUND " .. k:sub(2)) or string.upper(F.named_label(form.format, k))
			copies[#copies + 1] = { n = G.UIT.C, config = { align = "cm", padding = 0.03 }, nodes = { TUI().button(label, "tom_round_copy", { from = k }, G.C.UI.BACKGROUND_INACTIVE, 1.6, 0.26) } }
		end
	end
	if #copies > 0 then
		local lines, line = {}, {}
		for _, c in ipairs(copies) do
			line[#line + 1] = c
			if #line == 5 then
				lines[#lines + 1] = { n = G.UIT.R, config = { align = "cl" }, nodes = line }
				line = {}
			end
		end
		if #line > 0 then
			lines[#lines + 1] = { n = G.UIT.R, config = { align = "cl" }, nodes = line }
		end
		rows[#rows + 1] = UI.row(TOM.T("k_tom_copy_from"), { { n = G.UIT.C, config = { align = "cl" }, nodes = lines } })
	end
	rows[#rows + 1] = TUI().hbox({
		TUI().button(TOM.T("k_tom_reset"), "tom_round_reset", nil, G.C.RED, 1.8),
		TUI().spacer(3.0),
		TUI().button(TOM.T("k_tom_done"), "tom_round_done", nil, G.C.GREEN, 2.2),
	}, "cm", 0.1)
	return rows
end

-- Rebuilds the editor's contents where they are (no new overlay).
refresh_editor = function()
	if editor_el then
		editor_el:update()
	end
end

open_editor = function()
	editor_el = MPAPI.ui_element(function()
		return { nodes = { { n = G.UIT.C, config = { align = "cl" }, nodes = editor_contents() } } }
	end)
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			no_back = true,
			contents = { { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { editor_el.node } } },
		}),
	})
end

G.FUNCS.tom_round_edit = function(e)
	local ref = e.config.ref_table
	if ref and ctx then
		editing = { key = ref.key, title = ref.title }
		open_editor()
	end
end

G.FUNCS.tom_round_copy = function(e)
	local from = e.config.ref_table and e.config.ref_table.from
	if from and editing and ctx then
		ctx.form.rounds[editing.key] = copy_round(ctx.form.rounds[from])
		refresh_editor()
	end
end

G.FUNCS.tom_round_reset = function()
	if editing and ctx then
		ctx.form.rounds[editing.key] = {}
		refresh_editor()
	end
end

G.FUNCS.tom_round_done = function()
	editing = nil
	editor_el = nil
	G.FUNCS.exit_overlay_menu()
	if ctx then
		ctx.rebuild()
	end
	if list then
		list:update()
	end
end
