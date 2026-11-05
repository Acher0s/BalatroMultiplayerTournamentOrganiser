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
		out[#out + 1] = { key = "R" .. n, title = "Round " .. n, first = n == 1, played = p ~= nil, tag = p and #names > 0 and ("= " .. table.concat(names, ", ")) or nil }
	end
	if F.NAMED[form.format] then
		out[#out + 1] = { heading = "Named rounds (win over the round number)" }
		for _, entry in ipairs(F.NAMED[form.format]) do
			out[#out + 1] = { key = entry[1], title = entry[2], named = true }
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
	local tag = item.tag or (item.played == false and ("not played with " .. form.previewPlayers) or nil)
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
			{ n = G.UIT.C, config = { align = "cr", minw = 1.6 }, nodes = { TUI().button("EDIT", "tom_timing_edit", { key = item.key, title = item.title, first = item.first }, G.C.BLUE, 1.2, 0.28) } },
		},
	}
end

-- The rows for the SCHEDULE step; context: { form, lists, rebuild }.
function TS.rows(context)
	ctx = context
	if not list then
		list = TUI().scroll_list({ items = items, build_row = row, visible = 5, row_h = 0.52, width = ROW_W, empty = "No rounds." })
	end
	return {
		UI.row("Round by round", {
			TUI().text("Changes for some rounds:", TUI().SMALL, G.C.UI.TEXT_INACTIVE),
		}, {
			"A break before a round, starting a",
			"round yourself, or playing it another",
			"way: say live finals after a league.",
			"Named rounds win over the number.",
		}),
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
		lists = { breakBefore = F.TIMING.breakBefore, start = F.TIMING.start, play = F.TIMING.play, atDay = F.at_days(form) },
		on_change = function()
			refresh_editor()
		end,
	}
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { TUI().text(string.upper(editing.title), 0.45, G.C.PURPLE) } },
	}
	if editing.first then
		rows[#rows + 1] = UI.note("Round 1 starts with the tournament.")
	else
		rows[#rows + 1] = UI.choice("Starts", "start", "start", {
			"When I press START ROUND: on the",
			"manage page, when you're ready.",
			"At a date and time: for long breaks,",
			"say the final the next evening.",
		})
		if t.start == "at" then
			t.atDay = t.atDay or 0
			t.atHour = t.atHour or "8"
			t.atMinute = t.atMinute or "00"
			if t.atPm == nil then
				t.atPm = true
			end
			rows[#rows + 1] = UI.choice("Day", "atDay", "atDay")
			local small = function(node)
				return { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { node } }
			end
			rows[#rows + 1] = UI.row("Time", {
				small(UI.text_box("tom_timing_hour", "atHour", { max_length = 2, w = 0.75, charset = "digits" })),
				small(TUI().text(":", 0.4)),
				small(UI.text_box("tom_timing_minute", "atMinute", { max_length = 2, w = 0.75, charset = "digits" })),
				{
					n = G.UIT.C,
					config = { align = "cm", minw = 0.9, minh = 0.5, r = 0.08, colour = G.C.UI.BACKGROUND_INACTIVE, hover = true, shadow = true, button = "tom_timing_ampm" },
					nodes = { TUI().text(t.atPm and "PM" or "AM", 0.32) },
				},
				TUI().spacer(0.2),
				TUI().text("your local time", TUI().SMALL, G.C.UI.TEXT_INACTIVE),
			})
		else
			rows[#rows + 1] = UI.choice("Break before", "breakBefore", "breakBefore", { "A pause once every earlier match", "is done, before this round opens.", "Longer? Use Starts: at a date and time." })
		end
	end
	rows[#rows + 1] = UI.choice("Played", "play", "play", { "Live: both players ready up within", "minutes. By a deadline: they play", "any time before it." })
	if t.play == "live" then
		t.readyUpMinutes = t.readyUpMinutes or 10
		rows[#rows + 1] = UI.choice("Time to ready up", "readyUpMinutes")
	elseif t.play == "window" then
		t.windowMinutes = t.windowMinutes or 24 * 60
		rows[#rows + 1] = UI.choice("Time for the round", "windowMinutes")
	end
	if t.play then
		rows[#rows + 1] = UI.switch("Every later round too", "onward", { "Later rounds are played this way", "too, until another round changes it." })
	end
	rows[#rows + 1] = TUI().hbox({
		TUI().button("RESET", "tom_timing_reset", nil, G.C.RED, 1.8),
		TUI().spacer(3.0),
		TUI().button("DONE", "tom_timing_done", nil, G.C.GREEN, 2.2),
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
