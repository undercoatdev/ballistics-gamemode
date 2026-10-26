-- What a round cleanup may delete. Ragdolls only. Flags, players, and anything
-- marked BallisticsKeep stay. No GMod calls.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Cleanup = BALLISTICS.Cleanup or {}

local RAGDOLL = {
	["prop_ragdoll"] = true,
	["class C_ClientRagdoll"] = true,
}

function BALLISTICS.Cleanup.IsRagdollClass(class)
	return type(class) == "string" and RAGDOLL[class] == true
end

-- info: class, isPlayer, keep, flagTeam (NW2 bal_flag_team).
function BALLISTICS.Cleanup.ShouldRemove(info)
	info = info or {}
	if info.isPlayer == true then return false end
	if info.keep == true then return false end
	local flag = info.flagTeam
	if flag ~= nil and flag ~= 0 and flag ~= "" and flag ~= false then return false end
	return BALLISTICS.Cleanup.IsRagdollClass(info.class) == true
end
