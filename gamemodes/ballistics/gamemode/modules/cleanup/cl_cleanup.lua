-- Server round cleanup asks every client to drop local decals and ragdolls.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Cleanup = BALLISTICS.Cleanup or {}

local function localRagdolls()
	if game and game.RemoveRagdolls then game.RemoveRagdolls() end
	if not (ents and ents.GetAll) then return end
	local all = ents.GetAll()
	if type(all) ~= "table" then return end
	for i = 1, #all do
		local ent = all[i]
		if ent ~= nil then
			local class = ""
			if type(ent.GetClass) == "function" then
				local ok, got = pcall(ent.GetClass, ent)
				if ok and type(got) == "string" then class = got end
			end
			local flag = 0
			if type(ent.GetNW2Int) == "function" then
				local ok, got = pcall(ent.GetNW2Int, ent, "bal_flag_team", 0)
				if ok and got ~= nil then flag = got end
			end
			local info = {
				class = class,
				isPlayer = type(ent.IsPlayer) == "function" and ent:IsPlayer() == true or false,
				keep = ent.BallisticsKeep == true,
				flagTeam = flag,
			}
			if BALLISTICS.Cleanup.ShouldRemove(info) and type(ent.Remove) == "function" then
				pcall(ent.Remove, ent)
			end
		end
	end
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_cleanup", function()
		if RunConsoleCommand then RunConsoleCommand("r_cleardecals") end
		localRagdolls()
	end)
end
