-- Run from the repo root: lua5.4 tests/template_test.lua
-- lib/template.lua: saving a wizard form as a template and loading it back.
dofile("lib/text.lua")
dofile("lib/form.lua")
dofile("lib/template.lua")
local F, T = TOM.Form, TOM.Template

local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end

local NOW = os.time({ year = 2027, month = 3, day = 10, hour = 15, min = 0, sec = 0 }) * 1000

-- A weekly: double elimination, odd/even round decks, a pool with a Cocktail.
local form = F.new(NOW)
form.name = "Friday Weekly"
form.format = "double_elim"
form.maxPlayers = 32
form.checkInMinutes = false
form.deckKind = "draft"
form.draftStakes = { 1, 5, 11 }
form.poolDecks = { "b_red", "b_mp_orange" }
form.poolCocktails = { { name = "Mix", decks = { "b_black", "b_blue" } } }
form.rounds = { R1 = { deckKind = "locked", deck = "b_mp_orange", stake = 4 }, FINAL = { bestOf = 5, gameMode = false } }
form.hour, form.minute, form.pm = "8", "30", true
form.previewPlayers = 8

local t = T.from_form(form)
check("kind", t.kind == T.KIND and t.version == 1 and t.name == "Friday Weekly")
check("no date", t.form.date == nil and t.form.startsAt == nil and t.form.previewPlayers == nil)
-- Saved, then changed: the template is a copy.
form.rounds.R1.stake = 8
check("copied", t.form.rounds.R1.stake == 4)

local loaded, skipped = T.to_form(t, NOW)
check("loads", loaded ~= nil and skipped == 0, skipped)
check("settings", loaded.name == "Friday Weekly" and loaded.format == "double_elim" and loaded.maxPlayers == 32 and loaded.checkInMinutes == false)
check("pool", loaded.poolDecks[2] == "b_mp_orange" and loaded.draftStakes[3] == 11 and loaded.poolCocktails[1].decks[2] == "b_blue")
check("rounds", loaded.rounds.R1.deck == "b_mp_orange" and loaded.rounds.FINAL.bestOf == 5 and loaded.rounds.FINAL.gameMode == false)
-- 8:30 PM today (it's 3 PM).
local at = os.date("*t", math.floor(loaded.startsAt / 1000))
check("time today", at.day == 10 and at.hour == 20 and at.min == 30, at.day .. " " .. at.hour .. ":" .. at.min)
check("valid", #F.problems(loaded, NOW) == 0, F.problems(loaded, NOW)[1])
-- At 9 PM it's tomorrow's 8:30 PM.
local later = T.to_form(t, NOW + 6 * 3600 * 1000)
check("time tomorrow", os.date("*t", math.floor(later.startsAt / 1000)).day == 11)
-- "Every deck" stays every deck.
form.poolDecks = nil
check("every deck", T.to_form(T.from_form(form), NOW).poolDecks == nil)

-- Bad files.
check("not a template", T.to_form({ kind = "other" }, NOW) == nil)
check("newer", T.to_form({ kind = T.KIND, version = 99, form = {} }, NOW) == nil)
local broken, n = T.to_form({ kind = T.KIND, version = 1, form = { maxPlayers = "lots", format = "swiss", draftStakes = { "x", 2, true }, rounds = { R1 = { bestOf = "three", deck = "b_red" }, [5] = {} }, hour = 7 } }, NOW)
check("broken fields skipped", broken.maxPlayers == 16 and broken.format == "swiss" and broken.draftStakes[1] == 1 and n == 3, n)
check("broken round cleaned", broken.rounds.R1.bestOf == nil and broken.rounds.R1.deck == "b_red" and broken.rounds[5] == nil)

-- An old template's "Unset" decks load as ban and pick.
local old = T.to_form({ kind = T.KIND, version = 1, form = { name = "Old", deckKind = "any" } }, NOW)
check("old unset", old.deckKind == "draft")

-- File names.
check("file name", T.file_name("Friday Weekly!") == "Friday Weekly.json", T.file_name("Friday Weekly!"))
check("empty file name", T.file_name("  ??? ") == "template.json")
check("long file name", #T.file_name(string.rep("a", 80)) == 45)

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("template_test: all passed")
