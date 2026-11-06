-- Run from the repo root: lua5.4 tests/edit_test.lua
-- lib/form.lua: an existing tournament back into the wizard's form, and
-- what an edit sends (only what changed).
dofile("lib/form.lua")
local F = TOM.Form

local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end

local NOW = os.time({ year = 2027, month = 3, day = 10, hour = 15, min = 0, sec = 0 }) * 1000
local ALL = { "b_red", "b_blue", "b_black", "b_mp_orange" }

-- A weekly with everything set.
local form = F.new(NOW)
form.name = "Friday Weekly"
form.description = "Line one\nLine two"
form.visibility = "private"
form.requireRanked = true
form.maxPlayers = 32
form.checkInMinutes = 20
form.format = "double_elim"
form.grandFinalReset = false
form.seeding = "random"
form.bestOf = 5
form.deckKind = "draft"
form.poolDecks = { "b_red", "b_mp_orange" }
form.draftStakes = { 1, 5, 11 }
form.banOrder = "previous_loser_first"
form.poolCocktails = { { name = "Mix", decks = { "b_black", "b_blue" } } }
form.rounds = {
	R1 = { deckKind = "locked", deck = "b_mp_cocktail", stake = 4, cocktail = { name = "", decks = { "b_red" } } },
	FINAL = { bestOf = 7 },
}
form.preset = "league"
form.windowMinutes = 3 * 24 * 60
form.timing = {
	R2 = { breakBefore = 15 },
	LOSERS_FINAL = { play = "live", readyUpMinutes = 10, onward = true },
	FINAL = { start = "at", atDay = 1, atHour = "8", atMinute = "30", atPm = true },
}
F.sync_start(form)
local sent = F.payload(form, ALL)

-- The view the server answers with (the fields the wizard reads).
local view = {
	summary = {
		name = sent.name,
		format = sent.format,
		visibility = sent.visibility,
		maxPlayers = sent.maxPlayers,
		startsAt = sent.startsAt,
		checkInAt = sent.startsAt - sent.checkInMinutes * 60000,
		official = sent.official,
		requireRanked = sent.requireRanked,
		status = "registration",
	},
	description = sent.description,
	formatOptions = sent.formatOptions,
	seeding = sent.seeding,
	rounds = sent.rounds,
	timetable = sent.timetable,
}

local back = F.from_view(view, NOW, ALL)
check("settings back", back.name == "Friday Weekly" and back.format == "double_elim" and back.grandFinalReset == false and back.requireRanked and back.checkInMinutes == 20)
check("pool back", back.poolDecks and #back.poolDecks == 2 and back.draftStakes[3] == 11 and back.poolCocktails[1].name == "Mix")
check("round back", back.rounds.R1.deckKind == "locked" and back.rounds.R1.cocktail.decks[1] == "b_red" and back.rounds.FINAL.bestOf == 7)
check("timing back", back.timing.FINAL.start == "at" and back.timing.FINAL.atDay == 1 and back.timing.FINAL.atHour == "8" and back.timing.FINAL.atPm == true and back.timing.LOSERS_FINAL.onward == true)
check("description back", back.description == "Line one\nLine two")

-- Nothing changed: nothing to send.
local again = F.payload(back, ALL)
local diff = F.changes(sent, again)
local keys = {}
for k in pairs(diff or {}) do
	keys[#keys + 1] = k
end
check("round trip", diff == nil, table.concat(keys, ","))

-- One change: only that field.
back.maxPlayers = 64
local one = F.changes(sent, F.payload(back, ALL))
check("one change", one and one.maxPlayers == 64 and one.name == nil and one.startsAt == nil)

-- Running: only name, description and round settings go.
back.name = "Renamed"
back.rounds.R2 = { bestOf = 3 }
local running = F.changes(sent, F.payload(back, ALL), true)
check("running", running.name == "Renamed" and running.rounds and running.maxPlayers == nil)

-- Switching things off still says so.
back.checkInMinutes = false
local off = F.changes(sent, F.payload(back, ALL))
check("check-in off", off.checkInMinutes == false)
local rr = F.new(NOW)
rr.name, rr.format, rr.groupSize = "Groups", "round_robin", 4
local with_groups = F.payload(rr, ALL)
rr.groupSize = false
local one_group = F.changes(with_groups, F.payload(rr, ALL))
check("one group", type(one_group.formatOptions) == "table" and next(one_group.formatOptions) == nil)

-- A pool of every deck reads as "every deck".
local every = F.from_view({ summary = { startsAt = NOW + 7200000 }, rounds = { defaults = { deck = { kind = "draft", decks = ALL, stakes = { 1 }, banOrder = "random" } } } }, NOW, ALL)
check("every deck", every.poolDecks == nil and every.deckKind == "draft")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("edit_test: all passed")
