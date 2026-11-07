-- Run from the repo root: lua5.4 tests/timing_test.lua
-- lib/form.lua's timetable round by round, and templates keeping it.
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
local form = F.new(NOW)
form.name = "League with live finals"
form.preset = "league"
form.maxPlayers = 16

check("nothing", F.payload(form).timetable.rounds == nil)
check("describe nothing", F.describe_timing(nil) == "as the timetable")

form.timing = {
	R3 = { breakBefore = 15 },
	SEMI = { play = "live", readyUpMinutes = 10, onward = true },
	FINAL = { start = "manual", breakBefore = false, play = false },
	R2 = { onward = true }, -- "every later round" with nothing to carry
	R9 = { breakBefore = 30 }, -- 16 players: 4 rounds
	LOSERS_FINAL = { breakBefore = 5 }, -- not double elimination
}
local r = F.payload(form).timetable.rounds
check("break", r.R3.breakBefore == 15 and r.R3.play == nil and r.R3.onward == nil)
check("onward live", r.SEMI.play.kind == "live" and r.SEMI.play.readyUpMinutes == 10 and r.SEMI.onward == true)
check("manual", r.FINAL.manualStart == true and r.FINAL.breakBefore == nil)
check("dropped", r.R2 == nil and r.R9 == nil and r.LOSERS_FINAL == nil)
form.timing.R2 = { play = "window", windowMinutes = 2 * 24 * 60 }
check("window", F.payload(form).timetable.rounds.R2.play.durationMinutes == 2 * 24 * 60)
check("describe", F.describe_timing(form.timing.SEMI, form) == "live, 10 min to ready up; and every later round", F.describe_timing(form.timing.SEMI, form))
check("describe break", F.describe_timing(form.timing.R3, form) == "15 min break first", F.describe_timing(form.timing.R3, form))

-- Continuing at a date and time: days after the start day, local time.
form.timing.FINAL = { start = "at", atDay = 1, atHour = "8", atMinute = "00", atPm = true }
local d = form.date
local expected = os.time({ year = d.year, month = d.month, day = d.day + 1, hour = 20, min = 0, sec = 0 }) * 1000
check("at", F.payload(form).timetable.rounds.FINAL.startAt == expected and F.payload(form).timetable.rounds.FINAL.manualStart == nil)
check("describe at", (F.describe_timing(form.timing.FINAL, form)):find("^continues ") ~= nil, F.describe_timing(form.timing.FINAL, form))
check("at days", #F.at_days(form) == F.AT_DAYS_MAX + 1 and F.at_days(form)[1][2]:find("start day") ~= nil)
check("at fine", #F.problems(form, NOW, "schedule") == 0, F.problems(form, NOW, "schedule")[1])
form.timing.FINAL.atHour = "13"
check("at bad hour", (F.problems(form, NOW, "schedule")[1] or ""):find("hour") ~= nil)
form.timing.FINAL.atHour, form.timing.FINAL.atDay, form.timing.FINAL.atPm = "1", 0, false
check("at before start", (F.problems(form, NOW, "schedule")[1] or ""):find("before the tournament") ~= nil)
form.timing.FINAL = { start = "at", atDay = 1, atHour = "8", atMinute = "00", atPm = true }

-- Its own check-in: sent only with a date and time, and opening after the start.
form.timing.FINAL.checkInMinutes = 30
check("check-in sent", F.payload(form).timetable.rounds.FINAL.checkInMinutes == 30)
check("describe check-in", (F.describe_timing(form.timing.FINAL, form)):find("check%-in 30 min before") ~= nil, F.describe_timing(form.timing.FINAL, form))
form.timing.SEMI.start = "manual"
form.timing.SEMI.checkInMinutes = 30
check("check-in needs a time", F.payload(form).timetable.rounds.SEMI.checkInMinutes == nil)
form.timing.SEMI.start, form.timing.SEMI.checkInMinutes = nil, nil
local start = F.payload(form).startsAt
form.timing.FINAL = { start = "at", atDay = 0, atMinute = "30", checkInMinutes = 60 }
local st = os.date("*t", math.floor(start / 1000))
form.timing.FINAL.atHour = tostring(st.hour % 12 == 0 and 12 or st.hour % 12)
form.timing.FINAL.atPm = st.hour >= 12
check("check-in before start", table.concat(F.problems(form, NOW, "schedule"), "|"):find("check%-in can't open") ~= nil, table.concat(F.problems(form, NOW, "schedule"), "|"))
-- In round order: the semifinals can't be after the final.
form.timing.FINAL = { start = "at", atDay = 1, atHour = "8", atMinute = "00", atPm = true }
form.timing.SEMI = { start = "at", atDay = 2, atHour = "8", atMinute = "00", atPm = true }
check("out of order", table.concat(F.problems(form, NOW, "schedule"), "|"):find("round order") ~= nil)
form.timing.SEMI = { play = "live", readyUpMinutes = 10, onward = true }

-- Templates keep it.
local loaded = T.to_form(T.from_form(form), NOW)
check("template", loaded.timing.SEMI.play == "live" and loaded.timing.FINAL.start == "at" and loaded.timing.FINAL.atDay == 1 and loaded.timing.R3.breakBefore == 15)

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("timing_test: all passed")
