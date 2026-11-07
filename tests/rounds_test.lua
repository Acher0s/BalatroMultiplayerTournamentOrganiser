-- Run from the repo root: lua5.4 tests/rounds_test.lua
-- lib/form.lua's rounds: the plan for a player count, layering, overrides.
dofile("lib/text.lua")
dofile("lib/form.lua")
local F = TOM.Form

local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. tostring(detail)) or ""))
	end
end

local function names(plan)
	local out = {}
	for _, r in ipairs(plan) do
		out[#out + 1] = table.concat(r.names, "+")
	end
	return table.concat(out, ",")
end

local form = F.new(1800000000000)
form.name = "Weekly"

-- Single elimination: rounds and names, same as the server's.
check("se 16", names(F.round_plan(form, 16)) == ",QUARTER,SEMI,FINAL", names(F.round_plan(form, 16)))
check("se 13", #F.round_plan(form, 13) == 4)
check("se 5", names(F.round_plan(form, 5)) == "QUARTER,SEMI,FINAL", names(F.round_plan(form, 5)))
check("se 2", names(F.round_plan(form, 2)) == "FINAL")

-- Double elimination, 8 players: W1 | W2+L1 | L2 | W3+L3 | L4 | GF | reset.
form.format = "double_elim"
form.grandFinalReset = true
check("de 8", names(F.round_plan(form, 8)) == ",,,WINNERS_FINAL,LOSERS_FINAL,FINAL,FINAL", names(F.round_plan(form, 8)))
form.grandFinalReset = false
check("de 8 no reset", #F.round_plan(form, 8) == 6)
check("de 16", #F.round_plan(form, 16) == 8)

-- Round robin and Swiss: numbered only.
form.format = "round_robin"
form.groupSize = false
check("rr 8", #F.round_plan(form, 8) == 7)
check("rr 7", #F.round_plan(form, 7) == 7)
form.groupSize = 4
check("rr groups of 4", #F.round_plan(form, 16) == 3)
form.format = "swiss"
form.swissRounds = false
check("swiss auto", #F.round_plan(form, 16) == 4)
form.swissRounds = 7
check("swiss capped", #F.round_plan(form, 5) == 4)

-- The weekly: odd rounds one deck, even rounds another, the final best of 5.
form.format = "single_elim"
form.maxPlayers = 32
form.rounds = {
	R1 = { deckKind = "locked", deck = "b_red", stake = 4 },
	R2 = { deckKind = "locked", deck = "b_black", stake = 7 },
	R3 = { deckKind = "locked", deck = "b_red", stake = 4 },
	FINAL = { bestOf = 5 },
}
local plan = F.round_plan(form, 8)
local final = F.effective(form, plan[3])
check("final keeps round 3's deck", final.deckKind == "locked" and final.deck == "b_red" and final.stake == 4)
check("final best of 5", final.bestOf == 5)
local r2 = F.effective(form, plan[2])
check("round 2", r2.deck == "b_black" and r2.stake == 7 and r2.bestOf == 3)
check("describe", F.describe(r2, form) == "b_black on Orange", F.describe(r2, form))
check("describe same", F.describe(F.effective(form, { n = 9, names = {} }), form) == "same as the defaults")

-- Overrides: only keys the format and player limit allow; empty rounds left out.
form.rounds.R9 = { bestOf = 7 } -- 32 players: 5 rounds
form.rounds.LOSERS_FINAL = { bestOf = 7 } -- not single elimination
form.rounds.R5 = {}
local o = F.payload(form, { "b_red" }).rounds.overrides
check("overrides kept", o.R1 and o.R2 and o.R3 and o.FINAL)
check("overrides dropped", not o.R9 and not o.LOSERS_FINAL and not o.R5)
check("locked deck", o.R2.deck.kind == "locked" and o.R2.deck.deck == "b_black" and o.R2.deck.stake == 7 and o.R2.bestOf == nil)
check("final only best of", o.FINAL.bestOf == 5 and o.FINAL.deck == nil)
form.rounds = {}
check("no overrides", F.payload(form).rounds.overrides == nil)

-- A ban-and-pick round needs a stake.
form.rounds.R2 = { deckKind = "draft", draftStakes = {}, banOrder = "random" }
check("draft round problem", #F.problems(form, 1800000000000, "rounds") == 1)
form.rounds.R2.draftStakes = { 11, 9 }
check("draft round fine", #F.problems(form, 1800000000000, "rounds") == 0)
local d = F.payload(form, { "b_red", "b_blue" }).rounds.overrides.R2.deck
check("draft round", d.kind == "draft" and d.stakes[1] == 9 and d.stakes[2] == 11 and #d.decks == 2)

-- The round editor: a field never set reads "Same as defaults", and stepping
-- from it moves to the first real choice.
local editor_list = { { false, "Same as defaults" }, { 1, "Best of 1" }, { 3, "Best of 3" } }
local fresh = {}
check("unset is same", F.label(fresh, "bestOf", editor_list) == "Same as defaults", F.label(fresh, "bestOf", editor_list))
F.step(fresh, "bestOf", 1, editor_list)
check("step from unset", fresh.bestOf == 1, tostring(fresh.bestOf))
F.step(fresh, "bestOf", -1, editor_list)
check("back to same", fresh.bestOf == false and F.round_override(fresh) == nil)

-- The Cocktail: locked to it, or in the pool, it needs its decks.
local c = F.new(1800000000000)
c.name = "Cocktail Cup"
c.deckKind, c.deck, c.stake = "locked", F.COCKTAIL, 6
check("cocktail needs decks", (F.problems(c, 1800000000000, "games")[1] or ""):find("Cocktail") ~= nil)
c.cocktail = { name = "  Friday Mix ", decks = { "b_abandoned", "b_erratic", "b_checkered" } }
check("cocktail fine", #F.problems(c, 1800000000000) == 0, F.problems(c, 1800000000000)[1])
local cd = F.payload(c).rounds.defaults.deck
check("cocktail locked", cd.deck == F.COCKTAIL and cd.stake == 6 and cd.cocktail.name == "Friday Mix" and #cd.cocktail.decks == 3)
c.cocktail.name = ""
check("cocktail no name", F.payload(c).rounds.defaults.deck.cocktail.name == nil)
c.deck = "b_red"
check("other deck no recipe", F.payload(c).rounds.defaults.deck.cocktail == nil)
-- Ban and pick: every deck until the pool is changed, Cocktails as items.
c.deckKind, c.draftStakes = "draft", { 1 }
local pd = F.payload(c, { "b_red", "b_blue" }).rounds.defaults.deck
check("pool every deck", #pd.decks == 2 and pd.cocktails == nil)
check("pool text", F.pool_text(c) == "every deck, 1 stake", F.pool_text(c))
c.poolDecks = { "b_mp_orange" }
c.poolCocktails = { { name = "", decks = { "b_red", "b_blue" } }, { name = "Mix", decks = { "b_black" } } }
pd = F.payload(c, { "b_red", "b_blue" }).rounds.defaults.deck
check("pool chosen", #pd.decks == 1 and pd.decks[1] == "b_mp_orange" and #pd.cocktails == 2 and pd.cocktails[2].name == "Mix")
check("pool text 2", F.pool_text(c) == "1 deck + 2 Cocktails, 1 stake", F.pool_text(c))
c.poolCocktails[2].decks = {}
check("pool cocktail needs decks", (F.problems(c, 1800000000000, "games")[1] or ""):find("mixes nothing") ~= nil)
c.poolCocktails = {}
c.poolDecks = {}
check("empty pool", (F.problems(c, 1800000000000, "games")[1] or ""):find("deck pool is empty") ~= nil)
c.poolDecks = nil
c.draftStakes = {}
check("no stakes", (F.problems(c, 1800000000000, "games")[1] or ""):find("stake pool") ~= nil)
c.draftStakes = { 1 }
-- A round copies the defaults' pool, then changes its own.
local copied = F.copy_pool({ poolDecks = { "b_red" }, draftStakes = { 2 }, poolCocktails = { { name = "A", decks = { "b_blue" } } } }, {})
copied.poolCocktails[1].decks[1] = "b_green"
check("copy is deep", copied.poolDecks[1] == "b_red" and copied.draftStakes[1] == 2 and copied.poolCocktails[1].name == "A")
-- A round with its own Cocktail.
c.cocktail.decks = { "b_red" }
c.rounds = { R2 = { deckKind = "locked", deck = F.COCKTAIL, stake = 8, cocktail = { name = "", decks = {} } } }
check("round cocktail needs decks", #F.problems(c, 1800000000000, "rounds") == 1)
c.rounds.R2.cocktail.decks = { "b_mp_orange", "b_black" }
local r2 = F.payload(c, { "b_red" }).rounds.overrides.R2.deck
check("round cocktail", r2.deck == F.COCKTAIL and r2.cocktail.decks[1] == "b_mp_orange")
check("round effective", F.effective(c, { n = 2, names = {} }).cocktail == c.rounds.R2.cocktail)

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("rounds_test: all passed")
