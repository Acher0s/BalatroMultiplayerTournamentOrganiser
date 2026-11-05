-- Tournament templates (TOM.Template): a create wizard form saved without
-- its date, to start the next tournament from. Pure; the files are written by
-- ui/templates.lua. tests/template_test.lua.
--
-- A template is { kind = "mp_tournament_template", version = 1, name, form }.
-- Loading takes only the fields it knows, of the right type, onto a fresh
-- form, so an old or hand-edited file can't break the wizard.

TOM = TOM or {}
local T = {}
TOM.Template = T

T.KIND = "mp_tournament_template"
T.VERSION = 1

local F = function()
	return TOM.Form
end

local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end

-- What a template keeps, and the types each may have ("false" = off/auto).
local FIELDS = {
	name = { "string" },
	description = { "string" },
	visibility = { "string" },
	official = { "boolean" },
	requireRanked = { "boolean" },
	maxPlayers = { "number" },
	checkInMinutes = { "number", "false" },
	format = { "string" },
	grandFinalReset = { "boolean" },
	groupSize = { "number", "false" },
	swissRounds = { "number", "false" },
	seeding = { "string" },
	gameMode = { "string" },
	ruleset = { "string" },
	bestOf = { "number" },
	deckKind = { "string" },
	deck = { "string" },
	stake = { "number" },
	draftStakes = { "list" },
	banOrder = { "string" },
	cocktail = { "recipe" },
	poolDecks = { "list", "nil" },
	poolCocktails = { "recipes" },
	preset = { "string" },
	readyUpMinutes = { "number" },
	breakMinutes = { "number" },
	windowMinutes = { "number" },
	-- The time of day (the date isn't kept).
	hour = { "string" },
	minute = { "string" },
	pm = { "boolean" },
	rounds = { "rounds" },
	timing = { "rounds" },
}

local function is_list_of(v, kind)
	if type(v) ~= "table" then
		return false
	end
	for k, x in pairs(v) do
		if type(k) ~= "number" or type(x) ~= kind then
			return false
		end
	end
	return true
end

local function is_recipe(v)
	return type(v) == "table" and (v.name == nil or type(v.name) == "string") and is_list_of(v.decks or {}, "string")
end

local function fits(v, kinds)
	for _, kind in ipairs(kinds) do
		if kind == "nil" and v == nil then
			return true
		elseif kind == "false" and v == false then
			return true
		elseif kind == "list" and (is_list_of(v, "string") or is_list_of(v, "number")) then
			return true
		elseif kind == "recipe" and is_recipe(v) then
			return true
		elseif kind == "recipes" and type(v) == "table" then
			for _, r in pairs(v) do
				if not is_recipe(r) then
					return false
				end
			end
			return true
		elseif kind == "rounds" and type(v) == "table" then
			return true
		elseif type(v) == kind then
			return true
		end
	end
	return false
end

-- The template for a form.
function T.from_form(form, name)
	local saved = {}
	for key in pairs(FIELDS) do
		if form[key] ~= nil then
			saved[key] = copy(form[key])
		end
	end
	return { kind = T.KIND, version = T.VERSION, name = name or form.name, form = saved }
end

-- A timetable change as saved.
local TIMING_FIELDS = { breakBefore = "number", start = "string", play = "string", readyUpMinutes = "number", windowMinutes = "number", onward = "boolean", atDay = "number", atHour = "string", atMinute = "string", atPm = "boolean" }

local function clean_timing(t)
	if type(t) ~= "table" then
		return nil
	end
	local out = {}
	for key, kind in pairs(TIMING_FIELDS) do
		local v = t[key]
		if v == false or type(v) == kind then
			out[key] = v
		end
	end
	return out
end

-- A round as saved: only the fields a round has.
local ROUND_FIELDS = { "gameMode", "ruleset", "bestOf", "deckKind", "deck", "stake", "draftStakes", "banOrder", "cocktail", "poolDecks", "poolCocktails" }

local function clean_round(r)
	if type(r) ~= "table" then
		return nil
	end
	local out = {}
	for _, key in ipairs(ROUND_FIELDS) do
		local kinds = FIELDS[key]
		local v = r[key]
		-- A round field may also be false ("same as the defaults").
		if v ~= nil and (v == false or fits(v, kinds)) then
			out[key] = copy(v)
		end
	end
	return out
end

-- A fresh form from a template (or nil and why not). now_ms: the server's
-- now. The start is the template's time of day on the first day it is still
-- at least 10 minutes away. Fields that don't fit are skipped.
function T.to_form(template, now_ms)
	if type(template) ~= "table" or template.kind ~= T.KIND or type(template.form) ~= "table" then
		return nil, "That isn't a tournament template."
	end
	if type(template.version) ~= "number" or template.version > T.VERSION then
		return nil, "That template is from a newer Tournament Organiser."
	end
	local form = F().new(now_ms)
	local skipped = 0
	for key, kinds in pairs(FIELDS) do
		local v = template.form[key]
		if key == "rounds" or key == "timing" then
			if type(v) == "table" then
				local clean = key == "rounds" and clean_round or clean_timing
				form[key] = {}
				for rk, r in pairs(v) do
					if type(rk) == "string" then
						form[key][rk] = clean(r)
					end
				end
			end
		elseif v ~= nil or key == "poolDecks" then
			if fits(v, kinds) then
				form[key] = copy(v)
			else
				skipped = skipped + 1
			end
		end
	end
	-- A deck rule this version doesn't have (the old "Unset"): ban and pick.
	if form.deckKind ~= "locked" and form.deckKind ~= "draft" then
		form.deckKind = "draft"
	end
	-- The time of day on the next day it still can be.
	local today = os.date("*t", math.floor(now_ms / 1000))
	for days = 0, 2 do
		form.date = os.date("*t", os.time({ year = today.year, month = today.month, day = today.day + days, hour = 12 }))
		form.date = { year = form.date.year, month = form.date.month, day = form.date.day }
		local at = F().start_from_fields(form)
		if not at then
			-- A broken time: keep the fresh form's.
			F().split_start(form)
			break
		end
		if at >= now_ms + 10 * 60 * 1000 then
			form.startsAt = at
			break
		end
	end
	return form, skipped
end

-- A file name for a template name: letters, digits, spaces, - and _.
function T.file_name(name)
	local base = tostring(name or ""):gsub("[^%w%s%-_]", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
	if base == "" then
		base = "template"
	end
	return base:sub(1, 40) .. ".json"
end

return T
