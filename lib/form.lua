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
		{ "public", "Public (listed in Browse)" },
		{ "private", "Private (invite code only)" },
	},
	maxPlayers = { { 4, "4" }, { 8, "8" }, { 12, "12" }, { 16, "16" }, { 24, "24" }, { 32, "32" }, { 48, "48" }, { 64, "64" }, { 96, "96" }, { 128, "128" } },
	checkInMinutes = { { false, "No check-in" }, { 10, "10 min before" }, { 15, "15 min before" }, { 20, "20 min before" }, { 30, "30 min before" }, { 45, "45 min before" }, { 60, "60 min before" } },
	format = {
		{ "single_elim", "Single elimination" },
		{ "double_elim", "Double elimination" },
		{ "round_robin", "Round robin" },
		{ "swiss", "Swiss" },
	},
	grandFinalReset = { { true, "Yes (bracket reset)" }, { false, "No" } },
	groupSize = { { false, "One group" }, { 3, "Groups of 3" }, { 4, "Groups of 4" }, { 5, "Groups of 5" }, { 6, "Groups of 6" }, { 8, "Groups of 8" } },
	swissRounds = { { false, "Automatic" }, { 3, "3" }, { 4, "4" }, { 5, "5" }, { 6, "6" }, { 7, "7" }, { 8, "8" }, { 9, "9" } },
	seeding = {
		{ "rating", "By ranked rating" },
		{ "random", "Random" },
		{ "manual", "I set the order" },
	},
	bestOf = { { 1, "Best of 1" }, { 3, "Best of 3" }, { 5, "Best of 5" }, { 7, "Best of 7" } },
	deckKind = {
		{ "any", "Players pick (lobby default)" },
		{ "locked", "Everyone plays one deck" },
		{ "draft", "Ban and pick from a pool" },
	},
	-- The base game's stakes; in the game the wizard lists every stake it has
	-- (PvP adds Planet, Spectral and Spectral+ after Gold).
	stake = { { 1, "White" }, { 2, "Red" }, { 3, "Green" }, { 4, "Black" }, { 5, "Blue" }, { 6, "Purple" }, { 7, "Orange" }, { 8, "Gold" } },
	banOrder = {
		{ "lower_seed_first", "Lower seed bans first" },
		{ "lower_seed_last", "Higher seed bans first" },
		{ "random", "Random" },
		{ "previous_loser_first", "Loser of the last game first" },
	},
	preset = {
		{ "live_event", "Live: play as soon as both are ready" },
		{ "live_fixed_rounds", "Live: I start each round" },
		{ "league", "League: play by a deadline" },
	},
	readyUpMinutes = { { 5, "5 min" }, { 10, "10 min" }, { 15, "15 min" }, { 20, "20 min" }, { 30, "30 min" } },
	breakMinutes = { { 0, "No breaks" }, { 5, "5 min" }, { 10, "10 min" }, { 15, "15 min" }, { 30, "30 min" }, { 60, "1 hour" } },
	windowMinutes = { { 1 * 24 * 60, "1 day" }, { 2 * 24 * 60, "2 days" }, { 3 * 24 * 60, "3 days" }, { 5 * 24 * 60, "5 days" }, { 7 * 24 * 60, "1 week" }, { 14 * 24 * 60, "2 weeks" } },
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
		return "The stake pool is empty: pick at least one stake."
	end
	local cocktails = settings.poolCocktails or {}
	if settings.poolDecks and #settings.poolDecks == 0 and #cocktails == 0 then
		return "The deck pool is empty: pick a deck or add a Cocktail."
	end
	for _, c in ipairs(cocktails) do
		if #(c.decks or {}) == 0 then
			return "A Cocktail in the deck pool mixes nothing yet."
		end
	end
	return nil
end

-- "12 decks + 2 Cocktails, 3 stakes"
function F.pool_text(settings)
	local cocktails = #(settings.poolCocktails or {})
	local decks = settings.poolDecks and (#settings.poolDecks .. " decks") or "every deck"
	local stakes = #(settings.draftStakes or {})
	return decks .. (cocktails > 0 and (" + " .. cocktails .. " Cocktail" .. (cocktails > 1 and "s" or "")) or "") .. ", " .. stakes .. " stake" .. (stakes == 1 and "" or "s")
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

-- The game types a 1v1 bracket can play (key -> label comes from PvP).
F.GAME_MODES = { "pvp_nemesis", "pvp_smallworld", "pvp_royale", "pvp_experimental" }

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
		return nil, "The hour must be 1-12."
	end
	if not minute or minute ~= math.floor(minute) or minute < 0 or minute > 59 then
		return nil, "The minutes must be 0-59."
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
		maxPlayers = 16,
		startsAt = start,
		checkInMinutes = 30,
		format = "single_elim",
		grandFinalReset = true,
		groupSize = false,
		swissRounds = false,
		seeding = "rating",
		gameMode = "pvp_nemesis",
		ruleset = "ruleset_mp_balanced",
		bestOf = 3,
		deckKind = "any",
		deck = "b_red",
		stake = 1,
		draftStakes = { 1 },
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

function F.label(form, key, list)
	list = list or F.CHOICES[key]
	local i = list and index_of(list, form[key])
	return i and list[i][2] or tostring(form[key])
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
	single_elim = { { "QUARTER", "Quarterfinals" }, { "SEMI", "Semifinals" }, { "FINAL", "Final" } },
	double_elim = { { "WINNERS_FINAL", "Winners final" }, { "LOSERS_FINAL", "Losers final" }, { "FINAL", "Grand final" } },
}

function F.named_label(format, key)
	for _, entry in ipairs(F.NAMED[format] or {}) do
		if entry[1] == key then
			return entry[2]
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
	for _, key in ipairs({ "gameMode", "ruleset", "bestOf" }) do
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
		gameMode = form.gameMode,
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
			for _, key in ipairs({ "gameMode", "ruleset", "bestOf" }) do
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
-- (gameMode, ruleset, deck, stake).
function F.describe(settings, form, names, all)
	names = names or {}
	local parts = {}
	local function differs(key)
		return all or settings[key] ~= form[key]
	end
	if differs("gameMode") then
		parts[#parts + 1] = F.label(settings, "gameMode", names.gameMode)
	end
	if differs("ruleset") then
		parts[#parts + 1] = F.label(settings, "ruleset", names.ruleset)
	end
	local deck_differs = all or settings.deckKind ~= form.deckKind or settings.deck ~= form.deck or settings.stake ~= form.stake or settings.draftStakes ~= form.draftStakes or settings.cocktail ~= form.cocktail or settings.poolDecks ~= form.poolDecks or settings.poolCocktails ~= form.poolCocktails
	if deck_differs then
		if settings.deckKind == "locked" then
			parts[#parts + 1] = F.label(settings, "deck", names.deck) .. " on " .. F.label(settings, "stake", names.stake)
		elseif settings.deckKind == "draft" then
			parts[#parts + 1] = "ban and pick (" .. F.pool_text(settings) .. ")"
		elseif all then
			parts[#parts + 1] = "players pick decks"
		end
	end
	if differs("bestOf") then
		parts[#parts + 1] = F.label(settings, "bestOf"):lower()
	end
	if #parts == 0 then
		return "same as the defaults"
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
	{ key = "basics", title = "BASICS" },
	{ key = "format", title = "FORMAT" },
	{ key = "games", title = "GAMES" },
	{ key = "rounds", title = "ROUNDS" },
	{ key = "schedule", title = "SCHEDULE" },
	{ key = "review", title = "REVIEW" },
}

-- What is still wrong on a step (or, with no step, anywhere): a list of
-- sentences, empty when fine.
function F.problems(form, now_ms, step)
	local out = {}
	local function check(on, ok, message)
		if (step == nil or step == on) and not ok then
			out[#out + 1] = message
		end
	end
	local name = (form.name or ""):match("^%s*(.-)%s*$")
	check("basics", #name >= 3, "The name needs at least 3 characters.")
	check("basics", #name <= 48, "The name can be at most 48 characters.")
	check("basics", #(form.description or "") <= 500, "The description can be at most 500 characters.")
	-- The start comes from the date and time fields when the form has them.
	local at, why = form.startsAt, nil
	if form.date then
		at, why = F.sync_start(form)
	end
	check("basics", why == nil, why)
	check("basics", not at or at >= now_ms + 5 * MINUTE, "The start must be at least 5 minutes away.")
	check("basics", not at or at <= now_ms + 90 * DAY, "The start can be at most 90 days away.")
	check("format", not (form.format == "round_robin" and form.groupSize and form.groupSize > form.maxPlayers), "Groups can't be bigger than the tournament.")
	check("games", form.deckKind ~= "draft" or F.pool_problem(form) == nil, form.deckKind == "draft" and F.pool_problem(form) or nil)
	check("games", not (form.deckKind == "locked" and not form.deck), "Pick the deck everyone plays.")
	local function mixed(settings)
		return not F.uses_cocktail(settings) or #((settings.cocktail or {}).decks or {}) > 0
	end
	check("games", mixed(form), "Mix 1 to 3 decks for the Cocktail (MIX).")
	for _, round in pairs(form.rounds or {}) do
		if round.deckKind == "draft" and F.pool_problem(round) then
			check("rounds", false, "A round's pool: " .. F.pool_problem(round))
		end
		if not mixed(round) then
			check("rounds", false, "A round with the Cocktail needs 1 to 3 decks mixed (MIX).")
		end
	end
	return out
end

-- The tournament_create payload. decks: the deck keys for a draft pool.
function F.payload(form, decks)
	local defaults = { gameMode = form.gameMode, ruleset = form.ruleset, bestOf = form.bestOf }
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
		format = form.format,
		-- Left out when empty: an empty Lua table may encode as [] (not an object).
		formatOptions = next(format_options) and format_options or nil,
		maxPlayers = form.maxPlayers,
		startsAt = form.startsAt,
		-- false (no check-in) is sent as nil: the server reads a missing value as none.
		checkInMinutes = form.checkInMinutes or nil,
		seeding = { kind = form.seeding },
		rounds = { defaults = defaults, overrides = F.overrides(form, decks) },
		timetable = { kind = "preset", preset = form.preset, options = options },
	}
end

return F
