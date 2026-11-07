-- The create wizard (page tom_create): BASICS, FORMAT, GAMES, SCHEDULE,
-- REVIEW. The form lives in TOM.Form (lib/form.lua); NEXT is refused while
-- the step has problems. CREATE makes the tournament, opens registration and
-- goes to its manage page.

local F = TOM.Form
local UI = TOM.UI

local wizard = { form = nil, step = 1, error = nil, busy = false, el = nil, lists = {}, start_note = { text = "", colour = { 1, 1, 1, 1 } } }
-- Editing an existing tournament: { id, running, original (what it has, as
-- a payload), start }; nil when creating.
wizard.edit = nil

-- The steps: all of them, or once running only what can still change (the
-- name and description, and round settings).
local function steps()
	if not (wizard.edit and wizard.edit.running) then
		return F.STEPS
	end
	local out = {}
	for _, s in ipairs(F.STEPS) do
		if s.key == "basics" or s.key == "rounds" or s.key == "review" then
			out[#out + 1] = s
		end
	end
	return out
end

local function problems(step_key)
	local e = wizard.edit
	return F.problems(wizard.form, PVP.TournamentTime.now_ms(), step_key, e and { started = e.running, original_start = e.start } or nil)
end

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
		PVP.TUI.set_live(wizard.start_note, TOM.T("k_tom_start_note_soon"), G.C.RED)
		return
	end
	local left = PVP.TournamentTime.countdown(at)
	PVP.TUI.set_live(wizard.start_note, left and TOM.T("k_tom_start_note_in", left) or TOM.T("k_tom_your_local_time"), G.C.UI.TEXT_INACTIVE)
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
	live_event = "k_tom_help_preset_live_event",
	live_fixed_rounds = "k_tom_help_preset_live_fixed_rounds",
	league = "k_tom_help_preset_league",
}

local MONTHS = { "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec" }
local WEEKDAYS = { "sun", "mon", "tue", "wed", "thu", "fri", "sat" }

-- "Fri, Nov 7, 2026"
local function date_text(d)
	local t = os.date("*t", os.time({ year = d.year, month = d.month, day = d.day, hour = 12 }))
	return TOM.T("k_tom_date_full", TOM.T("k_tom_day_" .. WEEKDAYS[t.wday]), TOM.T("k_tom_month_" .. MONTHS[t.month]), t.day, t.year)
end

-- Date (opens the calendar), hour : minutes, AM/PM; all in local time.
local function start_row()
	local form = wizard.form
	local small = function(node)
		return { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { node } }
	end
	return {
		UI.row(TOM.T("k_tom_starts"), {
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
				nodes = { TUI().text(TOM.T(form.pm and "k_tom_pm" or "k_tom_am"), 0.32) },
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
		add(UI.input(TOM.T("k_tom_name"), "tom_create_name", "name", { prompt = TOM.T("k_tom_name_prompt"), max_length = 48 }))
		-- The description is edited in its own overlay (several lines).
		local desc = (form.description or ""):gsub("\n", "  ")
		if #desc > 46 then
			desc = desc:sub(1, 45) .. "..."
		end
		add(UI.row(TOM.T("k_tom_description"), {
			TUI().button(TOM.T("k_tom_edit"), "tom_create_desc_edit", nil, G.C.BLUE, 1.4, 0.3),
			TUI().spacer(0.1),
			TUI().text(desc ~= "" and desc or TOM.T("k_tom_desc_placeholder"), TUI().SMALL, desc ~= "" and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE),
		}, { TOM.T("k_tom_desc_help_1"), TOM.T("k_tom_desc_help_2", F.DESC_LINES * F.DESC_LINE, F.DESC_LINES) }))
		if wizard.edit and wizard.edit.running then
			add(UI.note(TOM.T("k_tom_running_only_the_name_description_an")))
			return rows
		end
		add(UI.choice(TOM.T("k_tom_who_can_join"), "visibility", nil, UI.lines("k_tom_help_public_listed_in_browse_for_everyone")))
		if UI.may_create_official() then
			add(UI.switch(TOM.T("k_tom_official"), "official", UI.lines("k_tom_help_shown_with_a_gold_official_badge_and")))
		end
		add(UI.switch(TOM.T("k_tom_ranked_profile_only"), "requireRanked", UI.lines("k_tom_help_ranked_profile_only")))
		add(UI.choice(TOM.T("k_tom_players"), "maxPlayers", nil, UI.lines("k_tom_help_the_most_players_who_can_join_anyone")))
		for _, r in ipairs(start_row()) do
			add(r)
		end
		add(UI.choice(TOM.T("k_tom_check_in"), "checkInMinutes", nil, UI.lines("k_tom_help_players_press_check_in_in_the_minute")))
	elseif key == "format" then
		add(UI.choice(TOM.T("k_tom_format"), "format"))
		if F.uses(form, "grandFinalReset") then
			add(UI.choice(TOM.T("k_tom_grand_final_reset"), "grandFinalReset", nil, UI.lines("k_tom_help_if_the_player_from_the_losers_bracke")))
		elseif F.uses(form, "groupSize") then
			add(UI.choice(TOM.T("k_tom_groups"), "groupSize", nil, UI.lines("k_tom_help_everyone_plays_everyone_else_in_thei")))
		elseif F.uses(form, "swissRounds") then
			add(UI.choice(TOM.T("k_tom_rounds"), "swissRounds", nil, UI.lines("k_tom_help_each_round_pairs_players_with_the_sa")))
		end
		add(UI.choice(TOM.T("k_tom_seeding"), "seeding", nil, UI.lines("k_tom_help_who_is_seed_1_2_3_top_seeds_meet_eac")))
	elseif key == "games" then
		add(UI.choice(TOM.T("k_tom_game_type"), "gameMode", "gameMode"))
		add(UI.choice(TOM.T("k_tom_ruleset"), "ruleset", "ruleset"))
		add(UI.choice(TOM.T("k_tom_series"), "bestOf", nil, UI.lines("k_tom_help_how_many_games_a_match_has_best_of_3")))
		add(UI.choice(TOM.T("k_tom_decks_stakes"), "deckKind", nil, UI.lines("k_tom_help_one_deck_everyone_plays_the_same_dec")))
		if F.uses(form, "deck") then
			add(UI.choice(TOM.T("k_tom_deck"), "deck", "deck"))
			add(UI.choice(TOM.T("k_tom_stake"), "stake", "stake"))
		elseif F.uses(form, "banOrder") then
			add(TOM.Pools.row(form, function()
				if wizard.el then
					wizard.el:update()
				end
			end))
			add(UI.choice(TOM.T("k_tom_ban_order"), "banOrder", nil, UI.lines("k_tom_help_who_bans_first_in_each_match")))
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
		add(UI.choice(TOM.T("k_tom_timetable"), "preset", nil, PRESET_NOTES[form.preset] and UI.lines(PRESET_NOTES[form.preset]) or nil))
		if F.uses(form, "readyUpMinutes") then
			add(UI.choice(TOM.T("k_tom_time_to_ready_up"), "readyUpMinutes", nil, UI.lines("k_tom_help_once_a_match_opens_both_players_have")))
		end
		if F.uses(form, "breakMinutes") then
			add(UI.choice(TOM.T("k_tom_breaks"), "breakMinutes", nil, UI.lines("k_tom_help_a_pause_between_rounds_with_a_break_")))
		end
		if F.uses(form, "windowMinutes") then
			add(UI.choice(TOM.T("k_tom_time_per_round"), "windowMinutes", nil, UI.lines("k_tom_help_players_arrange_a_time_themselves_an")))
		end
		local context = {
			form = form,
			lists = wizard.lists,
			rebuild = function()
				if wizard.el then
					wizard.el:update()
				end
			end,
		}
		for _, r in ipairs(TOM.TimingStep.rows(context)) do
			add(r)
		end
	elseif key == "review" then
		local lists = wizard.lists
		local function line(label, value)
			add(UI.row(label, { TUI().text(value, TUI().TEXT) }))
		end
		line(TOM.T("k_tom_name"), form.name ~= "" and form.name or "-")
		local who = F.label(form, "visibility")
		if form.official then
			who = TOM.T("k_tom_list2", who, TOM.T("k_tom_official_upper"))
		end
		if form.requireRanked then
			who = TOM.T("k_tom_list2", who, TOM.T("k_tom_ranked_profile_only_lower"))
		end
		line(TOM.T("k_tom_who_can_join"), who)
		line(TOM.T("k_tom_players"), TOM.T("k_tom_up_to_n", form.maxPlayers))
		line(TOM.T("k_tom_starts"), TOM.T("k_tom_paren", TT().format_local(form.startsAt), F.label(form, "checkInMinutes"):lower()))
		local format = F.label(form, "format")
		if F.uses(form, "groupSize") and form.groupSize then
			format = TOM.T("k_tom_list2", format, F.label(form, "groupSize"):lower())
		elseif F.uses(form, "swissRounds") and form.swissRounds then
			format = TOM.T("k_tom_list2", format, F.count(form.swissRounds, "k_tom_n_rounds"))
		end
		line(TOM.T("k_tom_format"), TOM.T("k_tom_review_format", format, F.label(form, "seeding"):lower()))
		line(TOM.T("k_tom_games"), TOM.T("k_tom_list2", TOM.T("k_tom_list2", F.label(form, "gameMode", lists.gameMode), F.label(form, "ruleset", lists.ruleset)), F.label(form, "bestOf"):lower()))
		local decks = F.label(form, "deckKind")
		if F.uses(form, "deck") then
			decks = TOM.T("k_tom_deck_on_stake", F.label(form, "deck", lists.deck), F.label(form, "stake", lists.stake))
		elseif F.uses(form, "banOrder") then
			decks = TOM.T("k_tom_review_pool", F.pool_text(form), F.label(form, "banOrder"):lower())
		end
		line(TOM.T("k_tom_decks_stakes"), decks)
		local changed = {}
		for _, k in ipairs(F.round_keys(form)) do
			if F.round_override(form.rounds[k]) then
				changed[#changed + 1] = k:match("^R(%d+)$") and TOM.T("k_tom_round_lower", k:sub(2)) or F.named_label(form.format, k):lower()
			end
		end
		line(TOM.T("k_tom_rounds"), #changed == 0 and TOM.T("k_tom_all_defaults") or TOM.T("k_tom_changed", table.concat(changed, TOM.T("k_tom_sep"))))
		local timing = {}
		for _, k in ipairs(F.round_keys(form)) do
			if F.timing_override(form.timing[k], form) then
				timing[#timing + 1] = k:match("^R(%d+)$") and TOM.T("k_tom_round_lower", k:sub(2)) or F.named_label(form.format, k):lower()
			end
		end
		line(TOM.T("k_tom_timetable"), #timing > 0 and TOM.T("k_tom_preset_changed", F.label(form, "preset"), table.concat(timing, TOM.T("k_tom_sep"))) or F.label(form, "preset"))
		if not wizard.edit then
			add(UI.note(TOM.T("k_tom_registration_opens_as_soon_as_you_cr")))
		end
	end
	return rows
end

local function step_bar()
	local nodes = {}
	for i, s in ipairs(steps()) do
		local current = i == wizard.step
		nodes[#nodes + 1] = {
			n = G.UIT.C,
			config = { align = "cm", padding = 0.03 },
			nodes = {
				{
					n = G.UIT.C,
					config = { align = "cm", minw = 1.85, minh = 0.45, r = 0.08, colour = current and G.C.PURPLE or G.C.UI.BACKGROUND_INACTIVE, hover = true, button = "tom_create_goto", ref_table = { step = i } },
					nodes = { TUI().text(i .. ". " .. F.text(s.title), 0.3, current and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) },
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
	local step = steps()[wizard.step]
	local last = wizard.step == #steps()
	local body = {
		{
			n = G.UIT.R,
			config = { align = "cm", padding = 0.04 },
			nodes = {
				{ n = G.UIT.C, config = { align = "cl", minw = 3.4 }, nodes = { TUI().button(TOM.T("k_tom_load_template"), "tom_create_load_template", nil, G.C.UI.BACKGROUND_INACTIVE, 2.9, 0.28) } },
				{ n = G.UIT.C, config = { align = "cm", minw = 4.8 }, nodes = { TUI().text(wizard.edit and "EDIT TOURNAMENT" or "NEW TOURNAMENT", 0.45, G.C.PURPLE) } },
				{ n = G.UIT.C, config = { align = "cr", minw = 3.4 }, nodes = { TUI().button(TOM.T("k_tom_save_template"), "tom_create_save_template", nil, G.C.UI.BACKGROUND_INACTIVE, 2.9, 0.28) } },
			},
		},
		step_bar(),
	}
	local form_rows = step_rows(step.key)
	body[#body + 1] = { n = G.UIT.R, config = { align = "tm", padding = 0.1, minh = 4.6, minw = 11.6, r = 0.1, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5) }, nodes = { { n = G.UIT.C, config = { align = "tl" }, nodes = form_rows } } }
	local problems = problems(not last and step.key or nil)
	local message = wizard.error or (wizard.busy and TOM.T("k_tom_creating")) or (last and problems[1]) or wizard.warning
	if message then
		body[#body + 1] = TUI().message(message, wizard.error and G.C.RED or G.C.UI.TEXT_INACTIVE)
	end
	local buttons = {
		TUI().button(wizard.step == 1 and "CANCEL" or "BACK", "tom_create_back", nil, G.C.ORANGE, 2.0),
		TUI().spacer(5.0),
	}
	if last then
		buttons[#buttons + 1] = TUI().button(wizard.edit and "SAVE CHANGES" or "CREATE", "tom_create_submit", nil, (#problems == 0 and not wizard.busy) and G.C.GREEN or G.C.UI.BACKGROUND_INACTIVE, 2.4)
	else
		buttons[#buttons + 1] = TUI().button(TOM.T("k_tom_next"), "tom_create_next", nil, G.C.BLUE, 2.4)
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
			TOM.TimingStep.dispose()
		end,
	})
end)

-- Opens the wizard with a fresh form (or the one left half done).
function TOM.open_create(fresh)
	-- A form left from editing isn't a new one.
	if wizard.edit then
		fresh = true
		wizard.edit = nil
	end
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

-- The description editor: one text box per line.
local desc_edit = nil -- { line1..lineN } while open

G.FUNCS.tom_create_desc_edit = function()
	if not wizard.form then
		return
	end
	desc_edit = {}
	for i, line in ipairs(F.split_description(wizard.form.description)) do
		desc_edit["line" .. i] = line
	end
	UI.target = { form = desc_edit, lists = {}, on_change = function() end }
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { TUI().text(TOM.T("k_tom_description_2"), 0.45, G.C.PURPLE) } },
		{ n = G.UIT.R, config = { align = "cm", padding = 0.02 }, nodes = { TUI().text(TOM.T("k_tom_lines_of", F.DESC_LINES, F.DESC_LINE), TUI().SMALL, G.C.UI.TEXT_INACTIVE) } },
	}
	for i = 1, F.DESC_LINES do
		rows[#rows + 1] = {
			n = G.UIT.R,
			config = { align = "cm", padding = 0.03 },
			nodes = { UI.text_box("tom_create_desc_" .. i, "line" .. i, { max_length = F.DESC_LINE, w = 11.5, text_scale = 0.28, prompt = i == 1 and "Prizes, rules, where to find you..." or "" }) },
		}
	end
	rows[#rows + 1] = TUI().hbox({
		TUI().button(TOM.T("k_tom_clear"), "tom_create_desc_clear", nil, G.C.RED, 1.8),
		TUI().spacer(6.0),
		TUI().button(TOM.T("k_tom_done"), "tom_create_desc_done", nil, G.C.GREEN, 2.2),
	}, "cm", 0.1)
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			no_back = true,
			contents = { { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { { n = G.UIT.C, config = { align = "cm" }, nodes = rows } } } },
		}),
	})
end

G.FUNCS.tom_create_desc_clear = function()
	if wizard.form then
		wizard.form.description = ""
	end
	G.FUNCS.tom_create_desc_edit()
end

G.FUNCS.tom_create_desc_done = function()
	if desc_edit and wizard.form then
		local lines = {}
		for i = 1, F.DESC_LINES do
			lines[i] = desc_edit["line" .. i] or ""
		end
		wizard.form.description = F.join_description(lines)
	end
	desc_edit = nil
	G.FUNCS.exit_overlay_menu()
	rebuild()
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
		wizard.warning = skipped and skipped > 0 and TOM.T("k_tom_loaded_template_skipped", name, skipped) or TOM.T("k_tom_loaded_template", name)
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
				{ n = G.UIT.C, config = { align = "cm", minw = 4.2 }, nodes = { TUI().text(TOM.T("k_tom_month_year", TOM.T("k_tom_month_long_" .. MONTHS[m]), y), 0.42) } },
				nav(">", 1, can_forward),
			},
		},
	}
	local head = {}
	for _, d in ipairs({ "mon", "tue", "wed", "thu", "fri", "sat", "sun" }) do
		head[#head + 1] = { n = G.UIT.C, config = { align = "cm", minw = 0.8, padding = 0.03 }, nodes = { TUI().text(TOM.T("k_tom_day_short_" .. d), 0.28, G.C.UI.TEXT_INACTIVE) } }
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
		local problems = problems(steps()[i].key)
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
	local found = problems(steps()[wizard.step].key)
	if #found > 0 then
		wizard.warning = found[1]
	else
		wizard.step, wizard.warning = math.min(#steps(), wizard.step + 1), nil
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

-- Opens the wizard on an existing tournament (its full view): every step
-- before the start, only what can still change once it runs.
function TOM.open_edit(view)
	local now = PVP.TournamentTime.now_ms()
	local all = UI.decks()
	local form = F.from_view(view, now, all)
	F.sync_start(form)
	wizard.form = form
	wizard.edit = { id = view.summary.id, running = view.summary.status == "running", original = F.payload(form, all), start = form.startsAt }
	wizard.step = 1
	wizard.error, wizard.warning, wizard.busy = nil, nil, false
	wizard.lists = make_lists()
	MPAPI.pages.show("tom_create", {})
end

-- SAVE CHANGES: only what changed goes to the server.
local function save_edit()
	local e = wizard.edit
	local changes = F.changes(e.original, F.payload(wizard.form, UI.decks()), e.running)
	if not changes then
		wizard.warning = TOM.T("k_tom_nothing_changed")
		rebuild()
		return
	end
	changes.id = e.id
	wizard.busy, wizard.error = true, nil
	rebuild()
	PVP.Tournaments.call("tournament_update", changes, function(err)
		wizard.busy = false
		if err then
			wizard.error = UI.error_text(err)
			rebuild()
			return
		end
		local id = e.id
		wizard.form, wizard.edit = nil, nil
		PVP.Tournaments.refresh()
		TOM.open_manage(id, TOM.T("k_tom_saved"))
	end)
end

G.FUNCS.tom_create_submit = function()
	local form = wizard.form
	if wizard.busy or #problems(nil) > 0 then
		return
	end
	if wizard.edit then
		save_edit()
		return
	end
	wizard.busy, wizard.error = true, nil
	rebuild()
	local payload = F.payload(form, UI.decks())
	PVP.Tournaments.call("tournament_create", payload, function(err, data)
		local t = not err and data and data.tournament
		if not t then
			wizard.busy, wizard.error = false, UI.error_text(err or TOM.T("k_tom_no_tournament_sent"))
			rebuild()
			return
		end
		local id = t.summary.id
		PVP.Tournaments.call("tournament_open", { id = id }, function(open_err)
			wizard.busy = false
			wizard.form = nil
			PVP.Tournaments.refresh()
			TOM.open_manage(id, open_err and TOM.T("k_tom_created_not_open", UI.error_text(open_err)) or nil)
		end)
	end)
end
