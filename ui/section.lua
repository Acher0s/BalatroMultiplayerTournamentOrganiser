-- What this mod adds to PvP's ORGANISE page (PVP.register_tournament_section):
-- NEW TOURNAMENT, and the tournaments the player runs (organiser or
-- co-organiser), newest activity first, each with MANAGE.

local SHOWN = 6
local WIDTH = 12.4

local STATUS = { draft = "Draft", registration = "Registration", check_in = "Check-in", running = "Running", finished = "Finished", cancelled = "Cancelled" }
local ORDER = { running = 1, check_in = 2, registration = 3, draft = 4, finished = 5, cancelled = 6 }

local function run_by_me()
	local out = {}
	for _, t in ipairs(PVP.Tournaments.state.mine or {}) do
		if t.organiser or t.role == "organiser" or t.role == "co_organiser" then
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

local function build()
	local TUI = PVP.TUI
	local TT = PVP.TournamentTime
	local rows = {
		{
			n = G.UIT.R,
			config = { align = "cm", padding = 0.06 },
			nodes = {
				{ n = G.UIT.C, config = { align = "cl", minw = WIDTH - 3.6 }, nodes = { TUI.text("TOURNAMENTS YOU RUN", 0.36, G.C.PURPLE) } },
				{ n = G.UIT.C, config = { align = "cr", minw = 3.4 }, nodes = { TUI.button("NEW TOURNAMENT", "tom_section_new", nil, G.C.GREEN, 3.2) } },
			},
		},
	}
	local mine = run_by_me()
	if #mine == 0 then
		rows[#rows + 1] = TUI.message(PVP.Tournaments.state.mine and "You don't run any tournaments yet." or "Loading...")
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
	if #mine > SHOWN then
		rows[#rows + 1] = TUI.message("+" .. (#mine - SHOWN) .. " older")
	end
	return { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = { { n = G.UIT.C, config = { align = "tm" }, nodes = rows } } }
end

MPAPI.on_loaded(function()
	if not PVP or not PVP.register_tournament_section then
		sendWarnMessage("This PvP has no tournament sections; the Organiser mod needs a newer PvP.", "TournamentOrganiser")
		return
	end
	PVP.register_tournament_section({ key = "organiser", build = build })
end)

G.FUNCS.tom_section_new = function()
	TOM.open_create(false)
end

G.FUNCS.tom_section_manage = function(e)
	local id = e.config.ref_table and e.config.ref_table.id
	if id then
		TOM.open_manage(id)
	end
end
