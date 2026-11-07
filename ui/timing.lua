-- The SCHEDULE step's "round by round" list (TOM.TimingStep): changes to the
-- timetable for a round (Round 1, 2...; named rounds win over the number):
-- a break before it, starting it by hand, or playing it another way (live
-- or by a deadline), optionally for every later round too. EDIT opens an
-- overlay, updated in place. Rules: lib/form.lua (timing_override); the
-- server applies them when it starts (round_timing.ts).

local F = TOM.Form
local UI = TOM.UI

local TS = {}
TOM.TimingStep = TS

local ROW_W = 11.2
local ctx = nil -- { form, lists, rebuild } from the wizard
local list = nil
local editing = nil -- { key, title, first }
local editor_el = nil

local function TUI()
	return PVP.TUI
end

local function preview_players(form)
	if not form.previewPlayers or form.previewPlayers > form.maxPlayers then
		form.previewPlayers = form.maxPlayers
	end
	return form.previewPlayers
end

local function items()
	if not ctx then
		return {}
	end
	local form = ctx.form
	local plan = F.round_plan(form, preview_players(form))
	local out = {}
	for n = 1, #F.round_plan(form, form.maxPlayers) do
		local p = plan[n]
		local names = {}
		for _, k in ipairs(p and p.names or {}) do
			names[#names + 1] = F.named_label(form.format, k)
		end
		out[#out + 1] = { key = "R" .. n, title = TOM.T("k_tom_round_n", n), first = n == 1, played = p ~= nil, tag = p and #names > 0 and ("= " .. table.concat(names, ", ")) or nil }
	end
	if F.NAMED[form.format] then
		out[#out + 1] = { heading = TOM.T("k_tom_named_rounds") }
		for _, entry in ipairs(F.NAMED[form.format]) do
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
	local t = form.timing[item.key]
	local changed = F.timing_override(t, form) ~= nil
	local title_nodes = { TUI().text(item.title, TUI().TEXT, changed and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE) }
	local tag = item.tag or (item.played == false and TOM.T("k_tom_not_played_with", form.previewPlayers) or nil)
	if tag then
		title_nodes[#title_nodes + 1] = TUI().spacer(0.1)
		title_nodes[#title_nodes + 1] = TUI().text(tag, TUI().SMALL, item.played == false and G.C.UI.TEXT_INACTIVE or G.C.GOLD)
	end
	return {
		n = G.UIT.R,
		config = { align = "cm", minh = 0.5, r = 0.08, colour = changed and mix_colours(G.C.BLUE, G.C.BLACK, 0.25) or nil },
		nodes = {
			{ n = G.UIT.C, config = { align = "cl", minw = 4.2, padding = 0.04 }, nodes = { { n = G.UIT.R, config = { align = "cl" }, nodes = title_nodes } } },
			{ n = G.UIT.C, config = { align = "cl", minw = 5.2 }, nodes = { TUI().text(F.describe_timing(t, form), TUI().SMALL, item.played == false and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT) } },
			{ n = G.UIT.C, config = { align = "cr", minw = 1.6 }, nodes = { TUI().button(TOM.T("k_tom_edit"), "tom_timing_edit", { key = item.key, title = item.title, first = item.first }, G.C.BLUE, 1.2, 0.28) } },
		},
	}
end

-- The rows for the SCHEDULE step; context: { form, lists, rebuild }.
function TS.rows(context)
	ctx = context
	if not list then
		list = TUI().scroll_list({ items = items, build_row = row, visible = 5, row_h = 0.52, width = ROW_W, empty = TOM.T("k_tom_no_rounds") })
	end
	return {
		UI.row(TOM.T("k_tom_round_by_round"), {
			TUI().text(TOM.T("k_tom_changes_for_some_rounds"), TUI().SMALL, G.C.UI.TEXT_INACTIVE),
		}, UI.lines("k_tom_help_a_break_before_a_round_starting_a")),
		{ n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = { list.el.node } },
	}
end

function TS.dispose()
	if list then
		list:dispose()
		list = nil
	end
	editing, editor_el = nil, nil
end

-- The editor -----------------------------------------------------------------

local refresh_editor

local function editor_contents()
	local form = ctx.form
	form.timing[editing.key] = form.timing[editing.key] or {}
	local t = form.timing[editing.key]
	UI.target = {
		form = t,
		lists = { breakBefore = F.TIMING.breakBefore, start = F.TIMING.start, play = F.TIMING.play, atDay = F.at_days(form), checkInMinutes = F.TIMING.checkInMinutes },
		on_change = function()
			refresh_editor()
		end,
	}
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { TUI().text(string.upper(editing.title), 0.45, G.C.PURPLE) } },
	}
	if editing.first then
		rows[#rows + 1] = UI.note(TOM.T("k_tom_round_1_starts_with_the_tournament"))
	else
		rows[#rows + 1] = UI.choice(TOM.T("k_tom_starts"), "start", "start", UI.lines("k_tom_help_when_i_press_start_round_on_the"))
		if t.start == "at" then
			t.atDay = t.atDay or 0
			t.atHour = t.atHour or "8"
			t.atMinute = t.atMinute or "00"
			if t.atPm == nil then
				t.atPm = true
			end
			rows[#rows + 1] = UI.choice(TOM.T("k_tom_day"), "atDay", "atDay")
			local small = function(node)
				return { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { node } }
			end
			rows[#rows + 1] = UI.row(TOM.T("k_tom_time"), {
				small(UI.text_box("tom_timing_hour", "atHour", { max_length = 2, w = 0.75, charset = "digits" })),
				small(TUI().text(":", 0.4)),
				small(UI.text_box("tom_timing_minute", "atMinute", { max_length = 2, w = 0.75, charset = "digits" })),
				{
					n = G.UIT.C,
					config = { align = "cm", minw = 0.9, minh = 0.5, r = 0.08, colour = G.C.UI.BACKGROUND_INACTIVE, hover = true, shadow = true, button = "tom_timing_ampm" },
					nodes = { TUI().text(TOM.T(t.atPm and "k_tom_pm" or "k_tom_am"), 0.32) },
				},
				TUI().spacer(0.2),
				TUI().text(TOM.T("k_tom_your_local_time"), TUI().SMALL, G.C.UI.TEXT_INACTIVE),
			})
			-- Only for a round at a date and time: after a long break, make
			-- sure its players are coming back.
			if t.checkInMinutes == nil then
				t.checkInMinutes = false
			end
			rows[#rows + 1] = UI.choice(TOM.T("k_tom_check_in_before"), "checkInMinutes", "checkInMinutes", UI.lines("k_tom_help_round_check_in"))
		else
			rows[#rows + 1] = UI.choice(TOM.T("k_tom_break_before"), "breakBefore", "breakBefore", UI.lines("k_tom_help_a_pause_once_every_earlier_match_is_"))
		end
	end
	rows[#rows + 1] = UI.choice(TOM.T("k_tom_played"), "play", "play", UI.lines("k_tom_help_live_both_players_ready_up_within_mi"))
	if t.play == "live" then
		t.readyUpMinutes = t.readyUpMinutes or 10
		rows[#rows + 1] = UI.choice(TOM.T("k_tom_time_to_ready_up"), "readyUpMinutes")
	elseif t.play == "window" then
		t.windowMinutes = t.windowMinutes or 24 * 60
		rows[#rows + 1] = UI.choice(TOM.T("k_tom_time_for_the_round"), "windowMinutes")
	end
	if t.play then
		rows[#rows + 1] = UI.switch(TOM.T("k_tom_every_later_round_too"), "onward", UI.lines("k_tom_help_later_rounds_are_played_this_way_too"))
	end
	rows[#rows + 1] = TUI().hbox({
		TUI().button(TOM.T("k_tom_reset"), "tom_timing_reset", nil, G.C.RED, 1.8),
		TUI().spacer(3.0),
		TUI().button(TOM.T("k_tom_done"), "tom_timing_done", nil, G.C.GREEN, 2.2),
	}, "cm", 0.1)
	return rows
end

refresh_editor = function()
	if editor_el then
		editor_el:update()
	end
end

G.FUNCS.tom_timing_edit = function(e)
	local ref = e.config.ref_table
	if not ref or not ctx then
		return
	end
	editing = { key = ref.key, title = ref.title, first = ref.first }
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

G.FUNCS.tom_timing_ampm = function()
	local t = editing and ctx and ctx.form.timing[editing.key]
	if t then
		t.atPm = not t.atPm
		refresh_editor()
	end
end

G.FUNCS.tom_timing_reset = function()
	if editing and ctx then
		ctx.form.timing[editing.key] = {}
		refresh_editor()
	end
end

G.FUNCS.tom_timing_done = function()
	editing, editor_el = nil, nil
	G.FUNCS.exit_overlay_menu()
	if ctx then
		ctx.rebuild()
	end
	if list then
		list:update()
	end
end
