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
	hook.Add("InitPostEntity", OWN, G.WrapHooks)
	hook.Add("Ballistics_PhaseChanged", OWN, function(_, new)
		if new == "buy" then G.WrapHooks() end
	end)
end
