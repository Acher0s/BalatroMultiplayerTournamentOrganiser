-- Multiplayer Tournament Organiser: hosting tournaments for Multiplayer PvP.
-- PvP has the TOURNAMENTS tab (joining, playing, the bracket); this mod adds
-- its ORGANISE page sections: creating a tournament (ui/create.lua) and
-- running one (ui/manage.lua). Everything goes through PvP's
-- PVP.Tournaments.call and the server's tournament_* RPCs.

TOM = TOM or {}
TOM.id = SMODS.current_mod.id

local function load(path)
	local chunk, err = SMODS.load_file(path, TOM.id)
	if not chunk then
		sendWarnMessage("Failed to load " .. path .. ": " .. tostring(err), "TournamentOrganiser")
		return
	end
	local ok, run_err = pcall(chunk)
	if not ok then
		sendWarnMessage("Failed to run " .. path .. ": " .. tostring(run_err), "TournamentOrganiser")
	end
end

load("lib/form.lua")
load("lib/template.lua")
load("ui/widgets.lua")
load("ui/cocktail.lua")
load("ui/pools.lua")
load("ui/rounds.lua")
load("ui/templates.lua")
load("ui/create.lua")
load("ui/manage.lua")
load("ui/section.lua")
