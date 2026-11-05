-- The create wizard (page tom_create): BASICS, FORMAT, GAMES, SCHEDULE,
-- REVIEW. The form lives in TOM.Form (lib/form.lua); NEXT is refused while
-- the step has problems. CREATE makes the tournament, opens registration and
-- goes to its manage page.

local F = TOM.Form
local UI = TOM.UI

local wizard = { form = nil, step = 1, error = nil, busy = false, el = nil, lists = {}, start_note = { text = "", colour = { 1, 1, 1, 1 } } }

-- The line under the start time, from what is in the boxes right now: how
-- long until then, or what is wrong with it. Updated a few times a second
-- (typing in a box doesn't rebuild the page).
local function update_start_note()
	local form = wizard.form
	if not form or not form.date then
		return
	end
	local at, why = F.start_from_fields(form)
	if not at then
		PVP.TUI.set_live(wizard.start_note, why, G.C.RED)
		return
	end
	local now = PVP.TournamentTime.now_ms()
	if at < now + 5 * 60 * 1000 then
		PVP.TUI.set_live(wizard.start_note, "That's too soon: at least 5 minutes from now.", G.C.RED)
		return
	end
	local left = PVP.TournamentTime.countdown(at)
	PVP.TUI.set_live(wizard.start_note, (left and ("in " .. left .. ", ") or "") .. "your local time", G.C.UI.TEXT_INACTIVE)
end

local function TUI()
	return PVP.TUI
end

local function TT()
	return PVP.TournamentTime
end

-- Lists that come from the game or PvP (not fixed in lib/form.lua).
local function make_lists()
	local modes = {}
	for _, key in ipairs(F.GAME_MODES) do
		if PVP.PVP_GAMEMODES and PVP.PVP_GAMEMODES[key] then
			modes[#modes + 1] = { key, TUI().game_type(key) }
		end
	end
	local rulesets = {}
	local order = { "BALANCED", "VANILLA", "EXPANDED", "SMALLWORLD", "EXPERIMENTAL", "MAJORLEAGUE" }
	for _, name in ipairs(order) do
		local key = PVP.RulesetKey and PVP.RulesetKey[name]
		if key and MPAPI.Rulesets and MPAPI.Rulesets[key] then
			rulesets[#rulesets + 1] = { key, TUI().ruleset_name(key) }
		end
	end
	local decks = {}
	for _, key in ipairs(UI.decks()) do
		decks[#decks + 1] = { key, UI.deck_name(key) }
	end
	if UI.has_cocktail() then
		decks[#decks + 1] = { F.COCKTAIL, UI.deck_name(F.COCKTAIL) }
	end
	return { gameMode = modes, ruleset = rulesets, deck = decks, stake = UI.stakes() }
end

local PRESET_NOTES = {
	live_event = { "Each match opens as soon as", "both of its players are known." },
	live_fixed_rounds = { "Every round waits for you to press", "START ROUND on the manage page." },
	league = { "Each round has a deadline; players", "play their match any time before it." },
}

local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }
local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

-- "Fri, Nov 7, 2026"
local function date_text(d)
	local t = os.date("*t", os.time({ year = d.year, month = d.month, day = d.day, hour = 12 }))
	return string.format("%s, %s %d, %d", WEEKDAYS[t.wday], MONTHS[t.month]:sub(1, 3), t.day, t.year)
end

-- Date (opens the calendar), hour : minutes, AM/PM; all in local time.
local function start_row()
	local form = wizard.form
	local small = function(node)
		return { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { node } }
	end
	return {
		UI.row("Starts", {
			{
				n = G.UIT.C,
				config = { align = "cm", minw = 3.3, minh = 0.5, r = 0.08, colour = G.C.BLUE, hover = true, shadow = true, button = "tom_cal_open" },
				nodes = { TUI().text(date_text(form.date), 0.3) },
			},
			TUI().spacer(0.15),
			small(UI.text_box("tom_create_hour", "hour", { max_length = 2, w = 0.75, charset = "digits" })),
			small(TUI().text(":", 0.4)),
			small(UI.text_box("tom_create_minute", "minute", { max_length = 2, w = 0.75, charset = "digits" })),
			{
				n = G.UIT.C,
				config = { align = "cm", minw = 0.9, minh = 0.5, r = 0.08, colour = G.C.UI.BACKGROUND_INACTIVE, hover = true, shadow = true, button = "tom_create_ampm" },
				nodes = { TUI().text(form.pm and "PM" or "AM", 0.32) },
			},
		}),
		{ n = G.UIT.R, config = { align = "cl", padding = 0.02 }, nodes = { { n = G.UIT.C, config = { minw = UI.LABEL_W } }, TUI().live_text(wizard.start_note, TUI().SMALL) } },
	}
end

local function step_rows(key)
	local form = wizard.form
	local rows = {}
	local function add(row)
		rows[#rows + 1] = row
	end
	if key == "basics" then
		add(UI.input("Name", "tom_create_name", "name", { prompt = "Tournament name", max_length = 48 }))
		add(UI.input("Description", "tom_create_desc", "description", { prompt = "Optional: prizes, rules, Discord link...", max_length = 100 }))
		add(UI.choice("Who can join", "visibility", nil, { "Public: listed in Browse for everyone.", "Private: hidden; players join with", "the invite code on the manage page." }))
		if UI.may_create_official() then
			add(UI.switch("Official", "official", { "Shown with a gold OFFICIAL badge", "and listed first. Only players with", "the right to host them see this." }))
		end
		add(UI.choice("Players", "maxPlayers", nil, { "The most players who can join.", "Anyone after that goes on a waitlist;", "you move them in from the manage page." }))
		for _, r in ipairs(start_row()) do
			add(r)
		end
		add(UI.choice("Check-in", "checkInMinutes", nil, { "Players press CHECK IN in the minutes", "before the start to say they're there.", "Anyone who doesn't is left out", "of the bracket when it starts." }))
	elseif key == "format" then
		add(UI.choice("Format", "format"))
		if F.uses(form, "grandFinalReset") then
			add(UI.choice("Grand final reset", "grandFinalReset", nil, { "If the player from the losers bracket", "wins the grand final, both have lost", "once: play one more match to decide." }))
		elseif F.uses(form, "groupSize") then
			add(UI.choice("Groups", "groupSize", nil, { "Everyone plays everyone else", "in their group once." }))
		elseif F.uses(form, "swissRounds") then
			add(UI.choice("Rounds", "swissRounds", nil, { "Each round pairs players with the", "same score who haven't met yet.", "Automatic: enough rounds for", "one clear winner." }))
		end
		add(UI.choice("Seeding", "seeding", nil, { "Who is seed 1, 2, 3... Top seeds", "meet each other as late as possible.", "I set the order: arrange the players", "on the manage page before it starts." }))
	elseif key == "games" then
		add(UI.choice("Game type", "gameMode", "gameMode"))
		add(UI.choice("Ruleset", "ruleset", "ruleset"))
		add(UI.choice("Series", "bestOf", nil, { "How many games a match has:", "best of 3 = first to win 2." }))
		add(UI.choice("Decks & stakes", "deckKind", nil, { "Players pick: the lobby's usual deck", "choice. One deck: everyone plays the", "same deck and stake. Ban and pick:", "players take turns banning from a", "pool of decks and stakes." }))
		if F.uses(form, "deck") then
			add(UI.choice("Deck", "deck", "deck"))
			add(UI.choice("Stake", "stake", "stake"))
		elseif F.uses(form, "banOrder") then
			add(TOM.Pools.row(form, function()
				if wizard.el then
					wizard.el:update()
				end
			end))
			add(UI.choice("Ban order", "banOrder", nil, { "Who bans first in each match." }))
		end
		if UI.has_cocktail() then
			for _, r in ipairs(UI.cocktail_rows(form, function()
				if wizard.el then
					wizard.el:update()
				end
			end)) do
				add(r)
			end
		end
	elseif key == "rounds" then
		local context = {
			form = form,
			lists = wizard.lists,
			rebuild = function()
				if wizard.el then
					wizard.el:update()
				end
			end,
			say = function(text)
				wizard.error = text
				if wizard.el then
					wizard.el:update()
				end
			end,
		}
		for _, r in ipairs(TOM.RoundsStep.rows(context)) do
			add(r)
		end
	elseif key == "schedule" then
		add(UI.choice("Timetable", "preset", nil, PRESET_NOTES[form.preset]))
		if F.uses(form, "readyUpMinutes") then
			add(UI.choice("Time to ready up", "readyUpMinutes", nil, { "Once a match opens, both players", "have this long to press READY.", "A player who isn't ready in time", "loses the match." }))
		end
		if F.uses(form, "breakMinutes") then
			add(UI.choice("Breaks", "breakMinutes", nil, { "A pause between rounds. With a break,", "the next round waits until every", "match of the round before is done." }))
		end
		if F.uses(form, "windowMinutes") then
			add(UI.choice("Time per round", "windowMinutes", nil, { "Players arrange a time themselves", "and play before the round's deadline." }))
		end
	elseif key == "review" then
		local lists = wizard.lists
		local function line(label, value)
			add(UI.row(label, { TUI().text(value, TUI().TEXT) }))
		end
		line("Name", form.name ~= "" and form.name or "-")
		line("Who can join", F.label(form, "visibility") .. (form.official and ", OFFICIAL" or ""))
		line("Players", "up to " .. form.maxPlayers)
		line("Starts", TT().format_local(form.startsAt) .. "  (" .. F.label(form, "checkInMinutes"):lower() .. ")")
		local format = F.label(form, "format")
		if F.uses(form, "groupSize") and form.groupSize then
			format = format .. ", " .. F.label(form, "groupSize"):lower()
		elseif F.uses(form, "swissRounds") and form.swissRounds then
			format = format .. ", " .. form.swissRounds .. " rounds"
		end
		line("Format", format .. "; seeding " .. F.label(form, "seeding"):lower())
		line("Games", F.label(form, "gameMode", lists.gameMode) .. ", " .. F.label(form, "ruleset", lists.ruleset) .. ", " .. F.label(form, "bestOf"):lower())
		local decks = F.label(form, "deckKind")
		if F.uses(form, "deck") then
			decks = F.label(form, "deck", lists.deck) .. " on " .. F.label(form, "stake", lists.stake) .. " stake"
		elseif F.uses(form, "banOrder") then
			decks = "Ban and pick: " .. F.pool_text(form) .. "; " .. F.label(form, "banOrder"):lower()
		end
		line("Decks & stakes", decks)
		local changed = {}
		for _, k in ipairs(F.round_keys(form)) do
			if F.round_override(form.rounds[k]) then
				changed[#changed + 1] = k:match("^R(%d+)$") and ("round " .. k:sub(2)) or F.named_label(form.format, k):lower()
			end
		end
		line("Rounds", #changed == 0 and "all play the defaults" or ("changed: " .. table.concat(changed, ", ")))
		line("Timetable", F.label(form, "preset"))
		add(UI.note("Registration opens as soon as you create it. You can still cancel it."))
	end
	return rows
end

local function step_bar()
	local nodes = {}
	for i, s in ipairs(F.STEPS) do
		local current = i == wizard.step
		nodes[#nodes + 1] = {
			n = G.UIT.C,
			config = { align = "cm", padding = 0.03 },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "cm", minw = 1.85, minh = 0.45, r = 0.08, colour = current and G.C.PURPLE or G.C.UI.BACKGROUND_INACTIVE, hover = true, button = "tom_create_goto", ref_table = { step = i } },
					nodes = { TUI().text(i .. ". " .. s.title, 0.3, current and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) },
				},
			},
		}
	end
	return { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = nodes }
end

local function build()
	local form = wizard.form
	-- The hour and minute boxes change without a rebuild: read them now.
	F.sync_start(form)
	update_start_note()
	UI.target = { form = form, lists = wizard.lists, on_change = function()
		wizard.error = nil
		wizard.el:update()
	end }
	local step = F.STEPS[wizard.step]
	local last = wizard.step == #F.STEPS
	local body = {
		{
			n = G.UIT.R,
			config = { align = "cm", padding = 0.04 },
			nodes = {
				{ n = G.UIT.C, config = { align = "cl", minw = 3.4 }, nodes = { TUI().button("LOAD TEMPLATE", "tom_create_load_template", nil, G.C.UI.BACKGROUND_INACTIVE, 2.9, 0.28) } },
				{ n = G.UIT.C, config = { align = "cm", minw = 4.8 }, nodes = { TUI().text("NEW TOURNAMENT", 0.45, G.C.PURPLE) } },
				{ n = G.UIT.C, config = { align = "cr", minw = 3.4 }, nodes = { TUI().button("SAVE TEMPLATE", "tom_create_save_template", nil, G.C.UI.BACKGROUND_INACTIVE, 2.9, 0.28) } },
			},
		},
		step_bar(),
	}
	local form_rows = step_rows(step.key)
	body[#body + 1] = { n = G.UIT.R, config = { align = "tm", padding = 0.1, minh = 4.6, minw = 11.6, r = 0.1, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5) }, nodes = { { n = G.UIT.C, config = { align = "tl" }, nodes = form_rows } } }
	local problems = F.problems(form, TT().now_ms(), not last and step.key or nil)
	local message = wizard.error or (wizard.busy and "Creating...") or (last and problems[1]) or wizard.warning
	if message then
		body[#body + 1] = TUI().message(message, wizard.error and G.C.RED or G.C.UI.TEXT_INACTIVE)
	end
	local buttons = {
		TUI().button(wizard.step == 1 and "CANCEL" or "BACK", "tom_create_back", nil, G.C.ORANGE, 2.0),
		TUI().spacer(5.0),
	}
	if last then
		buttons[#buttons + 1] = TUI().button("CREATE", "tom_create_submit", nil, (#problems == 0 and not wizard.busy) and G.C.GREEN or G.C.UI.BACKGROUND_INACTIVE, 2.4)
	else
		buttons[#buttons + 1] = TUI().button("NEXT", "tom_create_next", nil, G.C.BLUE, 2.4)
	end
	body[#body + 1] = TUI().hbox(buttons, "cm", 0.05)
	return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = { TUI().panel(body, { align = "cm", minw = 12.4 }) } }
end

MPAPI.on_loaded(function()
	MPAPI.Page({
		key = "tom_create",
		category = "game_select",
		build = function(self)
			wizard.el = MPAPI.ui_element(build)
			return { n = G.UIT.ROOT, config = { align = "tm", colour = G.C.CLEAR }, nodes = { { n = G.UIT.R, config = { align = "tm", padding = 0.1 }, nodes = { wizard.el.node } } } }
		end,
		on_enter = function(self)
			PVP.TUI.page_enter()
			wizard.active = true
			wizard.gen = (wizard.gen or 0) + 1
			local gen = wizard.gen
			update_start_note()
			local function tick()
				G.E_MANAGER:add_event(Event({
					trigger = "after",
					delay = 0.2,
					timer = "REAL",
					blockable = false,
					blocking = false,
					func = function()
						if wizard.active and gen == wizard.gen then
							update_start_note()
							tick()
						end
						return true
					end,
				}))
			end
			tick()
		end,
		dispose = function(self)
			wizard.active = false
			TOM.RoundsStep.dispose()
		end,
	})
end)

-- Opens the wizard with a fresh form (or the one left half done).
function TOM.open_create(fresh)
	if fresh or not wizard.form then
		wizard.form = F.new(PVP.TournamentTime.now_ms())
		wizard.step = 1
	end
	wizard.error, wizard.warning, wizard.busy = nil, nil, false
	wizard.lists = make_lists()
	MPAPI.pages.show("tom_create", {})
end

local function rebuild()
	if wizard.el then
		wizard.el:update()
	end
end

-- Templates (ui/templates.lua).
G.FUNCS.tom_create_save_template = function()
	if not wizard.form then
		return
	end
	F.sync_start(wizard.form)
	TOM.Templates.open_save(wizard.form, function(text)
		wizard.warning = text
		rebuild()
	end)
end

G.FUNCS.tom_create_load_template = function()
	TOM.Templates.open_load(function(form, name, skipped)
		wizard.form = form
		wizard.step = 1
		wizard.error = nil
		wizard.warning = "Loaded the template " .. name .. (skipped and skipped > 0 and (" (" .. skipped .. " setting(s) it had were skipped)") or "") .. "."
		rebuild()
	end, function()
		rebuild()
	end)
end

G.FUNCS.tom_create_ampm = function()
	if wizard.form then
		wizard.form.pm = not wizard.form.pm
		F.sync_start(wizard.form)
		rebuild()
	end
end

-- The calendar: a month of days in an overlay; past days and days more than
-- 90 days away can't be picked.
local calendar = { year = nil, month = nil }

local function calendar_contents()
	local form = wizard.form
	local now = PVP.TournamentTime.now_ms()
	local today = os.date("*t", math.floor(now / 1000))
	local last = os.date("*t", math.floor((now + 90 * 24 * 3600 * 1000) / 1000))
	local y, m = calendar.year, calendar.month
	local can_back = y > today.year or (y == today.year and m > today.month)
	local can_forward = y < last.year or (y == last.year and m < last.month)
	local function nav(text, dir, enabled)
		return {
			n = G.UIT.C,
			config = { align = "cm", minw = 0.7, minh = 0.5, r = 0.08, colour = enabled and G.C.RED or G.C.UI.BACKGROUND_INACTIVE, hover = enabled, shadow = enabled, button = enabled and "tom_cal_month" or nil, ref_table = { dir = dir } },
			nodes = { TUI().text(text, 0.36, enabled and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) },
		}
	end
	local rows = {
		{
			n = G.UIT.R,
			config = { align = "cm", padding = 0.06 },
			nodes = {
				nav("<", -1, can_back),
				{ n = G.UIT.C, config = { align = "cm", minw = 4.2 }, nodes = { TUI().text(MONTHS[m] .. " " .. y, 0.42) } },
				nav(">", 1, can_forward),
			},
		},
	}
	local head = {}
	for _, d in ipairs({ "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }) do
		head[#head + 1] = { n = G.UIT.C, config = { align = "cm", minw = 0.8, padding = 0.03 }, nodes = { TUI().text(d, 0.28, G.C.UI.TEXT_INACTIVE) } }
	end
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = head }
	for _, week in ipairs(F.month_grid(y, m)) do
		local cells = {}
		for _, day in ipairs(week) do
			local cell
			if not day then
				cell = { n = G.UIT.C, config = { minw = 0.74, minh = 0.55 }, nodes = {} }
			else
				local ok = F.day_allowed(y, m, day, now)
				local chosen = form.date.year == y and form.date.month == m and form.date.day == day
				local is_today = today.year == y and today.month == m and today.day == day
				cell = {
					n = G.UIT.C,
					config = {
						align = "cm",
						minw = 0.74,
						minh = 0.55,
						r = 0.08,
						colour = chosen and G.C.PURPLE or (ok and G.C.BLUE or mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5)),
						outline = is_today and 1 or nil,
						outline_colour = is_today and G.C.GOLD or nil,
						hover = ok,
						shadow = ok,
						button = ok and "tom_cal_pick" or nil,
						ref_table = { day = day },
					},
					nodes = { TUI().text(tostring(day), 0.32, ok and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) },
				}
			end
			cells[#cells + 1] = { n = G.UIT.C, config = { align = "cm", padding = 0.03 }, nodes = { cell } }
		end
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = cells }
	end
	return rows
end

local calendar_el = nil -- the month grid, updated in place

local function show_calendar()
	calendar_el = MPAPI.ui_element(function()
		return { nodes = { { n = G.UIT.C, config = { align = "cm" }, nodes = calendar_contents() } } }
	end)
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			back_func = "tom_cal_close",
			contents = { { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { calendar_el.node } } },
		}),
	})
end

G.FUNCS.tom_cal_open = function()
	local d = wizard.form and wizard.form.date
	if d then
		calendar.year, calendar.month = d.year, d.month
		show_calendar()
	end
end

G.FUNCS.tom_cal_month = function(e)
	local dir = e.config.ref_table and e.config.ref_table.dir or 0
	calendar.month = calendar.month + dir
	if calendar.month < 1 then
		calendar.year, calendar.month = calendar.year - 1, 12
	elseif calendar.month > 12 then
		calendar.year, calendar.month = calendar.year + 1, 1
	end
	if calendar_el then
		calendar_el:update()
	end
end

G.FUNCS.tom_cal_pick = function(e)
	local day = e.config.ref_table and e.config.ref_table.day
	if day and wizard.form then
		wizard.form.date = { year = calendar.year, month = calendar.month, day = day }
		F.sync_start(wizard.form)
	end
	G.FUNCS.exit_overlay_menu()
	rebuild()
end

G.FUNCS.tom_cal_close = function()
	G.FUNCS.exit_overlay_menu()
end

G.FUNCS.tom_create_goto = function(e)
	local ref = e.config.ref_table
	if not ref then
		return
	end
	-- Forward only past steps without problems.
	for i = wizard.step, ref.step - 1 do
		local problems = F.problems(wizard.form, PVP.TournamentTime.now_ms(), F.STEPS[i].key)
		if #problems > 0 then
			wizard.step, wizard.warning = i, problems[1]
			rebuild()
			return
		end
	end
	wizard.step, wizard.warning = ref.step, nil
	rebuild()
end

G.FUNCS.tom_create_next = function()
	local problems = F.problems(wizard.form, PVP.TournamentTime.now_ms(), F.STEPS[wizard.step].key)
	if #problems > 0 then
		wizard.warning = problems[1]
	else
		wizard.step, wizard.warning = math.min(#F.STEPS, wizard.step + 1), nil
	end
	rebuild()
end

G.FUNCS.tom_create_back = function()
	if wizard.step == 1 then
		MPAPI.pages.back()
		return
	end
	wizard.step, wizard.warning = wizard.step - 1, nil
	rebuild()
end

G.FUNCS.tom_create_submit = function()
	local form = wizard.form
	if wizard.busy or #F.problems(form, PVP.TournamentTime.now_ms()) > 0 then
		return
	end
	wizard.busy, wizard.error = true, nil
	rebuild()
	local payload = F.payload(form, UI.decks())
	PVP.Tournaments.call("tournament_create", payload, function(err, data)
		local t = not err and data and data.tournament
		if not t then
			wizard.busy, wizard.error = false, UI.error_text(err or "The server sent no tournament")
			rebuild()
			return
		end
		local id = t.summary.id
		PVP.Tournaments.call("tournament_open", { id = id }, function(open_err)
			wizard.busy = false
			wizard.form = nil
			PVP.Tournaments.refresh()
			TOM.open_manage(id, open_err and ("Created, but registration didn't open: " .. UI.error_text(open_err)) or nil)
		end)
	end)
end
