-- Run from the repo root: lua5.4 tests/form_test.lua
-- lib/form.lua: the create wizard's choices, checks and payload.
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

local HOUR = 3600 * 1000
local NOW = 1800000000000 + 17 * 60 * 1000 -- 17 minutes past an hour

-- Defaults: starts on a whole hour, more than an hour away.
local form = F.new(NOW)
check("start whole hour", form.startsAt % HOUR == 0)
check("start an hour away", form.startsAt >= NOW + HOUR and form.startsAt < NOW + 2 * HOUR)

-- Only the name is missing at first.
local problems = F.problems(form, NOW)
check("name missing", #problems == 1 and problems[1]:find("name"), problems[1])
form.name = "  Friday Cup  "
check("fine now", #F.problems(form, NOW) == 0)
check("problems per step", #F.problems({ name = "", description = "", startsAt = NOW + HOUR, format = "swiss", maxPlayers = 8, deckKind = "draft", draftStakes = { 1 } }, NOW, "format") == 0)

-- Choices wrap both ways.
F.step(form, "format", -1)
check("wrap back", form.format == "swiss", form.format)
F.step(form, "format", 1)
check("wrap forward", form.format == "single_elim", form.format)
check("label", F.label(form, "bestOf") == "Best of 3")

-- The start as date + hour + minutes + AM/PM (local time; the test runs in UTC).
check("split", form.date and form.hour and form.minute and form.pm ~= nil)
local before = form.startsAt
check("round trip", F.start_from_fields(form) == before)
form.date = { year = 2027, month = 3, day = 14 }
form.hour, form.minute, form.pm = "12", "05", false -- 12:05 AM
check("midnight", F.start_from_fields(form) == os.time({ year = 2027, month = 3, day = 14, hour = 0, min = 5, sec = 0 }) * 1000)
form.hour, form.pm = "12", true -- 12:05 PM
check("noon", F.start_from_fields(form) == os.time({ year = 2027, month = 3, day = 14, hour = 12, min = 5, sec = 0 }) * 1000)
form.hour, form.minute, form.pm = "7", "30", true
check("evening", F.start_from_fields(form) == os.time({ year = 2027, month = 3, day = 14, hour = 19, min = 30, sec = 0 }) * 1000)
for _, bad in ipairs({ { "13", "00" }, { "0", "00" }, { "", "00" }, { "7", "60" }, { "7", "x" } }) do
	form.hour, form.minute = bad[1], bad[2]
	check("bad time " .. bad[1] .. ":" .. bad[2], F.start_from_fields(form) == nil)
end
form.hour, form.minute = "7", "30"
-- Problems re-read the fields: a past date or a bad hour is refused.
form.date = os.date("*t", math.floor(NOW / 1000) - 86400)
check("past", #F.problems(form, NOW, "basics") == 1)
form.hour = "13"
check("bad hour named", (F.problems(form, NOW, "basics")[1] or ""):find("hour") ~= nil)
form.startsAt = NOW + 2 * HOUR
F.split_start(form)
check("fine again", #F.problems(form, NOW) == 0, F.problems(form, NOW)[1])
form.date = os.date("*t", math.floor((NOW + 91 * 24 * HOUR) / 1000))
check("too far", #F.problems(form, NOW) == 1)
form.startsAt = NOW + 2 * HOUR
F.split_start(form)

-- The calendar: Monday first. March 2027 starts on a Monday, Feb 2027 on a Monday too, Nov 2026 on a Sunday.
local march = F.month_grid(2027, 3)
check("march first", march[1][1] == 1 and march[#march][3] == 31 and march[#march][4] == false)
local nov = F.month_grid(2026, 11)
check("november", nov[1][6] == false and nov[1][7] == 1 and #nov == 6 and nov[6][1] == 30)
check("february", #F.month_grid(2027, 2) == 4)
local today = os.date("*t", math.floor(NOW / 1000))
check("today allowed", F.day_allowed(today.year, today.month, today.day, NOW))
check("yesterday not", not F.day_allowed(today.year, today.month, today.day - 1, NOW))
check("91 days not", not F.day_allowed(today.year, today.month, today.day + 91, NOW))

-- Payloads.
local p = F.payload(form)
check("name trimmed", p.name == "Friday Cup", p.name)
check("single elim no options", p.formatOptions == nil)
check("check-in", p.checkInMinutes == 30)
check("ranked off", p.requireRanked == false)
form.requireRanked = true
check("ranked on", F.payload(form).requireRanked == true)
form.requireRanked = false
check("defaults", p.rounds.defaults.gameMode == "pvp_nemesis" and p.rounds.defaults.bestOf == 3)
-- By default: ban and pick from every deck on White to Gold.
check("default decks", p.rounds.defaults.deck.kind == "draft" and #p.rounds.defaults.deck.stakes == 8)
check("live event options", p.timetable.preset == "live_event" and p.timetable.options.readyUpMinutes == 10 and p.timetable.options.breakMinutes == 0)

form.checkInMinutes = false
check("no check-in", F.payload(form).checkInMinutes == nil)

form.format = "double_elim"
form.grandFinalReset = false
check("double elim reset", F.payload(form).formatOptions.grandFinalReset == false)

form.format = "round_robin"
form.groupSize = 4
check("groups", F.payload(form).formatOptions.groupSize == 4)
form.maxPlayers = 4
form.groupSize = 8
check("group too big", #F.problems(form, NOW, "format") == 1)
form.groupSize = false
check("one group", F.payload(form).formatOptions == nil)

form.format = "swiss"
form.swissRounds = 5
check("swiss rounds", F.payload(form).formatOptions.swissRounds == 5)

form.deckKind = "locked"
form.deck, form.stake = "b_blue", 4
local d = F.payload(form).rounds.defaults.deck
check("locked deck", d.kind == "locked" and d.deck == "b_blue" and d.stake == 4)

form.deckKind = "draft"
form.draftStakes = { 3, 1 }
form.banOrder = "random"
d = F.payload(form, { "b_red", "b_blue" }).rounds.defaults.deck
check("draft", d.kind == "draft" and #d.decks == 2 and d.stakes[1] == 1 and d.stakes[2] == 3 and d.banOrder == "random")
form.draftStakes = {}
check("draft needs a stake", #F.problems(form, NOW, "games") == 1)

form.preset = "league"
form.windowMinutes = 3 * 24 * 60
local o = F.payload(form).timetable.options
check("league", o.windowMinutes == 3 * 24 * 60 and o.readyUpMinutes == nil)
check("uses", F.uses(form, "windowMinutes") and not F.uses(form, "readyUpMinutes") and F.uses(form, "banOrder") and not F.uses(form, "stake"))

form.preset = "live_fixed_rounds"
o = F.payload(form).timetable.options
check("fixed rounds", o.readyUpMinutes == 10 and o.breakMinutes == nil)

-- The description editor's lines.
local lines = F.split_description("Prizes: 50k\nRules in our Discord")
check("split lines", #lines == F.DESC_LINES and lines[1] == "Prizes: 50k" and lines[2] == "Rules in our Discord" and lines[3] == "")
check("join", F.join_description(lines) == "Prizes: 50k\nRules in our Discord")
check("join drops empty end", F.join_description({ "a", "", "b", "", "" }) == "a\n\nb")
local long = string.rep("word ", 30) -- 150 characters
local split = F.split_description(long)
check("long split at a space", #split[1] <= F.DESC_LINE and split[2] ~= "" and not split[2]:match("^ "), split[2])
check("empty", F.join_description(F.split_description("")) == "")
-- The notice board: 3 lines of 100.
local notice = F.split_description("Finals on stream\nat 9 PM", 3, 100)
check("notice split", #notice == 3 and notice[1] == "Finals on stream" and notice[2] == "at 9 PM" and notice[3] == "")
check("notice join", F.join_description(notice, 3) == "Finals on stream\nat 9 PM")
local short_lines = F.split_description(string.rep("word ", 30), 2, 40)
check("narrow split", #short_lines == 2 and #short_lines[1] <= 40)

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("form_test: all passed")
