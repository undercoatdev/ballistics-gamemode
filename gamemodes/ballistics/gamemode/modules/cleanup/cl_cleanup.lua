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
			-- Only client-side entities (EntIndex -1) may be removed here; the server removes its own.
			local clientside = type(ent.EntIndex) == "function" and ent:EntIndex() == -1
			if clientside and BALLISTICS.Cleanup.ShouldRemove(info) and type(ent.Remove) == "function" then
				pcall(ent.Remove, ent)
			end
		end
	end
end

BALLISTICS.Cleanup.DECAL_PASSES = { 0.3, 1, 2 }

-- r_cleardecals alone is not enough: also strip decals from the world and
-- every entity on this client (Body Damage / Sticky Blood paint on both).
function BALLISTICS.Cleanup.ClientDecals()
	if RunConsoleCommand then pcall(RunConsoleCommand, "r_cleardecals") end
	if game and game.GetWorld then
		local ok, world = pcall(game.GetWorld)
		if ok and world and world.RemoveAllDecals then pcall(world.RemoveAllDecals, world) end
	end
	if ents and ents.GetAll then
		for _, ent in ipairs(ents.GetAll()) do
			if ent and ent.RemoveAllDecals then pcall(ent.RemoveAllDecals, ent) end
		end
	end
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_cleanup", function()
		localRagdolls()
		BALLISTICS.Cleanup.ClientDecals()
		-- Again after the server ragdoll removals arrive: Sticky Blood stamps
		-- a fresh decal when a blood plate entity is removed (EntityRemoved).
		if timer and timer.Simple then
			for _, t in ipairs(BALLISTICS.Cleanup.DECAL_PASSES or {}) do
				timer.Simple(t, BALLISTICS.Cleanup.ClientDecals)
			end
		end
	end)
end
