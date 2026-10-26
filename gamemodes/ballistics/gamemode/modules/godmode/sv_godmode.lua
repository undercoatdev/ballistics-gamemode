-- Buy phase god mode. Our EntityTakeDamage returns true, but hook order is not
-- fixed, so Body Damage / Player Ballistics damage hooks (organ hits, bleed,
-- knockouts) are also wrapped to skip protected players. Their files are not touched.

if not SERVER then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.GodMode = BALLISTICS.GodMode or {}

local G = BALLISTICS.GodMode
local wrapped = setmetatable({}, { __mode = "k" })

local function phase()
	return BALLISTICS.Round and BALLISTICS.Round.Phase and BALLISTICS.Round.Phase()
end

function G.Protected(ent)
	if ent == nil then return false end
	local isPly = type(ent.IsPlayer) == "function" and ent:IsPlayer() == true
	if not isPly then return false end
	if IsValid and not IsValid(ent) then return false end
	return G.Protects(phase(), true)
end

local WRAP = { EntityTakeDamage = true, ScalePlayerDamage = true, PostEntityTakeDamage = true }
local OWN = "Ballistics_BuyGod"

function G.WrapHooks()
	if not (hook and hook.GetTable) then return end
	local all = hook.GetTable()
	for event in pairs(WRAP) do
		local list = all[event]
		if type(list) == "table" then
			for name, fn in pairs(list) do
				if name ~= OWN and type(fn) == "function" and not wrapped[fn] then
					local orig = fn
					local guard = function(ent, ...)
						if G.Protected(ent) then
							if event == "EntityTakeDamage" then return true end
							return
						end
						return orig(ent, ...)
					end
					wrapped[guard] = true
					hook.Add(event, name, guard)
				end
			end
		end
	end
end

-- Passive drain: Body Damage's 1 s vitals tick turns weak organs into low
-- oxygen and then a knockout, and bleeding drains blood. During buy a
-- protected player reads full oxygen output, and bleed / debt / stress /
-- lost blood are pinned so nothing drains. A bled-out kill is refused.
local held = setmetatable({}, { __mode = "k" })

local function recOf(ply)
	local bd = BODY_DAMAGE
	if not (bd and type(bd.FindRecord) == "function") then return nil end
	local ok, rec = pcall(bd.FindRecord, ply)
	if ok and type(rec) == "table" then return rec end
	return nil
end

function G.Pin(ply)
	if not G.Protected(ply) then
		held[ply] = nil
		return
	end
	local rec = recOf(ply)
	if not rec then return end
	if held[ply] == nil or held[ply].rec ~= rec then
		held[ply] = { rec = rec, blood = rec.blood }
	end
	local keep = held[ply]
	rec.bleedPerSecond = 0
	rec.oxygenDebt = 0
	rec.waterDebt = 0
	rec.stress = 0
	if type(keep.blood) == "number" and (tonumber(rec.blood) or 0) < keep.blood then rec.blood = keep.blood end
end

function G.WrapBodyDamage()
	local bd = BODY_DAMAGE
	if type(bd) ~= "table" then return end
	local out = bd.OxygenOutput
	if type(out) == "function" and not wrapped[out] then
		local guard = function(organs, flag, ent, ...)
			if G.Protected(ent) then return 100 end
			return out(organs, flag, ent, ...)
		end
		wrapped[guard] = true
		bd.OxygenOutput = guard
	end
	local kill = bd.KillBledOut
	if type(kill) == "function" and not wrapped[kill] then
		local guard = function(ent, ...)
			if G.Protected(ent) then return end
			return kill(ent, ...)
		end
		wrapped[guard] = true
		bd.KillBledOut = guard
	end
end

function G.PinAll()
	if not (player and player.GetAll) then return end
	for _, ply in ipairs(player.GetAll()) do G.Pin(ply) end
end

if timer and timer.Create then
	timer.Create("Ballistics_BuyGodPin", 0.1, 0, function() G.PinAll() end)
end

if hook and hook.Add then
	hook.Add("EntityTakeDamage", OWN, function(ent, dmg)
		if G.Protected(ent) then
			if dmg and dmg.SetDamage then dmg:SetDamage(0) end
			return true
		end
	end)
	hook.Add("ScalePlayerDamage", OWN, function(ply, _, dmg)
		if G.Protected(ply) and dmg and dmg.ScaleDamage then dmg:ScaleDamage(0) end
	end)
	hook.Add("PlayerShouldTakeDamage", OWN, function(ply)
		if G.Protected(ply) then return false end
	end)
	hook.Add("GetFallDamage", OWN, function(ply)
		if G.Protected(ply) then return 0 end
	end)
	-- Body Damage asks before an organ bleed starts; true cancels it.
	hook.Add("BodyDamage_OrganBleed", OWN, function(ent)
		if G.Protected(ent) then return true end
	end)
	hook.Add("InitPostEntity", OWN, function()
		G.WrapHooks()
		G.WrapBodyDamage()
	end)
	hook.Add("Ballistics_PhaseChanged", OWN, function(_, new)
		if new == "buy" then
			G.WrapHooks()
			G.WrapBodyDamage()
		end
	end)
end
