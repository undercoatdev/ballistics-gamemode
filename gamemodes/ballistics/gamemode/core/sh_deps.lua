-- TacRP / Player Ballistics / Body Damage adapters. Every foreign global is
-- guarded; missing TacRP prints one warning and disables the buy menu.

BALLISTICS = BALLISTICS or {}

BALLISTICS.WorkshopIDs = {
	tacrp = "3734712166",
	-- player_ballistics TBD
	-- body_damage TBD
}

function BALLISTICS.HasTacRP()
	return TacRP ~= nil
end

function BALLISTICS.HasPlayerBallistics()
	return PLAYER_BALLISTICS ~= nil
end

function BALLISTICS.HasBodyDamage()
	return BODY_DAMAGE ~= nil
end

function BALLISTICS.IsConscious(ply)
	if ply == nil then return false end
	if type(ply.Alive) == "function" and not ply:Alive() then return false end
	if ply.pbDown then return false end
	local pb = PLAYER_BALLISTICS
	if pb and pb.DownOf and pb.DownOf[ply] then return false end
	local bd = BODY_DAMAGE
	if bd and type(bd.FindRecord) == "function" then
		local rec = bd.FindRecord(ply)
		if rec and rec.unconscious then return false end
	end
	return true
end

function BALLISTICS.GiveMed(ply, id, n)
	local pb = PLAYER_BALLISTICS
	if not pb or type(pb.GiveMed) ~= "function" then return false end
	return pb.GiveMed(ply, id, n)
end

function BALLISTICS.MedMax()
	local pb = PLAYER_BALLISTICS
	if not pb or type(pb.MedMax) ~= "function" then return 0 end
	return pb.MedMax()
end

function BALLISTICS.BuyMenuEnabled()
	return BALLISTICS.BuyDisabled ~= true and BALLISTICS.HasTacRP()
end

local function checkTacRP()
	if TacRP ~= nil then
		BALLISTICS.BuyDisabled = false
		return
	end
	BALLISTICS.BuyDisabled = true
	if BALLISTICS._warnedTacRP then return end
	BALLISTICS._warnedTacRP = true
	print("[Ballistics] TacRP is not loaded (Workshop 3734712166). The buy menu is disabled.")
end

-- Addons (TacRP) autorun after the gamemode loads, so only judge (and warn)
-- once Initialize has run; at file load just record the current state.
BALLISTICS.BuyDisabled = (TacRP == nil)
if hook and hook.Add then
	hook.Add("Initialize", "Ballistics_Deps", checkTacRP)
end
