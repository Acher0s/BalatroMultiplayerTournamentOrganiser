-- What this mod adds to PvP's ORGANISE page (PVP.register_tournament_section):
-- NEW TOURNAMENT, and the tournaments the player runs (organiser or
-- co-organiser), newest activity first, each with MANAGE.

local SHOWN = 6
local WIDTH = 12.4

local STATUS = { draft = "Draft", registration = "Registration", check_in = "Check-in", running = "Running", finished = "Finished", cancelled = "Cancelled" }
local ORDER = { running = 1, check_in = 2, registration = 3, draft = 4, finished = 5, cancelled = 6 }

-- SHOW FINISHED: finished and cancelled ones are hidden until asked for.
local section = { finished = false, el = nil }
local OVER = { finished = true, cancelled = true }

local function run_by_me()
	local out = {}
	for _, t in ipairs(PVP.Tournaments.state.mine or {}) do
		local runs = t.organiser or t.role == "organiser" or t.role == "co_organiser"
		if runs and (section.finished or not OVER[t.status]) then
			out[#out + 1] = t
		end
	end
	table.sort(out, function(a, b)
		local oa, ob = ORDER[a.status] or 9, ORDER[b.status] or 9
		if oa ~= ob then
			return oa < ob
		end
		return (a.startsAt or 0) > (b.startsAt or 0)
	end)
	return out
end

local function build_inner()
	local TUI = PVP.TUI
	local TT = PVP.TournamentTime
	local rows = {
		{
			n = G.UIT.R,
			config = { align = "cm", padding = 0.06 },
			nodes = {
				{ n = G.UIT.C, config = { align = "cl", minw = WIDTH - 7.6 }, nodes = { TUI.text("TOURNAMENTS YOU RUN", 0.36, G.C.PURPLE) } },
				{
					n = G.UIT.C,
					config = { align = "cr", minw = 3.4 },
					nodes = {
						{
							n = G.UIT.R,
							config = { align = "cr" },
							nodes = {
								{ n = G.UIT.C, config = { align = "cm", padding = 0.03 }, nodes = { TUI.button("JOIN AS CO-ORGANISER", "tom_section_coorg", nil, G.C.UI.BACKGROUND_INACTIVE, 4.0) } },
								{ n = G.UIT.C, config = { align = "cm", padding = 0.03 }, nodes = { TUI.button("NEW TOURNAMENT", "tom_section_new", nil, G.C.GREEN, 3.2) } },
							},
						},
					},
				},
			},
		},
	}
	local mine = run_by_me()
	if #mine == 0 then
		local none = section.finished and "You don't run any tournaments yet." or "No tournaments on the go."
		rows[#rows + 1] = TUI.message(PVP.Tournaments.state.mine and none or "Loading...")
	end
	for i = 1, math.min(#mine, SHOWN) do
		local t = mine[i]
		local when = (t.status == "registration" or t.status == "check_in" or t.status == "draft") and ("  -  " .. TT.format_local(t.startsAt)) or ""
		local info = string.format("%s  -  %s  -  %d/%d%s", STATUS[t.status] or t.status, TUI.format_name(t.format), t.players or 0, t.maxPlayers or 0, when)
		rows[#rows + 1] = TUI.row({
			TUI.name_line(t, 0.34),
			{ n = G.UIT.R, config = { align = "cl" }, nodes = { TUI.text(info, TUI.SMALL, G.C.UI.TEXT_INACTIVE) } },
		}, { TUI.button("MANAGE", "tom_section_manage", { id = t.id }, G.C.PURPLE, 1.8) }, WIDTH, t.official)
	end
	-- Under the list: how many more, and SHOW / HIDE FINISHED.
	local foot = {}
	if #mine > SHOWN then
		foot[#foot + 1] = { n = G.UIT.C, config = { align = "cm", padding = 0.06 }, nodes = { TUI.text("+" .. (#mine - SHOWN) .. " older", TUI.SMALL, G.C.UI.TEXT_INACTIVE) } }
	end
	foot[#foot + 1] = { n = G.UIT.C, config = { align = "cm", padding = 0.03 }, nodes = { TUI.button(section.finished and "HIDE FINISHED" or "SHOW FINISHED", "tom_section_finished", nil, G.C.UI.BACKGROUND_INACTIVE, 2.8, 0.3) } }
	rows[#rows + 1] = { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = foot }
	return { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { { n = G.UIT.C, config = { align = "tm" }, nodes = rows } } }
end

-- Its own element, so SHOW FINISHED redraws just this section.
local function build()
	section.el = MPAPI.ui_element(function()
		return { nodes = { build_inner() } }
	end)
	return { n = G.UIT.R, config = { align = "cm" }, nodes = { section.el.node } }
end

G.FUNCS.tom_section_finished = function()
	section.finished = not section.finished
	if section.el then
		section.el:update()
	end
end

MPAPI.on_loaded(function()
	if not PVP or not PVP.register_tournament_section then
		sendWarnMessage("This PvP has no tournament sections; the Organiser mod needs a newer PvP.", "TournamentOrganiser")
		return
	end
	PVP.register_tournament_section({ key = "organiser", build = build })
end)

-- JOIN AS CO-ORGANISER: enter the code an organiser shared. An overlay that
-- updates in place (PASTE, messages).
local join = { code = "", el = nil, message = nil, colour = nil }

local function join_contents()
	local TUI = PVP.TUI
	TOM.UI.target = { form = join, lists = {}, on_change = function() end }
	return {
		{ n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = { TUI.text("JOIN AS CO-ORGANISER", 0.45, G.C.PURPLE) } },
		{ n = G.UIT.R, config = { align = "cm" }, nodes = { TUI.text("Enter the code the tournament's organiser gave you.", TUI.SMALL, G.C.UI.TEXT_INACTIVE) } },
		-- Columns, so the box and PASTE sit side by side.
		{
			n = G.UIT.R,
			config = { align = "cm", padding = 0.12 },
			nodes = {
				{ n = G.UIT.C, config = { align = "cm" }, nodes = { TOM.UI.text_box("tom_coorg_join_code", "code", { max_length = 6, w = 2.6, prompt = "CODE" }) } },
				TUI.spacer(0.15),
				{ n = G.UIT.C, config = { align = "cm" }, nodes = { TUI.button("PASTE", "tom_section_coorg_paste", nil, G.C.BLUE, 1.6, 0.3) } },
			},
		},
		{ n = G.UIT.R, config = { align = "cm", minh = 0.4 }, nodes = { TUI.text(join.message or " ", TUI.SMALL, join.colour or G.C.UI.TEXT_INACTIVE) } },
		TUI.hbox({
			TUI.button("CANCEL", "tom_section_coorg_close", nil, G.C.ORANGE, 1.8),
			TUI.spacer(1.0),
			TUI.button("JOIN", "tom_section_coorg_join", nil, G.C.GREEN, 2.2),
		}, "cm", 0.08),
	}
end

local function join_refresh(message, colour)
	join.message, join.colour = message, colour
	if join.el then
		join.el:update()
	end
end

G.FUNCS.tom_section_coorg = function()
	join.code, join.message = "", nil
	join.el = MPAPI.ui_element(function()
		return { nodes = { { n = G.UIT.C, config = { align = "cm", minw = 7.6 }, nodes = join_contents() } } }
	end)
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			no_back = true,
			contents = { { n = G.UIT.R, config = { align = "cm", padding = 0.1 }, nodes = { join.el.node } } },
		}),
	})
end

-- The clipboard's code (letters and digits only, at most 6).
G.FUNCS.tom_section_coorg_paste = function()
	local text = love.system.getClipboardText() or ""
	join.code = text:upper():gsub("[^%w]", ""):sub(1, 6)
	join_refresh(nil)
end

G.FUNCS.tom_section_coorg_close = function()
	join.el = nil
	G.FUNCS.exit_overlay_menu()
end

G.FUNCS.tom_section_coorg_join = function()
	local code = (join.code or ""):upper():gsub("%s", "")
	if #code == 0 then
		join_refresh("Enter the code first.", G.C.RED)
		return
	end
	PVP.Tournaments.call("tournament_co_organiser_join", { code = code }, function(err, data)
		local t = not err and data and data.tournament
		if not t then
			join_refresh(TOM.UI.error_text(err or "No answer"), G.C.RED)
			return
		end
		join.el = nil
		G.FUNCS.exit_overlay_menu()
		PVP.Tournaments.refresh()
		TOM.open_manage(t.summary.id, "You're a co-organiser of " .. tostring(t.summary.name) .. ".")
	end)
end

G.FUNCS.tom_section_new = function()
	TOM.open_create(false)
end

G.FUNCS.tom_section_manage = function(e)
	local id = e.config.ref_table and e.config.ref_table.id
	if id then
		TOM.open_manage(id)
	end
end
