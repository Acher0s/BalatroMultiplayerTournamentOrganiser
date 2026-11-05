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
local LEFT_W = 6.2
local RIGHT_W = 7.4

local function TUI()
	return PVP.TUI
end

local STATUS = { draft = "Draft", registration = "Registration open", check_in = "Check-in", running = "Running", finished = "Finished", cancelled = "Cancelled" }
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
			say(UI.error_text(err or "The server sent no tournament"), G.C.RED)
			return
		end
		page.view = data.tournament
		PVP.Tournaments.state.views[page.id] = data.tournament
		rebuild()
	end)
end

-- An organiser action: say what failed, else reload.
local function act(rpc_id, body, done_text)
	body.id = page.id
	page.confirm = nil
	say("Working...", G.C.UI.TEXT_INACTIVE)
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
		return "TBD"
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
	if view.bracket then
		add("BRACKET", "tom_manage_do", { what = "bracket" }, G.C.BLUE, 2.0)
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
		when = "Starts " .. TT.format_local(s.startsAt) .. (left and ("  (in " .. left .. ")") or "")
	elseif s.status == "running" then
		when = view.paused and "Paused: deadlines are stopped" or "Running"
	else
		when = STATUS[s.status] or s.status
	end
	local info = string.format("%s  -  %s  -  %d/%d players", STATUS[s.status] or s.status, TUI().format_name(s.format), s.players, s.maxPlayers)
	if s.waitlist and s.waitlist > 0 then
		info = info .. ", " .. s.waitlist .. " waiting"
	end
	local rows = {
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().name_line(s, 0.45) } },
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(info, TUI().TEXT, G.C.UI.TEXT_INACTIVE) } },
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text(when, TUI().TEXT, view.paused and G.C.ORANGE or G.C.GOLD) } },
	}
	if view.inviteCode then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm" }, nodes = { TUI().text("Invite code: " .. view.inviteCode, TUI().TEXT, G.C.BLUE) } }
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
	local manual = before and view.seeding and view.seeding.kind == "manual"
	if manual then
		items[#items + 1] = { heading = "SEEDING ORDER (top = seed 1)" }
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
		items[#items + 1] = { heading = "PLAYERS" }
		for _, e in ipairs(view.entrants or {}) do
			local bits = {}
			if e.seed then
				bits[#bits + 1] = "#" .. e.seed
			end
			if e.rating then
				bits[#bits + 1] = tostring(math.floor(e.rating))
			end
			if status == "check_in" then
				bits[#bits + 1] = e.checkedIn and "in" or "not in"
			end
			local text = short(e.name, 16) .. (#bits > 0 and ("  " .. table.concat(bits, "  ")) or "")
			items[#items + 1] = { text = text, colour = e.dropped and G.C.UI.TEXT_INACTIVE or nil, remove = not e.dropped and status ~= "finished" and status ~= "cancelled" and e.id or nil, drop = status == "running" }
		end
	end
	if #(view.waitlist or {}) > 0 then
		items[#items + 1] = { heading = "WAITLIST" }
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
	if item.up then
		buttons[#buttons + 1] = TUI().button("UP", "tom_manage_seed_up", { index = item.up }, G.C.UI.BACKGROUND_INACTIVE, 0.8, 0.26)
	end
	if item.promote then
		buttons[#buttons + 1] = TUI().button("PROMOTE", "tom_manage_player", { what = "promote", user = item.promote }, G.C.GREEN, 1.5, 0.26)
	end
	if item.remove and not item.up then
		local key = "remove:" .. item.remove
		local label = page.confirm == key and "SURE?" or (item.drop and "DROP" or "REMOVE")
		buttons[#buttons + 1] = TUI().button(label, "tom_manage_player", { what = "remove", user = item.remove }, G.C.RED, 1.4, 0.26)
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
				state = "playing"
			elseif phase == "unplayed" then
				state = "NOT PLAYED"
			elseif phase == "ready_up" and m.clock.deadline then
				state = (TT.countdown(m.clock.deadline) or TT.format_local(m.clock.deadline)) .. " to ready"
			elseif m.lobby and m.lobby.status == "disputed" then
				state = "DISPUTED"
			else
				state = "waiting"
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
	local label = string.format("%s%d  %s %d-%d %s", ROUND[m.stage] or m.stage, m.round, short(name_of(m.players[1]), 10), m.wins and m.wins[1] or 0, m.wins and m.wins[2] or 0, short(name_of(m.players[2]), 10))
	local function win(side)
		local p = m.players[side]
		local key = "win:" .. m.id .. ":" .. side
		local text = page.confirm == key and "SURE?" or (short(name_of(p), 7) .. " WINS")
		return { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { TUI().button(text, "tom_manage_result", { match = m.id, side = side }, G.C.UI.BACKGROUND_INACTIVE, 1.6, 0.24) } }
	end
	return {
		n = G.UIT.R,
		config = { align = "cm", minh = 0.82, padding = 0.02 },
		nodes = {
			{
				n = G.UIT.C,
				config = { align = "cl", minw = RIGHT_W - 3.6 },
				nodes = {
					{ n = G.UIT.R, config = { align = "cl" }, nodes = { TUI().text(label, TUI().SMALL) } },
					{ n = G.UIT.R, config = { align = "cl" }, nodes = { TUI().text(item.state, TUI().SMALL, item.urgent and G.C.RED or G.C.UI.TEXT_INACTIVE) } },
				},
			},
			{
				n = G.UIT.C,
				config = { align = "cr", minw = 3.6 },
				nodes = {
					{ n = G.UIT.R, config = { align = "cr" }, nodes = { win(1), win(2) } },
					{ n = G.UIT.R, config = { align = "cr" }, nodes = { { n = G.UIT.C, config = { align = "cm", padding = 0.02 }, nodes = { TUI().button("+10 MIN", "tom_manage_extend", { match = m.id }, G.C.UI.BACKGROUND_INACTIVE, 1.6, 0.24) } } } },
				},
			},
		},
	}
end

-- The order the seeding editor starts from: the saved one, else join order.
local function reset_order(view)
	page.order = {}
	local entrants = {}
	for _, e in ipairs(view and view.entrants or {}) do
		entrants[#entrants + 1] = e
	end
	table.sort(entrants, function(a, b)
		return (a.seed or 1000) < (b.seed or 1000)
	end)
	for _, e in ipairs(entrants) do
		page.order[#page.order + 1] = e.id
	end
end

local function build()
	local view = page.view
	if view and not page.order then
		reset_order(view)
	end
	local body = {}
	if not view then
		body[#body + 1] = TUI().message(page.message or "Loading...", page.message_colour)
		body[#body + 1] = TUI().hbox({ TUI().button("BACK", "tom_manage_back", nil, G.C.ORANGE, 2.0) })
		return { n = G.UIT.ROOT, config = { align = "cm", colour = G.C.CLEAR }, nodes = { TUI().panel(body, { align = "cm", minw = 12 }) } }
	end
	for _, r in ipairs(header(view)) do
		body[#body + 1] = r
	end
	local buttons = { TUI().button("BACK", "tom_manage_back", nil, G.C.ORANGE, 1.6, 0.3) }
	for _, b in ipairs(actions(view)) do
		buttons[#buttons + 1] = b
	end
	body[#body + 1] = TUI().hbox(buttons, "cm", 0.04)
	if page.message then
		body[#body + 1] = TUI().message(page.message, page.message_colour)
	end
	-- The lists live for the whole visit (they keep their scroll position);
	-- each rebuild takes a fresh node from them.
	local columns = {}
	columns[#columns + 1] = { n = G.UIT.C, config = { align = "tm", padding = 0.06, r = 0.1, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5) }, nodes = { page.lists.players.el.node } }
	local seeding_manual = view.seeding and view.seeding.kind == "manual" and (view.summary.status == "registration" or view.summary.status == "check_in" or view.summary.status == "draft")
	if view.summary.status == "running" then
		columns[#columns + 1] = TUI().spacer(0.15)
		columns[#columns + 1] = {
			n = G.UIT.C,
			config = { align = "tm", padding = 0.06, r = 0.1, colour = mix_colours(G.C.BLACK, G.C.L_BLACK, 0.5) },
			nodes = { { n = G.UIT.R, config = { align = "cl" }, nodes = { TUI().text("MATCHES", TUI().SMALL, G.C.GOLD) } }, page.lists.matches.el.node },
		}
	elseif seeding_manual then
		columns[#columns + 1] = TUI().spacer(0.15)
		columns[#columns + 1] = {
			n = G.UIT.C,
			config = { align = "cm", padding = 0.1, minw = 3.4 },
			nodes = {
				{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { TUI().button("SAVE ORDER", "tom_manage_seed_save", nil, G.C.GREEN, 2.6) } },
				{ n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { TUI().text("UP moves a player one seed up.", TUI().SMALL, G.C.UI.TEXT_INACTIVE) } },
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
				players = PVP.TUI.scroll_list({ items = player_items, build_row = player_row, visible = 9, row_h = 0.46, width = LEFT_W, empty = "No players yet." }),
				matches = PVP.TUI.scroll_list({ items = match_items, build_row = match_row, visible = 5, row_h = 0.86, width = RIGHT_W, empty = "Nothing to do: no match is waiting." }),
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
		act("tournament_open", {}, "Registration is open.")
	elseif what == "close_reg" then
		act("tournament_registration_set", { closed = true }, "Registration is closed.")
	elseif what == "open_reg" then
		act("tournament_registration_set", { closed = false }, "Registration is open again.")
	elseif what == "start" and confirmed("start") then
		act("tournament_start", {}, "Started.")
	elseif what == "pause" then
		act("tournament_pause", {}, "Paused: deadlines are stopped.")
	elseif what == "resume" then
		act("tournament_resume", {}, "Resumed.")
	elseif what == "round" then
		act("tournament_round_start", {}, "The next round has started.")
	elseif what == "cancel" and confirmed("cancel") then
		act("tournament_cancel", {}, "Cancelled.")
	elseif what == "bots" then
		act("tournament_dev_fill", { count = e.config.ref_table.count }, "Added " .. e.config.ref_table.count .. " bots.")
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
		act("tournament_promote", { userId = ref.user }, "Moved into the tournament.")
	elseif ref.what == "remove" and confirmed("remove:" .. ref.user) then
		act("tournament_remove_player", { userId = ref.user }, "Removed.")
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
	act("tournament_result_set", { matchId = m.id, scope = "match", winner = p.id }, p.name .. " wins " .. m.id .. ".")
end

G.FUNCS.tom_manage_extend = function(e)
	local ref = e.config.ref_table
	if ref then
		act("tournament_extend", { matchId = ref.match, minutes = 10 }, "10 more minutes for " .. ref.match .. ".")
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
		act("tournament_seeding_set", { order = page.order }, "Seeding saved.")
	end
end

-- Any tournament change elsewhere (notifications, the tab's refresh) shows
-- here. PvP's tournament code exists once everything has loaded.
MPAPI.on_loaded(function()
	PVP.Tournaments.on_change(function()
		if page.active and page.id then
			local cached = PVP.Tournaments.state.views[page.id]
			if cached and cached ~= page.view then
				page.view = cached
				rebuild()
			end
		end
	end)
end)
