-- Run from the repo root: lua5.4 tests/text_test.lua
-- Every text key the mod names (k_tom_...) is in the English file, and
-- TOM.T fills in its #n# arguments.
dofile("lib/text.lua")

local failures = 0
local function check(name, ok, detail)
	if not ok then
		failures = failures + 1
		print("FAIL " .. name .. (detail and (": " .. detail) or ""))
	end
end

local english = dofile("localization/en-us.lua").misc.dictionary

local FILES = {
	"lib/form.lua",
	"lib/template.lua",
	"ui/cocktail.lua",
	"ui/create.lua",
	"ui/manage.lua",
	"ui/pools.lua",
	"ui/rounds.lua",
	"ui/section.lua",
	"ui/templates.lua",
	"ui/timing.lua",
	"ui/widgets.lua",
}

local used = 0
for _, path in ipairs(FILES) do
	local f = assert(io.open(path, "r"))
	local src = f:read("a")
	f:close()
	for key in src:gmatch('"(k_tom_[%w_]+)"') do
		-- "k_tom_day_" .. x builds the key: those prefixes end in "_".
		if not key:match("_$") then
			used = used + 1
			-- F.count(n, key) uses key .. "_1" and key .. "_n".
			local ok = english[key] ~= nil or (english[key .. "_1"] ~= nil and english[key .. "_n"] ~= nil)
			check("key " .. key .. " (" .. path .. ")", ok)
		end
	end
end
check("keys found", used > 300, tostring(used))

check("plain", TOM.T("k_tom_saved") == "Saved.")
check("arguments", TOM.T("k_tom_done_wins", "Ana", "W2-1") == "Ana wins W2-1.")
check("unknown key shows itself", TOM.T("k_tom_no_such_key") == "k_tom_no_such_key")

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("text_test: all passed")
