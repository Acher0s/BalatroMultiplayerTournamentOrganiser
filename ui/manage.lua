-- The manage page (tom_manage, params {id}): running one tournament.
--   top      name, status, start, invite code; the actions for this status
--            (open/close registration, start now, start round, pause/resume,
--            cancel, bracket)
--   left     players (remove / drop), the waitlist (promote), and with manual
--            seeding the order (move up, save)
--   right    once running: the matches being played or waiting on someone,
--            with "X wins" and "+10 min"
-- Refreshes every 5 seconds and on every tournament change.

local UI = TOM.UI

local page = { id = nil, view = nil, el = nil, active = false, message = nil, message_colour = nil, confirm = nil, order = nil, lists = {} }

local REFRESH_SECONDS = 5
local LEFT_W = 4.8
local RIGHT_W = 6.6

local function TUI()
	return PVP.TUI
end

-- Status -> text key.
local STATUS = { draft = "k_tom_status_draft", registration = "k_tom_status_registration_open", check_in = "k_tom_status_check_in", running = "k_tom_status_running", finished = "k_tom_status_finished", cancelled = "k_tom_status_cancelled" }
local ROUND = { W = "W", L = "L", GF = "GF", RR = "R", SW = "R" }

local function rebuild()
	if page.el and page.active then
		page.el:update()
	end
end

local function say(text, colour)
	page.message, page.message_colour = text, colour
	rebuild()
end

local function load()
	if not page.id then
		return
	end
	PVP.Tournaments.get({ id = page.id }, function(err, data)
		if not page.active then
			return
		end
		if err or not data or not data.tournament then
			say(UI.error_text(err or TOM.T("k_tom_no_tournament_sent")), G.C.RED)
			return
		end
		PVP.Tournaments.state.views[page.id] = data.tournament
		-- Removed as a co-organiser (or the organiser handed it over): the
		-- page goes; the server refuses what it would do anyway.
		local role = data.tournament.role
		if role ~= "organiser" and role ~= "co_organiser" then
			page.view = nil
			say(TOM.T("k_tom_not_running_it"), G.C.ORANGE)
			return
		end
		page.view = data.tournament
		rebuild()
	end)
end

-- An organiser action: say what failed, else reload.
local function act(rpc_id, body, done_text)
	body.id = page.id
	page.confirm = nil
	say(TOM.T("k_tom_working"), G.C.UI.TEXT_INACTIVE)
	PVP.Tournaments.call(rpc_id, body, function(err)
		if err then
			say(UI.error_text(err), G.C.RED)
		else
			say(done_text, G.C.GREEN)
			PVP.Tournaments.refresh()
		end
		load()
	end)
end

local function name_of(p)
	if p == "tbd" then
		return TOM.T("k_tom_tbd")
	end
	return type(p) == "table" and p.name or "bye"
end

local function short(s, n)
	s = tostring(s)
	return #s > n and (s:sub(1, n - 1) .. ".") or s
end

-- The buttons for what can be done now.
local function actions(view)
	local s = view.summary
	local status = s.status
	local out = {}
	local function add(label, fn_name, ref, colour, w)
		out[#out + 1] = TUI().button(label, fn_name, ref, colour, w or 2.4, 0.3)
	end
	-- Co-organisers run matches and players; the rest is the organiser's.
	local organiser = view.role == "organiser"
	-- Both kinds of organiser: the notice board, and messages into the match lobbies.
	local function talk()
		if status ~= "finished" and status ~= "cancelled" then
			add(view.notice and "NOTICE BOARD *" or "NOTICE BOARD", "tom_manage_do", { what = "notice" }, G.C.UI.BACKGROUND_INACTIVE, 2.8)
		end
		if status == "running" then
			add("MESSAGE PLAYERS", "tom_manage_do", { what = "message" }, G.C.UI.BACKGROUND_INACTIVE, 3.0)
		end
	end
	if not organiser then
		talk()
		if status == "running" then
			add(view.paused and "RESUME" or "PAUSE", "tom_manage_do", { what = view.paused and "resume" or "pause" }, view.paused and G.C.GREEN or G.C.ORANGE)
			local manual = view.timetable and (view.timetable.kind == "custom" or view.timetable.preset == "live_fixed_rounds")
			if manual then
				add("START ROUND", "tom_manage_do", { what = "round" }, G.C.BLUE)
			end
		end
		if view.bracket then
			add("BRACKET", "tom_manage_do", { what = "bracket" }, G.C.BLUE, 2.0)
		end
		return out
	end
	if status == "draft" then
		add("OPEN REGISTRATION", "tom_manage_do", { what = "open" }, G.C.GREEN, 3.4)
	end
	if status == "registration" then
		if s.registrationOpen then
			add("CLOSE REGISTRATION", "tom_manage_do", { what = "close_reg" }, G.C.ORANGE, 3.4)
		else
			add("REOPEN REGISTRATION", "tom_manage_do", { what = "open_reg" }, G.C.GREEN, 3.4)
		end
	end
	if status == "registration" or status == "check_in" then
		add(page.confirm == "start" and "SURE? START" or "START NOW", "tom_manage_do", { what = "start" }, G.C.BLUE)
	end
	-- Testing on a Dev server (the MultiplayerDev mod): fill the free spots
	-- with bots. The server refuses this anywhere else.
	local dev = SMODS.Mods and SMODS.Mods.MultiplayerDev and SMODS.Mods.MultiplayerDev.can_load ~= false
	local free = (s.maxPlayers or 0) - (s.players or 0)
	if dev and free > 0 and (status == "draft" or status == "registration" or status == "check_in") then
		add("ADD BOTS", "tom_manage_do", { what = "bots", count = free }, G.C.UI.BACKGROUND_INACTIVE, 2.0)
	end
	if status == "running" then
		if view.paused then
			add("RESUME", "tom_manage_do", { what = "resume" }, G.C.GREEN)
		else
			add("PAUSE", "tom_manage_do", { what = "pause" }, G.C.ORANGE)
		end
		local manual = view.timetable and (view.timetable.kind == "custom" or view.timetable.preset == "live_fixed_rounds")
		if manual then
			add("START ROUND", "tom_manage_do", { what = "round" }, G.C.BLUE)
		end
	end
	-- Change settings: everything before the start, round settings after.
	if status == "draft" or status == "registration" or status == "check_in" then
		add("EDIT", "tom_manage_do", { what = "edit" }, G.C.PURPLE, 1.6)
	elseif status == "running" then
		add("EDIT ROUNDS", "tom_manage_do", { what = "edit" }, G.C.PURPLE, 2.4)
	end
	if view.bracket then
		add("BRACKET", "tom_manage_do", { what = "bracket" }, G.C.BLUE, 2.0)
	end
	talk()
	if status ~= "finished" and status ~= "cancelled" then
		add("CO-ORGANISERS", "tom_manage_do", { what = "coorg" }, G.C.UI.BACKGROUND_INACTIVE, 2.8)
	end
	if status ~= "finished" and status ~= "cancelled" then
		add(page.confirm == "cancel" and "SURE? CANCEL IT" or "CANCEL", "tom_manage_do", { what = "cancel" }, G.C.RED, page.confirm == "cancel" and 3.2 or 2.0)
	end
	return out
end

local function header(view)
	local s = view.summary
	local TT = PVP.TournamentTime
	local when
	if s.status == "registration" or s.status == "check_in" or s.status == "draft" then
		local left = TT.countdown(s.startsAt)
		when = left and TOM.T("k_tom_starts_in_at", TT.format_local(s.startsAt), left) or TOM.T("k_tom_starts_at", TT.format_local(s.startsAt))
	-- The status is already on the line above: this says when instead.
	elseif s.status == "running" then
		when = view.paused and TOM.T("k_tom_paused_deadlines") or TOM.T("k_tom_started_at", TT.format_local(view.startedAt or s.startsAt))
	elseif s.status == "finished" and view.finishedAt then
		when = TOM.T("k_tom_ended_at", TT.format_local(view.finishedAt))
	end
	local info = TOM.T("k_tom_manage_info", STATUS[s.status] and TOM.T(STATUS[s.status]) or s.status, TUI().format_name(s.format), s.players, s.maxPlayers)
	if s.waitlist and s.waitlist > 0 then
		info = TOM.T("k_tom_list2", info, TOM.T("k_tom_n_waiting", s.waitlist))
	end
	local rows = {
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().name_line(s, 0.45) } },
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(info, TUI().TEXT, G.C.UI.TEXT_INACTIVE) } },
	}
	if when then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(when, TUI().TEXT, view.paused and G.C.ORANGE or G.C.GOLD) } }
	end
	if view.inviteCode then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(TOM.T("k_tom_invite_code_is", view.inviteCode), TUI().TEXT, G.C.BLUE) } }
	end
	return rows
end

-- Left column rows: players (or the seeding order), then the waitlist.
local function player_items()
	local view = page.view
	local items = {}
	if not view then
		return items
	end
	local status = view.summary.status
	local before = status == "draft" or status == "registration" or status == "check_in"
	local manual = before and view.seeding and view.seeding.kind == "manual" and view.role == "organiser"
	if manual then
		items[#items + 1] = { heading = TOM.T("k_tom_seeding_order") }
		local by_id = {}
		for _, e in ipairs(view.entrants or {}) do
			by_id[e.id] = e
		end
		for i, id in ipairs(page.order or {}) do
			local e = by_id[id]
			if e then
				items[#items + 1] = { text = string.format("%d. %s", i, short(e.name, 16)), up = i > 1 and i or nil, remove = id }
			end
		end
	else
		items[#items + 1] = { heading = TOM.T("k_tom_players_upper") }
		for _, e in ipairs(view.entrants or {}) do
			local bits = {}
			if e.seed then
				bits[#bits + 1] = "#" .. e.seed
			end
			if e.rating then
				bits[#bits + 1] = tostring(math.floor(e.rating))
			end
			if status == "check_in" then
				bits[#bits + 1] = TOM.T(e.checkedIn and "k_tom_checked_in_short" or "k_tom_not_checked_in_short")
			end
			local text = short(e.name, 12) .. (#bits > 0 and ("  " .. table.concat(bits, "  ")) or "")
			items[#items + 1] = { text = text, colour = e.dropped and G.C.UI.TEXT_INACTIVE or nil, remove = not e.dropped and status ~= "finished" and status ~= "cancelled" and e.id or nil, drop = status == "running" }
		end
	end
	if #(view.waitlist or {}) > 0 then
		items[#items + 1] = { heading = TOM.T("k_tom_waitlist_upper") }
		for _, w in ipairs(view.waitlist) do
			items[#items + 1] = { text = short(w.name, 18), promote = before and w.id or nil }
		end
	end
	return items
end

local function player_row(item)
	if item.heading then
		return { n = G.UIT.R, config = { align = "cl", minw = LEFT_W, minh = 0.42 }, nodes = { TUI().text(item.heading, TUI().SMALL, G.C.GOLD) } }
	end
	local buttons = {}
	local confirming = item.remove and page.confirm == "remove:" .. item.remove
	-- In the seeding editor a row has UP and a small X (SURE? while asking).
	if item.up and not confirming then
		buttons[#buttons + 1] = TUI().button(TOM.T("k_tom_up"), "tom_manage_seed_up", { index = item.up }, G.C.UI.BACKGROUND_INACTIVE, 0.8, 0.26)
	end
	if item.promote then
		buttons[#buttons + 1] = TUI().button(TOM.T("k_tom_promote"), "tom_manage_player", { what = "promote", user = item.promote }, G.C.GREEN, 1.5, 0.26)
	end
	if item.remove then
		local label, w = TOM.T(item.drop and "k_tom_b_drop" or "k_tom_b_remove"), 1.4
		if confirming then
			label = TOM.T("k_tom_b_sure")
		elseif item.up then
			label, w = "X", 0.6
		end
		buttons[#buttons + 1] = TUI().button(label, "tom_manage_player", { what = "remove", user = item.remove }, G.C.RED, w, 0.26)
	end
	local right = {}
	for _, b in ipairs(buttons) do
		right[#right + 1] = { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { b } }
	end
	return {
		n = G.UIT.R,
		config = { align = "cm", minh = 0.42 },
		nodes = {
			{ n = G.UIT.C, config = { align = "cl", minw = LEFT_W - 1.8 }, nodes = { TUI().text(item.text, TUI().SMALL, item.colour) } },
			{ n = G.UIT.C, config = { align = "cr", minw = 1.8 }, nodes = right },
		},
	}
end

-- Right column rows: matches someone is waiting on.
local function match_items()
	local view = page.view
	local items = {}
	if not view or not view.bracket or view.summary.status ~= "running" then
		return items
	end
	local TT = PVP.TournamentTime
	for _, m in ipairs(view.bracket) do
		local phase = m.clock and m.clock.phase
		local open = (m.status == "ready" or m.status == "in_progress") and type(m.players[1]) == "table" and type(m.players[2]) == "table"
		if open or phase == "unplayed" then
			local state
			if phase == "in_game" then
				state = TOM.T("k_tom_state_playing")
			elseif phase == "unplayed" then
				state = TOM.T("k_tom_state_unplayed")
			elseif phase == "ready_up" and m.clock.deadline then
				state = TOM.T("k_tom_state_to_ready", TT.countdown(m.clock.deadline) or TT.format_local(m.clock.deadline))
			elseif m.lobby and m.lobby.status == "disputed" then
				state = TOM.T("k_tom_state_disputed")
			else
				state = TOM.T("k_tom_state_waiting")
			end
			items[#items + 1] = { match = m, state = state, urgent = phase == "unplayed" or (m.lobby and m.lobby.status == "disputed") }
		end
	end
	-- What needs the organiser first.
	table.sort(items, function(a, b)
		if a.urgent ~= b.urgent then
			return a.urgent
		end
		return a.match.id < b.match.id
	end)
	return items
end

local function match_row(item)
	local m = item.match
	-- The names in full on a line of their own (cut names that start alike
	-- can't be told apart), the score and state beside them, then the buttons.
	local who = string.format("%s%d  %s vs %s", ROUND[m.stage] or m.stage, m.round, short(name_of(m.players[1]), 14), short(name_of(m.players[2]), 14))
	local how = string.format("%d-%d  %s", m.wins and m.wins[1] or 0, m.wins and m.wins[2] or 0, item.state)
	local function win(side)
		local p = m.players[side]
		local key = "win:" .. m.id .. ":" .. side
		local text = page.confirm == key and TOM.T("k_tom_b_sure") or TOM.T("k_tom_b_wins", short(name_of(p), 14))
		return { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { TUI().button(text, "tom_manage_result", { match = m.id, side = side }, G.C.UI.BACKGROUND_INACTIVE, 2.55, 0.22) } }
	end
	return {
		n = G.UIT.R,
		config = { align = "cm", padding = 0.03 },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "cl", minw = RIGHT_W - 0.3 },
				nodes = {
					{
						n = G.UIT.R,
						config = { align = "cl" },
						nodes = {
							{ n = G.UIT.C, config = { align = "cl", minw = RIGHT_W - 2.4 }, nodes = { TUI().text(who, 0.26) } },
							{ n = G.UIT.C, config = { align = "cr", minw = 2.1 }, nodes = { TUI().text(how, 0.24, item.urgent and G.C.RED or G.C.UI.TEXT_INACTIVE) } },
						},
					},
					{
						n = G.UIT.R,
						config = { align = "cr", padding = 0.04 },
						nodes = {
							win(1),
							win(2),
							{ n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { TUI().button("+10M", "tom_manage_extend", { match = m.id }, G.C.UI.BACKGROUND_INACTIVE, 0.8, 0.22) } },
						},
					},
				},
			},
		},
	}
end

-- The order the seeding editor starts from: seeds once there are some, else
-- the saved manual order, then everyone else in join order. (Lua's sort
-- isn't stable, so ties are broken by join order explicitly.)
local function reset_order(view)
	page.order = {}
	local saved = {}
	for i, id in ipairs(view and view.seeding and type(view.seeding.order) == "table" and view.seeding.order or {}) do
		saved[id] = i
	end
	local entrants = {}
	for i, e in ipairs(view and view.entrants or {}) do
		entrants[#entrants + 1] = { e = e, join = i }
	end
	local function rank(x)
		return x.e.seed or saved[x.e.id] or 1000
	end
	table.sort(entrants, function(a, b)
		if rank(a) ~= rank(b) then
			return rank(a) < rank(b)
		end
		return a.join < b.join
	end)
	for _, x in ipairs(entrants) do
		page.order[#page.order + 1] = x.e.id
	end
end

local function build()
	local view = page.view
	if view and not page.order then
		reset_order(view)
	end
	local body = {}
	if not view then
		body[#body + 1] = TUI().message(page.message or TOM.T("k_tom_loading"), page.message_colour)
		body[#body + 1] = TUI().hbox({ TUI().button(TOM.T("k_tom_back"), "tom_manage_back", nil, G.C.ORANGE, 2.0) })
		return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = { TUI().panel(body, { align = "cm", minw = 12 }) } }
	end
	for _, r in ipairs(header(view)) do
		body[#body + 1] = r
	end
	local buttons = { TUI().button(TOM.T("k_tom_back"), "tom_manage_back", nil, G.C.ORANGE, 1.6, 0.3) }
	for _, b in ipairs(actions(view)) do
		buttons[#buttons + 1] = b
	end
	-- At most four to a row, so they fit the panel.
	for first = 1, #buttons, 4 do
		local row = {}
		for i = first, math.min(#buttons, first + 3) do
			row[#row + 1] = buttons[i]
		end
		body[#body + 1] = TUI().hbox(row, "cm", 0.04)
	end
	if page.message then
		body[#body + 1] = TUI().message(page.message, page.message_colour)
	end
	-- The lists live for the whole visit (they keep their scroll position);
	-- each rebuild takes a fresh node from them.
	local columns = {}
	columns[#columns + 1] = { n = G.UIT.C, config = { align = "tm", padding = 0.06, r = 0.1, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5) }, nodes = { page.lists.players.el.node } }
	local seeding_manual = view.role == "organiser" and view.seeding and view.seeding.kind == "manual" and (view.summary.status == "registration" or view.summary.status == "check_in" or view.summary.status == "draft")
	if view.summary.status == "running" then
		columns[#columns + 1] = TUI().spacer(0.15)
		columns[#columns + 1] = {
			n = G.UIT.C,
			config = { align = "tm", padding = 0.06, r = 0.1, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5) },
			nodes = { { n = G.UIT.R, config = { align = "cl" }, nodes = { TUI().text(TOM.T("k_tom_matches"), TUI().SMALL, G.C.GOLD) } }, page.lists.matches.el.node },
		}
	elseif seeding_manual then
		columns[#columns + 1] = TUI().spacer(0.15)
		columns[#columns + 1] = {
			n = G.UIT.C,
			config = { align = "cm", padding = 0.1, minw = 3.4 },
			nodes = {
				{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { TUI().button(TOM.T("k_tom_save_order"), "tom_manage_seed_save", nil, G.C.GREEN, 2.6) } },
				{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { TUI().text(TOM.T("k_tom_up_moves_a_player_one_seed_up"), TUI().SMALL, G.C.UI.TEXT_INACTIVE) } },
			},
		}
	end
	body[#body + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = columns }
	return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = { TUI().panel(body, { align = "cm", minw = 12.4 }) } }
end

local function tick(gen)
	G.E_MANAGER:add_event(Event({
		trigger = "after",
		delay = REFRESH_SECONDS,
		timer = "REAL",
		blockable = false,
		blocking = false,
		func = function()
			if page.active and gen == page.gen then
				load()
				tick(gen)
			end
			return true
		end,
	}))
end

MPAPI.on_loaded(function()
	MPAPI.Page({
		key = "tom_manage",
		category = "game_select",
		build = function(self)
			local id = self.params and self.params.id
			if id ~= page.id then
				page.view = PVP.Tournaments.state.views[id]
				page.confirm = nil
				page.order = nil
			end
			page.id = id
			for _, l in pairs(page.lists) do
				l:dispose()
			end
			page.lists = {
				players = PVP.TUI.scroll_list({ items = player_items, build_row = player_row, visible = 9, row_h = 0.46, width = LEFT_W, empty = TOM.T("k_tom_no_players_yet") }),
				matches = PVP.TUI.scroll_list({ items = match_items, build_row = match_row, visible = 5, row_h = 0.82, width = RIGHT_W, empty = TOM.T("k_tom_no_match_waiting") }),
			}
			page.el = MPAPI.ui_element(build)
			return { n = G.UIT.ROOT, config = { align = "tm", colour = G.C.CLEAR }, nodes = { { n = G.UIT.R, config = { align = "tm", padding = 0.1 }, nodes = { page.el.node } } } }
		end,
		on_enter = function(self)
			PVP.TUI.page_enter()
			page.active = true
			page.gen = (page.gen or 0) + 1
			load()
			tick(page.gen)
		end,
		dispose = function(self)
			page.active = false
			for _, l in pairs(page.lists) do
				l:dispose()
			end
			page.lists = {}
		end,
	})
end)

-- CO-ORGANISERS (the organiser): the code to share, NEW CODE, and the
-- co-organisers with REMOVE. Updated in place.
local coorg = nil -- { el, confirm }

local COORG_W = 9.4

local function box(nodes)
	return {
		n = G.UIT.R,
		config = { align = "cm", padding = 0.08 },
		nodes = { { n = G.UIT.C, config = { align = "cm", minw = COORG_W, padding = 0.1, r = 0.1, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5) }, nodes = nodes } },
	}
end

local function coorg_contents()
	local view = page.view
	local code = view and view.coOrganiserCode
	local list = view and view.coOrganisers or {}
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = { TUI().text(TOM.T("k_tom_co_organisers"), 0.45, G.C.PURPLE) } },
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(TOM.T("k_tom_they_help_run_it_results_deadlines_p"), TUI().SMALL, G.C.UI.TEXT_INACTIVE) } },
	}
	-- The code to share.
	local code_row
	if code then
		code_row = TUI().hbox({
			{ n = G.UIT.C, config = { align = "cm", minw = 2.6, minh = 0.7, r = 0.1, colour = G.C.BLACK }, nodes = { TUI().text(code, 0.5, G.C.GOLD) } },
			TUI().button(TOM.T("k_tom_copy"), "tom_coorg_copy", nil, G.C.GREEN, 1.4, 0.3),
			TUI().button(TOM.T("k_tom_new_code"), "tom_coorg_code", nil, G.C.BLUE, 2.0, 0.3),
		}, "cm", 0.08)
	else
		code_row = TUI().hbox({ TUI().button(TOM.T("k_tom_make_a_code"), "tom_coorg_code", nil, G.C.BLUE, 2.6, 0.3) }, "cm", 0.08)
	end
	rows[#rows + 1] = box({
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(TOM.T("k_tom_share_this_code"), TUI().SMALL, G.C.GOLD) } },
		code_row,
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(TOM.T("k_tom_they_enter_it_with_join_as_co_organi"), 0.24, G.C.UI.TEXT_INACTIVE) } },
	})
	-- Who helps now.
	local people = {
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(TOM.T("k_tom_co_organisers_count", #list, 5), TUI().SMALL, G.C.GOLD) } },
	}
	if #list == 0 then
		people[#people + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = { TUI().text(TOM.T("k_tom_nobody_yet"), TUI().SMALL, G.C.UI.TEXT_INACTIVE) } }
	end
	for _, c in ipairs(list) do
		local sure = coorg.confirm == c.id
		people[#people + 1] = {
			n = G.UIT.R,
			config = { align = "cm", padding = 0.02 },
			nodes = {
				{ n = G.UIT.C, config = { align = "cl", minw = COORG_W - 2.4 }, nodes = { TUI().text(c.name, TUI().TEXT) } },
				{ n = G.UIT.C, config = { align = "cr", minw = 2.0 }, nodes = { TUI().button(sure and "SURE?" or "REMOVE", "tom_coorg_remove", { id = c.id }, G.C.RED, 1.6, 0.28) } },
			},
		}
	end
	rows[#rows + 1] = box(people)
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", minh = 0.4 }, nodes = { TUI().text(coorg.message or " ", TUI().SMALL, coorg.message_colour or G.C.UI.TEXT_INACTIVE) } }
	rows[#rows + 1] = TUI().hbox({ TUI().button(TOM.T("k_tom_done"), "tom_coorg_done", nil, G.C.GREEN, 2.2) }, "cm", 0.06)
	return rows
end

local function coorg_refresh()
	if coorg and coorg.el then
		coorg.el:update()
	end
end

function TOM.open_coorganisers(view)
	coorg = {}
	-- A fixed width: it updates in place, and a box can't grow after it is laid out.
	coorg.el = MPAPI.ui_element(function()
		return { nodes = { { n = G.UIT.C, config = { align = "cm", minw = COORG_W + 0.4 }, nodes = coorg_contents() } } }
	end)
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			no_back = true,
			contents = { { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { coorg.el.node } } },
		}),
	})
end

-- Runs a co-organiser RPC, then shows the tournament's new view.
local function coorg_call(rpc_id, body)
	body.id = page.id
	PVP.Tournaments.call(rpc_id, body, function(err, data)
		if not coorg then
			return
		end
		if err then
			coorg.message, coorg.message_colour = UI.error_text(err), G.C.RED
		elseif data and data.tournament then
			page.view = data.tournament
			coorg.message = nil
		end
		coorg.confirm = nil
		coorg_refresh()
	end)
end

G.FUNCS.tom_coorg_copy = function()
	local code = page.view and page.view.coOrganiserCode
	if code and coorg then
		love.system.setClipboardText(code)
		coorg.message, coorg.message_colour = TOM.T("k_tom_copied", code), G.C.GREEN
		coorg_refresh()
	end
end

G.FUNCS.tom_coorg_code = function()
	coorg_call("tournament_co_organiser_code", {})
end

G.FUNCS.tom_coorg_remove = function(e)
	local id = e.config.ref_table and e.config.ref_table.id
	if not id or not coorg then
		return
	end
	if coorg.confirm ~= id then
		coorg.confirm = id
		coorg_refresh()
		return
	end
	local keep = {}
	for _, c in ipairs(page.view and page.view.coOrganisers or {}) do
		if c.id ~= id then
			keep[#keep + 1] = c.id
		end
	end
	-- An empty list would be sent as [] -- what the server wants here.
	coorg_call("tournament_co_organisers_set", { userIds = keep })
end

G.FUNCS.tom_coorg_done = function()
	coorg = nil
	G.FUNCS.exit_overlay_menu()
	rebuild()
end

-- NOTICE BOARD and MESSAGE PLAYERS: a few lines of text in an overlay that
-- updates in place. Lines short enough to fit their box: 4 x 75 is the
-- server's notice limit (300), 3 x 66 within its message limit (200).
local SHAPE = { notice = { lines = 4, width = 75 }, message = { lines = 3, width = 66 } }
local talk = nil -- { kind = "notice" | "message", el, form, target, message, colour, busy }

-- The matches with a lobby open, for MESSAGE PLAYERS' "To": nil is all of them.
local function lobby_matches(view)
	local out = {}
	for _, m in ipairs(view and view.bracket or {}) do
		if m.lobby and (m.lobby.status == "open" or m.lobby.status == "disputed") then
			out[#out + 1] = m
		end
	end
	return out
end

local function talk_target_label()
	if not talk.target then
		local n = #lobby_matches(page.view)
		return TOM.T("k_tom_all_open_lobbies", n)
	end
	for _, m in ipairs(lobby_matches(page.view)) do
		if m.id == talk.target then
			return string.format("%s%d  %s vs %s", ROUND[m.stage] or m.stage, m.round, short(name_of(m.players[1]), 12), short(name_of(m.players[2]), 12))
		end
	end
	return tostring(talk.target)
end

local function talk_contents()
	local notice = talk.kind == "notice"
	local count, width = SHAPE[talk.kind].lines, SHAPE[talk.kind].width
	UI.target = { form = talk.form, lists = {}, on_change = function() end }
	local rows = {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = { TUI().text(notice and "NOTICE BOARD" or "MESSAGE PLAYERS", 0.45, G.C.PURPLE) } },
		{
			n = G.UIT.R,
			config = { align = "cm" },
			nodes = {
				TUI().text(
					TOM.T(notice and "k_tom_notice_sub" or "k_tom_message_sub"),
					TUI().SMALL,
					G.C.UI.TEXT_INACTIVE
				),
			},
		},
	}
	if not notice then
		rows[#rows + 1] = { n = G.UIT.R, config = { minh = 0.15 } }
		rows[#rows + 1] = TUI().hbox({
			{ n = G.UIT.C, config = { align = "cm", minw = 1.0 }, nodes = { TUI().text(TOM.T("k_tom_to"), TUI().SMALL, G.C.UI.TEXT_INACTIVE) } },
			{ n = G.UIT.C, config = { align = "cm", minw = 6.6, minh = 0.5, r = 0.1, colour = G.C.BLACK }, nodes = { TUI().text(talk_target_label(), TUI().SMALL) } },
			TUI().button(TOM.T("k_tom_change"), "tom_talk_target", nil, G.C.BLUE, 1.6, 0.3),
		}, "cm", 0.08)
	end
	-- A text box draws taller than its row: gaps keep it off the text around.
	rows[#rows + 1] = { n = G.UIT.R, config = { minh = 0.2 } }
	for i = 1, count do
		rows[#rows + 1] = {
			n = G.UIT.R,
			config = { align = "cm", padding = 0.07 },
			nodes = { UI.text_box("tom_talk_" .. i, "line" .. i, { max_length = width, w = 11.5, text_scale = 0.28, prompt = i == 1 and (notice and "e.g. Round 2 starts at 9 PM. Finals on stream!" or "e.g. Please ready up, your opponent is waiting.") or "" }) },
		}
	end
	rows[#rows + 1] = { n = G.UIT.R, config = { minh = 0.2 } }
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", minh = 0.4 }, nodes = { TUI().text(talk.message or "Up to " .. count .. " lines of " .. width .. " characters. Ctrl+V pastes.", TUI().SMALL, talk.colour or G.C.UI.TEXT_INACTIVE) } }
	local buttons = { TUI().button(TOM.T("k_tom_cancel"), "tom_talk_close", nil, G.C.ORANGE, 1.8) }
	if notice then
		buttons[#buttons + 1] = TUI().button(TOM.T("k_tom_clear"), "tom_talk_clear", nil, G.C.RED, 1.8)
	end
	buttons[#buttons + 1] = TUI().spacer(notice and 3.4 or 5.4)
	buttons[#buttons + 1] = TUI().button(talk.busy and "..." or (notice and "SAVE" or "SEND"), "tom_talk_send", nil, G.C.GREEN, 2.2)
	rows[#rows + 1] = TUI().hbox(buttons, "cm", 0.1)
	return rows
end

local function talk_refresh(message, colour)
	if not talk then
		return
	end
	talk.message, talk.colour = message, colour
	if talk.el then
		talk.el:update()
	end
end

local function open_talk(kind, view)
	local count, width = SHAPE[kind].lines, SHAPE[kind].width
	talk = { kind = kind, form = {}, target = nil }
	local text = kind == "notice" and view.notice or ""
	for i, line in ipairs(TOM.Form.split_description(text, count, width)) do
		talk.form["line" .. i] = line
	end
	talk.el = MPAPI.ui_element(function()
		return { nodes = { { n = G.UIT.C, config = { align = "cm", minw = 12.2 }, nodes = talk_contents() } } }
	end)
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			no_back = true,
			contents = { { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { talk.el.node } } },
		}),
	})
end

function TOM.open_notice(view)
	open_talk("notice", view)
end

function TOM.open_message(view)
	open_talk("message", view)
end

local function talk_text()
	local count = SHAPE[talk.kind].lines
	local lines = {}
	for i = 1, count do
		lines[i] = talk.form["line" .. i] or ""
	end
	return TOM.Form.join_description(lines, count)
end

local function talk_done(text)
	talk = nil
	G.FUNCS.exit_overlay_menu()
	say(text, G.C.GREEN)
	load()
end

-- CHANGE: all open lobbies, then each match with a lobby, then all again.
G.FUNCS.tom_talk_target = function()
	if not talk then
		return
	end
	local matches = lobby_matches(page.view)
	local next_target = nil
	if not talk.target then
		next_target = matches[1] and matches[1].id or nil
	else
		for i, m in ipairs(matches) do
			if m.id == talk.target then
				next_target = matches[i + 1] and matches[i + 1].id or nil
			end
		end
	end
	talk.target = next_target
	talk_refresh(nil)
end

G.FUNCS.tom_talk_close = function()
	talk = nil
	G.FUNCS.exit_overlay_menu()
end

G.FUNCS.tom_talk_clear = function()
	if not talk then
		return
	end
	for k in pairs(talk.form) do
		talk.form[k] = ""
	end
	talk_refresh(TOM.T("k_tom_notice_cleared_hint"), G.C.ORANGE)
end

G.FUNCS.tom_talk_send = function()
	if not talk or talk.busy then
		return
	end
	local text = talk_text()
	local notice = talk.kind == "notice"
	if not notice and not text:match("%S") then
		talk_refresh(TOM.T("k_tom_write_message_first"), G.C.RED)
		return
	end
	talk.busy = true
	talk_refresh(nil)
	local body = { id = page.id, text = text }
	if not notice then
		body.matchId = talk.target
	end
	PVP.Tournaments.call(notice and "tournament_notice_set" or "tournament_message", body, function(err, data)
		if not talk then
			return
		end
		talk.busy = false
		if err then
			talk_refresh(UI.error_text(err), G.C.RED)
			return
		end
		if notice then
			if data and data.tournament then
				page.view = data.tournament
			end
			talk_done(text:match("%S") and "Notice board updated." or "Notice board cleared.")
		else
			local sent = data and data.sent or 0
			talk_done(TOM.Form.count(sent, "k_tom_message_sent"))
		end
	end)
end

function TOM.open_manage(id, message)
	page.message, page.message_colour = message, message and G.C.ORANGE or nil
	MPAPI.pages.show("tom_manage", { id = id })
end

G.FUNCS.tom_manage_back = function()
	MPAPI.pages.show("pvp_tournament_organise", {})
end

-- Buttons that need a second press to be sure.
local function confirmed(key)
	if page.confirm == key then
		return true
	end
	page.confirm = key
	rebuild()
	return false
end

G.FUNCS.tom_manage_do = function(e)
	local what = e.config.ref_table and e.config.ref_table.what
	if what == "open" then
		act("tournament_open", {}, TOM.T("k_tom_done_open"))
	elseif what == "close_reg" then
		act("tournament_registration_set", { closed = true }, TOM.T("k_tom_done_closed"))
	elseif what == "open_reg" then
		act("tournament_registration_set", { closed = false }, TOM.T("k_tom_done_reopened"))
	elseif what == "start" and confirmed("start") then
		act("tournament_start", {}, TOM.T("k_tom_done_started"))
	elseif what == "pause" then
		act("tournament_pause", {}, TOM.T("k_tom_done_paused"))
	elseif what == "resume" then
		act("tournament_resume", {}, TOM.T("k_tom_done_resumed"))
	elseif what == "round" then
		act("tournament_round_start", {}, TOM.T("k_tom_done_round"))
	elseif what == "cancel" and confirmed("cancel") then
		act("tournament_cancel", {}, TOM.T("k_tom_done_cancelled"))
	elseif what == "bots" then
		act("tournament_dev_fill", { count = e.config.ref_table.count }, TOM.T("k_tom_done_bots", e.config.ref_table.count))
	elseif what == "notice" then
		if page.view then
			TOM.open_notice(page.view)
		end
	elseif what == "message" then
		if page.view then
			TOM.open_message(page.view)
		end
	elseif what == "coorg" then
		if page.view then
			TOM.open_coorganisers(page.view)
		end
	elseif what == "edit" then
		if page.view then
			TOM.open_edit(page.view)
		end
	elseif what == "bracket" then
		PVP.open_tournament_bracket(page.id)
	end
end

G.FUNCS.tom_manage_player = function(e)
	local ref = e.config.ref_table
	if not ref then
		return
	end
	if ref.what == "promote" then
		act("tournament_promote", { userId = ref.user }, TOM.T("k_tom_done_promoted"))
	elseif ref.what == "remove" and confirmed("remove:" .. ref.user) then
		act("tournament_remove_player", { userId = ref.user }, TOM.T("k_tom_done_removed"))
	end
end

G.FUNCS.tom_manage_result = function(e)
	local ref = e.config.ref_table
	local m
	for _, x in ipairs(page.view and page.view.bracket or {}) do
		if x.id == (ref and ref.match) then
			m = x
		end
	end
	local p = m and m.players[ref.side]
	if type(p) ~= "table" or not confirmed("win:" .. m.id .. ":" .. ref.side) then
		return
	end
	act("tournament_result_set", { matchId = m.id, scope = "match", winner = p.id }, TOM.T("k_tom_done_wins", p.name, m.id))
end

G.FUNCS.tom_manage_extend = function(e)
	local ref = e.config.ref_table
	if ref then
		act("tournament_extend", { matchId = ref.match, minutes = 10 }, TOM.T("k_tom_done_extended", ref.match))
	end
end

G.FUNCS.tom_manage_seed_up = function(e)
	local i = e.config.ref_table and e.config.ref_table.index
	if page.order and i and i > 1 then
		page.order[i - 1], page.order[i] = page.order[i], page.order[i - 1]
		page.confirm = nil
		if page.lists.players then
			page.lists.players:update()
		end
	end
end

G.FUNCS.tom_manage_seed_save = function()
	if page.order then
		act("tournament_seeding_set", { order = page.order }, TOM.T("k_tom_done_seeding"))
	end
end

-- Any tournament change elsewhere (notifications, the tab's refresh) shows
-- here. PvP's tournament code exists once everything has loaded.
MPAPI.on_loaded(function()
	PVP.Tournaments.on_change(function()
		if page.active and page.id then
			local cached = PVP.Tournaments.state.views[page.id]
			local runs = cached and (cached.role == "organiser" or cached.role == "co_organiser")
			if cached and runs and cached ~= page.view then
				page.view = cached
				rebuild()
			end
		end
	end)
end)
