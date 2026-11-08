-- The create wizard's form: what can be chosen, the defaults, what is still
-- wrong, and the tournament_create payload. Pure (no game state), so
-- tests/form_test.lua runs it under plain Lua.

TOM = TOM or {}
local F = {}
TOM.Form = F

local MINUTE = 60 * 1000
local HOUR = 60 * MINUTE
local DAY = 24 * HOUR

-- Every choice is a list of { value, label }; the wizard steps through them.
F.CHOICES = {
	visibility = {
		{ "public", "k_tom_opt_public_listed_in_browse" },
		{ "private", "k_tom_opt_private_invite_code_only" },
	},
	maxPlayers = { { 4, "4" }, { 8, "8" }, { 12, "12" }, { 16, "16" }, { 24, "24" }, { 32, "32" }, { 48, "48" }, { 64, "64" }, { 96, "96" }, { 128, "128" } },
	checkInMinutes = { { false, "k_tom_opt_no_check_in" }, { 10, "k_tom_opt_10_min_before" }, { 15, "k_tom_opt_15_min_before" }, { 20, "k_tom_opt_20_min_before" }, { 30, "k_tom_opt_30_min_before" }, { 45, "k_tom_opt_45_min_before" }, { 60, "k_tom_opt_60_min_before" } },
	format = {
		{ "single_elim", "k_tom_opt_single_elimination" },
		{ "double_elim", "k_tom_opt_double_elimination" },
		{ "round_robin", "k_tom_opt_round_robin" },
		{ "swiss", "k_tom_opt_swiss" },
	},
	grandFinalReset = { { true, "k_tom_opt_yes_bracket_reset" }, { false, "k_tom_opt_no" } },
	groupSize = { { false, "k_tom_opt_one_group" }, { 3, "k_tom_opt_groups_of_3" }, { 4, "k_tom_opt_groups_of_4" }, { 5, "k_tom_opt_groups_of_5" }, { 6, "k_tom_opt_groups_of_6" }, { 8, "k_tom_opt_groups_of_8" } },
	swissRounds = { { false, "k_tom_opt_automatic" }, { 3, "3" }, { 4, "4" }, { 5, "5" }, { 6, "6" }, { 7, "7" }, { 8, "8" }, { 9, "9" } },
	seeding = {
		{ "rating", "k_tom_opt_by_ranked_rating" },
		{ "random", "k_tom_opt_random" },
		{ "manual", "k_tom_opt_i_set_the_order" },
	},
	bestOf = { { 1, "k_tom_opt_best_of_1" }, { 3, "k_tom_opt_best_of_3" }, { 5, "k_tom_opt_best_of_5" }, { 7, "k_tom_opt_best_of_7" } },
	deckKind = {
		{ "locked", "k_tom_opt_everyone_plays_one_deck" },
		{ "draft", "k_tom_opt_ban_and_pick_from_a_pool" },
	},
	-- The base game's stakes; in the game the wizard lists every stake it has
	-- (PvP adds Planet, Spectral and Spectral+ after Gold).
	stake = { { 1, "k_tom_opt_white" }, { 2, "k_tom_opt_red" }, { 3, "k_tom_opt_green" }, { 4, "k_tom_opt_black" }, { 5, "k_tom_opt_blue" }, { 6, "k_tom_opt_purple" }, { 7, "k_tom_opt_orange" }, { 8, "k_tom_opt_gold" } },
	banOrder = {
		{ "lower_seed_first", "k_tom_opt_lower_seed_bans_first" },
		{ "lower_seed_last", "k_tom_opt_higher_seed_bans_first" },
		{ "random", "k_tom_opt_random" },
		{ "previous_loser_first", "k_tom_opt_loser_of_the_last_game_first" },
	},
	preset = {
		{ "live_event", "k_tom_opt_live_play_as_soon_as_both_are_ready" },
		{ "live_fixed_rounds", "k_tom_opt_live_i_start_each_round" },
		{ "league", "k_tom_opt_league_play_by_a_deadline" },
	},
	readyUpMinutes = { { 5, "k_tom_opt_5_min" }, { 10, "k_tom_opt_10_min" }, { 15, "k_tom_opt_15_min" }, { 20, "k_tom_opt_20_min" }, { 30, "k_tom_opt_30_min" } },
	breakMinutes = { { 0, "k_tom_opt_no_breaks" }, { 5, "k_tom_opt_5_min" }, { 10, "k_tom_opt_10_min" }, { 15, "k_tom_opt_15_min" }, { 30, "k_tom_opt_30_min" }, { 60, "k_tom_opt_1_hour" } },
	windowMinutes = { { 1 * 24 * 60, "k_tom_opt_1_day" }, { 2 * 24 * 60, "k_tom_opt_2_days" }, { 3 * 24 * 60, "k_tom_opt_3_days" }, { 5 * 24 * 60, "k_tom_opt_5_days" }, { 7 * 24 * 60, "k_tom_opt_1_week" }, { 14 * 24 * 60, "k_tom_opt_2_weeks" } },
}

-- PvP's Cocktail deck: it plays 1-3 other decks at once (its recipe).
F.COCKTAIL = "b_mp_cocktail"
F.COCKTAIL_MAX = 3

local function new_recipe()
	return { name = "", decks = {} }
end
F.new_recipe = new_recipe

-- The recipe for the server, or nil when it mixes nothing.
function F.recipe_payload(recipe)
	if not recipe or #(recipe.decks or {}) == 0 then
		return nil
	end
	local out = { decks = {} }
	for i, d in ipairs(recipe.decks) do
		out.decks[i] = d
	end
	local name = (recipe.name or ""):match("^%s*(.-)%s*$")
	if name ~= "" then
		out.name = name
	end
	return out
end

-- Is this deck setting locked to the Cocktail (so it needs a mix)?
function F.uses_cocktail(settings)
	return settings.deckKind == "locked" and settings.deck == F.COCKTAIL
end

-- A ban-and-pick pool: poolDecks (nil = every deck), draftStakes, and
-- poolCocktails (each its own mix, an item of the pool).
function F.pool_decks(settings, all)
	return settings.poolDecks or all or {}
end

-- What is wrong with a pool, or nil.
function F.pool_problem(settings, all)
	if #(settings.draftStakes or {}) == 0 then
		return TOM.T("k_tom_pool_no_stakes")
	end
	local cocktails = settings.poolCocktails or {}
	if settings.poolDecks and #settings.poolDecks == 0 and #cocktails == 0 then
		return TOM.T("k_tom_pool_no_decks")
	end
	for _, c in ipairs(cocktails) do
		if #(c.decks or {}) == 0 then
			return TOM.T("k_tom_pool_empty_cocktail")
		end
	end
	return nil
end

-- "12 decks + 2 Cocktails, 3 stakes"
function F.pool_text(settings)
	local cocktails = #(settings.poolCocktails or {})
	local decks = settings.poolDecks and F.count(#settings.poolDecks, "k_tom_n_decks") or TOM.T("k_tom_every_deck")
	local stakes = #(settings.draftStakes or {})
	if cocktails > 0 then
		decks = TOM.T("k_tom_plus", decks, F.count(cocktails, "k_tom_n_cocktails"))
	end
	return TOM.T("k_tom_list2", decks, F.count(stakes, "k_tom_n_stakes"))
end

-- "1 deck" / "3 decks": key .. "_1" for one, key .. "_n" for any other count.
function F.count(n, key)
	return TOM.T(key .. (n == 1 and "_1" or "_n"), n)
end

-- A deep copy of a pool's lists (a round starting from the defaults).
function F.copy_pool(from, to)
	local function copy(list)
		if not list then
			return nil
		end
		local out = {}
		for i, v in ipairs(list) do
			out[i] = v
		end
		return out
	end
	to.poolDecks = copy(from.poolDecks)
	to.draftStakes = copy(from.draftStakes) or { 1 }
	to.poolCocktails = {}
	for i, c in ipairs(from.poolCocktails or {}) do
		to.poolCocktails[i] = { name = c.name, decks = copy(c.decks) }
	end
	return to
end

-- The deck object for the server from a form or a round (deckKind, deck,
-- stake, cocktail; or draftStakes, banOrder, poolDecks, poolCocktails).
-- decks: every deck (a pool left at "every deck").
local function deck_payload(settings, decks)
	if settings.deckKind == "locked" then
		local out = { kind = "locked", deck = settings.deck, stake = settings.stake }
		if settings.deck == F.COCKTAIL then
			out.cocktail = F.recipe_payload(settings.cocktail)
		end
		return out
	elseif settings.deckKind == "draft" then
		local stakes = {}
		for _, v in ipairs(settings.draftStakes or {}) do
			stakes[#stakes + 1] = v
		end
		table.sort(stakes)
		local pool = {}
		for _, d in ipairs(F.pool_decks(settings, decks)) do
			pool[#pool + 1] = d
		end
		local out = { kind = "draft", decks = pool, stakes = stakes, banOrder = settings.banOrder or "lower_seed_first" }
		local cocktails = {}
		for _, c in ipairs(settings.poolCocktails or {}) do
			cocktails[#cocktails + 1] = F.recipe_payload(c)
		end
		if #cocktails > 0 then
			out.cocktails = cocktails
		end
		return out
	end
	return nil
end
F.deck_payload = deck_payload

-- The description is edited as a few lines (Balatro's text boxes are one
-- line each) and stored with a newline between them.
F.DESC_LINES = 5
F.DESC_LINE = 100

-- A description as the editor's lines (always DESC_LINES of them). A line
-- longer than a box is split at a space where it can be.
function F.split_description(text, count, width)
	count, width = count or F.DESC_LINES, width or F.DESC_LINE
	local lines = {}
	for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
		while #line > width do
			local cut = line:sub(1, width):match("^.*() ") or (width + 1)
			lines[#lines + 1] = line:sub(1, cut - 1)
			line = line:sub(cut):gsub("^ ", "")
		end
		lines[#lines + 1] = line
	end
	local out = {}
	for i = 1, count do
		out[i] = lines[i] or ""
	end
	return out
end

-- The editor's lines as the description: trailing empty lines dropped.
function F.join_description(lines, count)
	count = count or F.DESC_LINES
	local last = 0
	for i = 1, count do
		if (lines[i] or ""):match("%S") then
			last = i
		end
	end
	local out = {}
	for i = 1, last do
		out[i] = (lines[i] or ""):gsub("%s+$", "")
	end
	return table.concat(out, "\n")
end

-- The game types a 1v1 bracket can play (key -> label comes from PvP).
-- Every match is 1v1, which PvP plays the same in each of its game modes, so
-- tournaments always use Nemesis; the ruleset is what organisers choose.
F.GAME_MODE = "pvp_nemesis"

-- The start as the player types it, in their local time: a date (from the
-- calendar), an hour 1-12, minutes and AM/PM. The hour and minutes are text
-- boxes, so they are strings.
function F.split_start(form)
	local t = os.date("*t", math.floor(form.startsAt / 1000))
	form.date = { year = t.year, month = t.month, day = t.day }
	local hour = t.hour % 12
	form.hour = tostring(hour == 0 and 12 or hour)
	form.minute = string.format("%02d", t.min)
	form.pm = t.hour >= 12
end

-- The start from the date and time fields (epoch ms), or nil and why not.
function F.start_from_fields(form)
	local hour = tonumber(form.hour or "")
	local minute = tonumber(form.minute or "")
	if not hour or hour ~= math.floor(hour) or hour < 1 or hour > 12 then
		return nil, TOM.T("k_tom_bad_hour")
	end
	if not minute or minute ~= math.floor(minute) or minute < 0 or minute > 59 then
		return nil, TOM.T("k_tom_bad_minutes")
	end
	local h24 = hour % 12 + (form.pm and 12 or 0)
	local d = form.date
	return os.time({ year = d.year, month = d.month, day = d.day, hour = h24, min = minute, sec = 0 }) * 1000
end

-- Copies the date and time fields into startsAt when they make sense.
function F.sync_start(form)
	local at, why = F.start_from_fields(form)
	if at then
		form.startsAt = at
	end
	return at, why
end

-- A month for the calendar: weeks of 7 days, Monday first; days outside the
-- month are false.
function F.month_grid(year, month)
	local first = os.date("*t", os.time({ year = year, month = month, day = 1, hour = 12 }))
	local days = os.date("*t", os.time({ year = year, month = month + 1, day = 0, hour = 12 })).day
	local lead = (first.wday + 5) % 7 -- wday 1 = Sunday -> Monday-first column
	local weeks, week = {}, {}
	for _ = 1, lead do
		week[#week + 1] = false
	end
	for day = 1, days do
		week[#week + 1] = day
		if #week == 7 then
			weeks[#weeks + 1] = week
			week = {}
		end
	end
	if #week > 0 then
		while #week < 7 do
			week[#week + 1] = false
		end
		weeks[#weeks + 1] = week
	end
	return weeks
end

-- Whether a day can be the start (not before today, not past 90 days).
function F.day_allowed(year, month, day, now_ms)
	local noon = os.time({ year = year, month = month, day = day, hour = 12 }) * 1000
	local today = os.date("*t", math.floor(now_ms / 1000))
	local today_noon = os.time({ year = today.year, month = today.month, day = today.day, hour = 12 }) * 1000
	return noon >= today_noon and noon <= now_ms + 90 * DAY
end

-- A fresh form. now_ms: the server's now. The start is the next whole hour
-- after an hour from now.
function F.new(now_ms)
	local start = math.ceil((now_ms + HOUR) / HOUR) * HOUR
	local form = {
		name = "",
		description = "",
		visibility = "public",
		official = false,
		-- Players need their ranked profile (as for ranked matchmaking).
		requireRanked = false,
		maxPlayers = 16,
		startsAt = start,
		checkInMinutes = 30,
		format = "single_elim",
		grandFinalReset = true,
		groupSize = false,
		swissRounds = false,
		seeding = "rating",
		ruleset = "ruleset_mp_balanced",
		bestOf = 3,
		-- Ban and pick from every deck on White to Gold, like matchmaking.
		deckKind = "draft",
		deck = "b_red",
		stake = 1,
		draftStakes = { 1, 2, 3, 4, 5, 6, 7, 8 },
		banOrder = "lower_seed_first",
		-- Locked to the Cocktail: its mix.
		cocktail = new_recipe(),
		-- Ban and pick: the pool (nil = every deck) and its Cocktails.
		poolDecks = nil,
		poolCocktails = {},
		preset = "live_event",
		readyUpMinutes = 10,
		breakMinutes = 0,
		windowMinutes = 7 * 24 * 60,
		-- Round by round: "R1", "R2"... and named rounds ("FINAL"...), each a
		-- table of what differs from the defaults (see F.round_override).
		rounds = {},
		-- The timetable round by round, keyed the same (see F.timing_override).
		timing = {},
	}
	F.split_start(form)
	return form
end

-- nil (a field never set) matches a list's false entry ("Same as defaults").
local function index_of(list, value)
	if value == nil then
		value = false
	end
	for i, entry in ipairs(list) do
		if entry[1] == value then
			return i
		end
	end
	return nil
end

-- Step a choice: dir = 1 next, -1 previous (wraps around).
function F.step(form, key, dir, list)
	list = list or F.CHOICES[key]
	local i = index_of(list, form[key]) or 1
	i = ((i - 1 + dir) % #list) + 1
	form[key] = list[i][1]
end

-- A label: a text key (k_tom_...) is looked up; text a list was built with
-- at runtime (PvP's game modes, stakes) is shown as it is.
function F.text(label)
	if type(label) == "string" and label:sub(1, 6) == "k_tom_" then
		return TOM.T(label)
	end
	return label
end

function F.label(form, key, list)
	list = list or F.CHOICES[key]
	local i = list and index_of(list, form[key])
	return i and F.text(list[i][2]) or tostring(form[key])
end

-- Rounds ------------------------------------------------------------------

local function log2_ceil(n)
	local k = 0
	while 2 ^ k < n do
		k = k + 1
	end
	return k
end

-- The group size the server will use (lifecycle.ts fittedFormatOptions).
local function fitted_group_size(group_size, players)
	local size = math.max(2, group_size or players)
	local function smallest(sz)
		local count = math.max(1, math.ceil(players / math.max(2, sz)))
		return math.floor(players / count)
	end
	while size < players and smallest(size) < 2 do
		size = size + 1
	end
	return math.min(size, players)
end

-- The named rounds a format has, in the order the wizard lists them.
F.NAMED = {
	single_elim = { { "QUARTER", "k_tom_opt_quarterfinals" }, { "SEMI", "k_tom_opt_semifinals" }, { "FINAL", "k_tom_opt_final" } },
	double_elim = { { "WINNERS_FINAL", "k_tom_opt_winners_final" }, { "LOSERS_FINAL", "k_tom_opt_losers_final" }, { "FINAL", "k_tom_opt_grand_final" } },
}

function F.named_label(format, key)
	for _, entry in ipairs(F.NAMED[format] or {}) do
		if entry[1] == key then
			return F.text(entry[2])
		end
	end
	return key
end

-- The rounds a tournament plays with `players` players, in playing order:
-- { { n = 1, names = { "SEMI" } }, ... }. Double elimination counts a winners
-- round and the losers round played alongside it as one round, like the
-- server (engine/schedule.ts roundSteps).
function F.round_plan(form, players)
	players = math.max(2, players)
	local out = {}
	local function add(names)
		out[#out + 1] = { n = #out + 1, names = names or {} }
	end
	if form.format == "single_elim" then
		local k = math.max(1, log2_ceil(players))
		for r = 1, k do
			local names = nil
			if r == k then
				names = { "FINAL" }
			elseif r == k - 1 then
				names = { "SEMI" }
			elseif r == k - 2 then
				names = { "QUARTER" }
			end
			add(names)
		end
	elseif form.format == "double_elim" then
		local k = math.max(1, log2_ceil(players))
		add(k == 1 and { "WINNERS_FINAL" } or nil) -- W1
		for j = 1, k - 1 do
			add(j + 1 == k and { "WINNERS_FINAL" } or nil) -- W(j+1) and L(2j-1)
			add(j == k - 1 and { "LOSERS_FINAL" } or nil) -- L(2j)
		end
		add({ "FINAL" }) -- the grand final
		if form.grandFinalReset then
			add({ "FINAL" }) -- its reset
		end
	elseif form.format == "round_robin" then
		local size = fitted_group_size(form.groupSize or nil, players)
		local count = math.max(1, math.ceil(players / size))
		local largest = math.ceil(players / count)
		for _ = 1, (largest % 2 == 0) and (largest - 1) or largest do
			add()
		end
	elseif form.format == "swiss" then
		local rounds = form.swissRounds and math.max(1, math.min(form.swissRounds, players - 1)) or math.max(1, log2_ceil(players))
		for _ = 1, rounds do
			add()
		end
	end
	return out
end

-- A round's override for the server, or nil when it changes nothing.
-- decks: the deck keys for a ban-and-pick pool.
function F.round_override(round, decks)
	if not round then
		return nil
	end
	local out, any = {}, false
	for _, key in ipairs({ "ruleset", "bestOf" }) do
		if round[key] then
			out[key] = round[key]
			any = true
		end
	end
	if (round.deckKind == "locked" and round.deck and round.stake) or (round.deckKind == "draft" and round.draftStakes and #round.draftStakes > 0) then
		out.deck = deck_payload(round, decks)
		any = true
	end
	return any and out or nil
end

-- The keys this form's rounds can use: numbered up to the most rounds the
-- player limit allows, and the format's named rounds.
function F.round_keys(form)
	local keys = {}
	for i = 1, #F.round_plan(form, form.maxPlayers) do
		keys[#keys + 1] = "R" .. i
	end
	for _, entry in ipairs(F.NAMED[form.format] or {}) do
		keys[#keys + 1] = entry[1]
	end
	return keys
end

-- What a round of the plan plays: the defaults, then its number, then its
-- name (each only changes what it sets), as the form's own fields.
function F.effective(form, plan_round)
	local out = {
		ruleset = form.ruleset,
		bestOf = form.bestOf,
		deckKind = form.deckKind,
		deck = form.deck,
		stake = form.stake,
		draftStakes = form.draftStakes,
		banOrder = form.banOrder,
		poolDecks = form.poolDecks,
		poolCocktails = form.poolCocktails,
		cocktail = form.cocktail,
	}
	local layers = { form.rounds["R" .. plan_round.n] }
	for _, name in ipairs(plan_round.names) do
		layers[#layers + 1] = form.rounds[name]
	end
	for i = 1, #layers + 1 do
		local layer = layers[i]
		if layer then
			for _, key in ipairs({ "ruleset", "bestOf" }) do
				if layer[key] then
					out[key] = layer[key]
				end
			end
			if layer.deckKind == "locked" or layer.deckKind == "draft" then
				out.deckKind, out.deck, out.stake = layer.deckKind, layer.deck, layer.stake
				out.draftStakes, out.banOrder = layer.draftStakes, layer.banOrder
				out.poolDecks, out.poolCocktails, out.cocktail = layer.poolDecks, layer.poolCocktails, layer.cocktail
			end
		end
	end
	return out
end

-- One line for a round's settings: the parts that differ from the defaults
-- (everything with `all`). names: lists of { value, label } to name keys with
-- (ruleset, deck, stake).
function F.describe(settings, form, names, all)
	names = names or {}
	local parts = {}
	local function differs(key)
		return all or settings[key] ~= form[key]
	end
	if differs("ruleset") then
		parts[#parts + 1] = F.label(settings, "ruleset", names.ruleset)
	end
	local deck_differs = all or settings.deckKind ~= form.deckKind or settings.deck ~= form.deck or settings.stake ~= form.stake or settings.draftStakes ~= form.draftStakes or settings.cocktail ~= form.cocktail or settings.poolDecks ~= form.poolDecks or settings.poolCocktails ~= form.poolCocktails
	if deck_differs then
		if settings.deckKind == "locked" then
			parts[#parts + 1] = TOM.T("k_tom_deck_on_stake", F.label(settings, "deck", names.deck), F.label(settings, "stake", names.stake))
		elseif settings.deckKind == "draft" then
			parts[#parts + 1] = TOM.T("k_tom_ban_and_pick_of", F.pool_text(settings))
		elseif all then
			parts[#parts + 1] = TOM.T("k_tom_decks_unset")
		end
	end
	if differs("bestOf") then
		parts[#parts + 1] = F.label(settings, "bestOf"):lower()
	end
	if #parts == 0 then
		return TOM.T("k_tom_same_as_defaults")
	end
	return table.concat(parts, ", ")
end

-- The round overrides for the server: only keys this format and player limit
-- can use, and only rounds that change something. nil when there are none
-- (an empty table could be sent as []).
function F.overrides(form, decks)
	local out, any = {}, false
	for _, key in ipairs(F.round_keys(form)) do
		local o = F.round_override(form.rounds and form.rounds[key], decks)
		if o then
			out[key] = o
			any = true
		end
	end
	return any and out or nil
end

-- Timetable round by round -----------------------------------------------

-- Longer than a couple of hours: continue at a date and time instead.
F.TIMING = {
	breakBefore = { { false, "k_tom_opt_no_break" }, { 5, "k_tom_opt_5_min" }, { 10, "k_tom_opt_10_min" }, { 15, "k_tom_opt_15_min" }, { 30, "k_tom_opt_30_min" }, { 60, "k_tom_opt_1_hour" }, { 120, "k_tom_opt_2_hours" } },
	start = { { false, "k_tom_opt_after_the_rounds_before_it" }, { "manual", "k_tom_opt_when_i_press_start_round" }, { "at", "k_tom_opt_at_a_date_and_time" } },
	play = { { false, "k_tom_opt_same_as_the_timetable" }, { "live", "k_tom_opt_live_with_a_ready_up" }, { "window", "k_tom_opt_by_a_deadline" } },
	-- A round at a date and time: its own check-in (as the tournament's).
	checkInMinutes = F.CHOICES.checkInMinutes,
}

-- Days after the start day a round can continue on.
F.AT_DAYS_MAX = 14

-- When a round set to continue "at a date and time" continues (epoch ms), or
-- nil and why not: t.atDay days after the tournament's start day, at
-- t.atHour:t.atMinute AM/PM, local time.
function F.round_start_at(t, form)
	local hour, minute = tonumber(t.atHour or ""), tonumber(t.atMinute or "")
	if not hour or hour ~= math.floor(hour) or hour < 1 or hour > 12 then
		return nil, TOM.T("k_tom_bad_hour")
	end
	if not minute or minute ~= math.floor(minute) or minute < 0 or minute > 59 then
		return nil, TOM.T("k_tom_bad_minutes")
	end
	local d = form.date or os.date("*t", math.floor(form.startsAt / 1000))
	return os.time({ year = d.year, month = d.month, day = d.day + (t.atDay or 0), hour = hour % 12 + (t.atPm and 12 or 0), min = minute, sec = 0 }) * 1000
end

-- A round's timetable change for the server, or nil when it changes nothing.
-- form: for a round that continues at a date and time.
function F.timing_override(t, form)
	if not t then
		return nil
	end
	local out, any = {}, false
	if t.start == "at" and form then
		out.startAt = F.round_start_at(t, form)
		any = out.startAt ~= nil
		if out.startAt and t.checkInMinutes then
			out.checkInMinutes = t.checkInMinutes
		end
	elseif t.start == "manual" then
		out.manualStart = true
		any = true
	elseif t.breakBefore then
		out.breakBefore = t.breakBefore
		any = true
	end
	if t.play == "live" then
		out.play = { kind = "live", readyUpMinutes = t.readyUpMinutes or 10 }
		any = true
	elseif t.play == "window" then
		out.play = { kind = "window", durationMinutes = t.windowMinutes or 24 * 60 }
		any = true
	end
	if any and t.onward and out.play then
		out.onward = true
	end
	return any and out or nil
end

-- The timetable changes for the server, or nil when none.
function F.timing_payload(form)
	local out, any = {}, false
	for _, key in ipairs(F.round_keys(form)) do
		local o = F.timing_override(form.timing and form.timing[key], form)
		if o then
			out[key] = o
			any = true
		end
	end
	return any and out or nil
end

local WEEKDAYS = { "sun", "mon", "tue", "wed", "thu", "fri", "sat" }
local MONTHS = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" }

-- "Sat, Nov 14"
local function day_text(t)
	return TOM.T("k_tom_day_date", TOM.T("k_tom_day_" .. WEEKDAYS[t.wday]), TOM.T("k_tom_month_" .. MONTHS[t.month]), t.day)
end

-- "Sat, Nov 14, 8:00 PM"
function F.when_text(ms)
	local t = os.date("*t", math.floor(ms / 1000))
	local hour = t.hour % 12
	local clock = TOM.T(t.hour < 12 and "k_tom_clock_am" or "k_tom_clock_pm", hour == 0 and 12 or hour, string.format("%02d", t.min))
	return TOM.T("k_tom_list2", day_text(t), clock)
end

-- The days a round can continue on: { day offset, "Sat, Nov 14" }.
function F.at_days(form)
	local d = form.date or os.date("*t", math.floor(form.startsAt / 1000))
	local out = {}
	for i = 0, F.AT_DAYS_MAX do
		local t = os.date("*t", os.time({ year = d.year, month = d.month, day = d.day + i, hour = 12 }))
		out[#out + 1] = { i, i == 0 and TOM.T("k_tom_start_day", day_text(t)) or day_text(t) }
	end
	return out
end

-- One line for a round's timetable change.
function F.describe_timing(t, form)
	if not F.timing_override(t, form) then
		return TOM.T("k_tom_as_timetable")
	end
	local parts = {}
	if t.start == "at" and form then
		parts[#parts + 1] = TOM.T("k_tom_continues", F.when_text(F.round_start_at(t, form)))
		if t.checkInMinutes then
			parts[#parts + 1] = TOM.T("k_tom_round_check_in_part", F.label(t, "checkInMinutes", F.TIMING.checkInMinutes))
		end
	elseif t.start == "manual" then
		parts[#parts + 1] = TOM.T("k_tom_you_start_it")
	elseif t.breakBefore then
		parts[#parts + 1] = TOM.T("k_tom_break_first", F.label(t, "breakBefore", F.TIMING.breakBefore))
	end
	if t.play == "live" then
		parts[#parts + 1] = TOM.T("k_tom_live_ready_up", F.label(t, "readyUpMinutes"))
	elseif t.play == "window" then
		parts[#parts + 1] = TOM.T("k_tom_by_deadline", F.label(t, "windowMinutes"))
	end
	if t.onward and t.play then
		parts[#parts + 1] = TOM.T("k_tom_every_later_round")
	end
	return table.concat(parts, "; ")
end

-- Editing an existing tournament ------------------------------------------

local function list_copy(list)
	local out = {}
	for i, v in ipairs(list or {}) do
		out[i] = v
	end
	return out
end

local function recipe_of(c)
	if type(c) ~= "table" then
		return F.new_recipe()
	end
	return { name = c.name or "", decks = list_copy(c.decks) }
end

-- Whether a deck list is every deck (then the form keeps "every deck").
local function is_every(decks, all)
	if not all or #decks ~= #all then
		return false
	end
	local have = {}
	for _, d in ipairs(decks) do
		have[d] = true
	end
	for _, d in ipairs(all) do
		if not have[d] then
			return false
		end
	end
	return true
end

-- A server deck rule as the form's (or a round's) deck fields, written into
-- `into`. all: every deck (a pool of all of them reads as "every deck").
local function deck_into(into, deck, all)
	if type(deck) ~= "table" then
		return
	end
	if deck.kind == "locked" then
		into.deckKind, into.deck, into.stake = "locked", deck.deck, deck.stake
		if deck.cocktail then
			into.cocktail = recipe_of(deck.cocktail)
		end
	elseif deck.kind == "draft" then
		into.deckKind = "draft"
		local decks = list_copy(deck.decks)
		-- Every deck reads as "every deck" (nil).
		if #decks == 0 or is_every(decks, all) then
			into.poolDecks = nil
		else
			into.poolDecks = decks
		end
		into.draftStakes = list_copy(deck.stakes)
		into.banOrder = deck.banOrder
		into.poolCocktails = {}
		for i, c in ipairs(deck.cocktails or {}) do
			into.poolCocktails[i] = recipe_of(c)
		end
	end
end

-- Days from one local date to another.
local function days_between(a, b)
	local ta = os.time({ year = a.year, month = a.month, day = a.day, hour = 12 })
	local tb = os.time({ year = b.year, month = b.month, day = b.day, hour = 12 })
	return math.floor((tb - ta) / 86400 + 0.5)
end

-- A server round-timing change as the form's.
local function timing_of(t, start_date)
	local out = {}
	if t.breakBefore then
		out.breakBefore = t.breakBefore
	end
	if t.startAt then
		local at = os.date("*t", math.floor(t.startAt / 1000))
		local hour = at.hour % 12
		out.start = "at"
		out.atDay = math.max(0, days_between(start_date, at))
		out.atHour = tostring(hour == 0 and 12 or hour)
		out.atMinute = string.format("%02d", at.min)
		out.atPm = at.hour >= 12
		out.checkInMinutes = t.checkInMinutes or false
	elseif t.manualStart then
		out.start = "manual"
	end
	if type(t.play) == "table" then
		out.play = t.play.kind
		if t.play.kind == "live" then
			out.readyUpMinutes = t.play.readyUpMinutes
		else
			out.windowMinutes = t.play.durationMinutes
		end
		out.onward = t.onward == true
	end
	return out
end

-- The wizard's form for an existing tournament (its full view, from
-- tournament_get). all: every deck PvP plays.
function F.from_view(view, now_ms, all)
	local s = view.summary or {}
	local form = F.new(now_ms)
	form.name = s.name or ""
	form.description = view.description or ""
	form.visibility = s.visibility or "public"
	form.official = s.official == true
	form.requireRanked = s.requireRanked == true
	form.maxPlayers = s.maxPlayers or form.maxPlayers
	form.startsAt = s.startsAt or form.startsAt
	F.split_start(form)
	form.checkInMinutes = s.checkInAt and math.floor((s.startsAt - s.checkInAt) / 60000 + 0.5) or false
	form.format = s.format or form.format
	local fo = view.formatOptions or {}
	if fo.grandFinalReset ~= nil then
		form.grandFinalReset = fo.grandFinalReset
	end
	form.groupSize = fo.groupSize or false
	form.swissRounds = fo.swissRounds or false
	form.seeding = view.seeding and view.seeding.kind or form.seeding
	local d = view.rounds and view.rounds.defaults or {}
	form.ruleset = d.ruleset or form.ruleset
	form.bestOf = d.bestOf or form.bestOf
	deck_into(form, d.deck, all)
	form.rounds = {}
	for key, o in pairs(view.rounds and view.rounds.overrides or {}) do
		local round = { ruleset = o.ruleset, bestOf = o.bestOf }
		deck_into(round, o.deck, all)
		form.rounds[key] = round
	end
	local tt = view.timetable or {}
	if tt.kind == "preset" then
		form.preset = tt.preset
		local o = tt.options or {}
		form.readyUpMinutes = o.readyUpMinutes or form.readyUpMinutes
		form.breakMinutes = o.breakMinutes or form.breakMinutes
		form.windowMinutes = o.windowMinutes or form.windowMinutes
		form.timing = {}
		for key, t in pairs(tt.rounds or {}) do
			form.timing[key] = timing_of(t, form.date)
		end
	end
	return form
end

-- Deep equality for payload values.
local function same(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- What changed between two payloads, as a tournament_update body (top-level
-- fields only; nil when nothing did). running: only what the server lets an
-- organiser change after the start (name, description, round settings).
function F.changes(before, after, running)
	local out, any = {}, false
	local keys = {}
	for k in pairs(after) do
		keys[k] = true
	end
	for k in pairs(before) do
		keys[k] = true
	end
	local allowed = running and { name = true, description = true, rounds = true } or nil
	-- A setting switched off is missing from `after`; say so explicitly (the
	-- server keeps what it isn't sent).
	local OFF = { checkInMinutes = false, formatOptions = {} }
	for k in pairs(keys) do
		if (not allowed or allowed[k]) and not same(before[k], after[k]) then
			if after[k] == nil then
				out[k] = OFF[k]
			else
				out[k] = after[k]
			end
			any = any or out[k] ~= nil
		end
	end
	return any and out or nil
end

-- What the format needs that the others don't.
function F.uses(form, option)
	if option == "grandFinalReset" then
		return form.format == "double_elim"
	elseif option == "groupSize" then
		return form.format == "round_robin"
	elseif option == "swissRounds" then
		return form.format == "swiss"
	elseif option == "readyUpMinutes" then
		return form.preset ~= "league"
	elseif option == "breakMinutes" then
		return form.preset == "live_event"
	elseif option == "windowMinutes" then
		return form.preset == "league"
	elseif option == "deck" or option == "stake" then
		return form.deckKind == "locked"
	elseif option == "draftStakes" or option == "banOrder" then
		return form.deckKind == "draft"
	end
	return true
end

-- The wizard's steps, and which fields each one checks.
F.STEPS = {
	{ key = "basics", title = "k_tom_step_basics" },
	{ key = "format", title = "k_tom_step_format" },
	{ key = "games", title = "k_tom_step_games" },
	{ key = "rounds", title = "k_tom_step_rounds" },
	{ key = "schedule", title = "k_tom_step_schedule" },
	{ key = "review", title = "k_tom_step_review" },
}

-- What is still wrong on a step (or, with no step, anywhere): a list of
-- sentences, empty when fine.
-- opts (an edit): started = the tournament is running (its start can't
-- change); original_start = its start, which may be close now and still stay.
function F.problems(form, now_ms, step, opts)
	opts = opts or {}
	local out = {}
	local function check(on, ok, message)
		if (step == nil or step == on) and not ok then
			out[#out + 1] = message
		end
	end
	local name = (form.name or ""):match("^%s*(.-)%s*$")
	check("basics", #name >= 3, TOM.T("k_tom_name_short"))
	check("basics", #name <= 48, TOM.T("k_tom_name_long"))
	check("basics", #(form.description or "") <= 500, TOM.T("k_tom_desc_long"))
	-- The start comes from the date and time fields when the form has them.
	local at, why = form.startsAt, nil
	if form.date then
		at, why = F.sync_start(form)
	end
	local start_fixed = opts.started or (opts.original_start and at == opts.original_start)
	if not opts.started then
		check("basics", why == nil, why)
	end
	check("basics", start_fixed or not at or at >= now_ms + 5 * MINUTE, TOM.T("k_tom_start_too_soon"))
	check("basics", start_fixed or not at or at <= now_ms + 90 * DAY, TOM.T("k_tom_start_too_far"))
	check("format", not (form.format == "round_robin" and form.groupSize and form.groupSize > form.maxPlayers), "Groups can't be bigger than the tournament.")
	check("games", form.deckKind ~= "draft" or F.pool_problem(form) == nil, form.deckKind == "draft" and F.pool_problem(form) or nil)
	check("games", not (form.deckKind == "locked" and not form.deck), "Pick the deck everyone plays.")
	local function mixed(settings)
		return not F.uses_cocktail(settings) or #((settings.cocktail or {}).decks or {}) > 0
	end
	check("games", mixed(form), TOM.T("k_tom_mix_needed"))
	-- A round that continues at a date and time: a real time, after the
	-- start, its check-in opening after the start too, and in round order.
	-- (The server checks the same: lifecycle.ts timedRoundsFit.)
	local previous = form.startsAt or 0
	for _, key in ipairs(F.round_keys(form)) do
		local t = form.timing and form.timing[key]
		if t and t.start == "at" then
			local at, why = F.round_start_at(t, form)
			check("schedule", at ~= nil, why and TOM.T("k_tom_round_start_problem", why) or nil)
			check("schedule", not at or at > (form.startsAt or 0), TOM.T("k_tom_round_before_start"))
			check("schedule", not (at and t.checkInMinutes) or at - t.checkInMinutes * MINUTE >= (form.startsAt or 0), TOM.T("k_tom_round_check_in_before_start"))
			check("schedule", not at or at >= previous, TOM.T("k_tom_rounds_out_of_order"))
			if at and at > previous then
				previous = at
			end
		end
	end
	for _, round in pairs(form.rounds or {}) do
		if round.deckKind == "draft" and F.pool_problem(round) then
			check("rounds", false, TOM.T("k_tom_round_pool_problem", F.pool_problem(round)))
		end
		if not mixed(round) then
			check("rounds", false, TOM.T("k_tom_round_mix_needed"))
		end
	end
	return out
end

-- The tournament_create payload. decks: the deck keys for a draft pool.
function F.payload(form, decks)
	local defaults = { gameMode = F.GAME_MODE, ruleset = form.ruleset, bestOf = form.bestOf }
	defaults.deck = deck_payload(form, decks)
	local format_options = {}
	if form.format == "double_elim" then
		format_options.grandFinalReset = form.grandFinalReset
	elseif form.format == "round_robin" and form.groupSize then
		format_options.groupSize = form.groupSize
	elseif form.format == "swiss" and form.swissRounds then
		format_options.swissRounds = form.swissRounds
	end
	local options = {}
	if form.preset == "league" then
		options.windowMinutes = form.windowMinutes
	else
		options.readyUpMinutes = form.readyUpMinutes
		if form.preset == "live_event" then
			options.breakMinutes = form.breakMinutes
		end
	end
	return {
		name = (form.name or ""):match("^%s*(.-)%s*$"),
		description = form.description or "",
		visibility = form.visibility,
		official = form.official,
		requireRanked = form.requireRanked == true,
		format = form.format,
		-- Left out when empty: an empty Lua table may encode as [] (not an object).
		formatOptions = next(format_options) and format_options or nil,
		maxPlayers = form.maxPlayers,
		startsAt = form.startsAt,
		-- false (no check-in) is sent as nil: the server reads a missing value as none.
		checkInMinutes = form.checkInMinutes or nil,
		seeding = { kind = form.seeding },
		rounds = { defaults = defaults, overrides = F.overrides(form, decks) },
		timetable = { kind = "preset", preset = form.preset, options = options, rounds = F.timing_payload(form) },
	}
end

return F
