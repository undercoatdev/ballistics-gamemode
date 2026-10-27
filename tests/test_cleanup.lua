-- Round cleanup spares flags and living records, and deletes ragdolls.
-- Run: luajit tests/test_cleanup.lua
local failed = false
local function check(name, ok)
	if ok then
		print("ok " .. name)
	else
		failed = true
		print("FAIL " .. name)
	end
end

dofile("tests/support/gmod_stub.lua")
dofile("gamemodes/ballistics/gamemode/modules/cleanup/sh_cleanup.lua")

local C = BALLISTICS.Cleanup
check("prop_ragdoll is removed", C.ShouldRemove({ class = "prop_ragdoll" }) == true)
check("client ragdoll is removed", C.ShouldRemove({ class = "class C_ClientRagdoll" }) == true)
check("prop_dynamic is kept", C.ShouldRemove({ class = "prop_dynamic" }) == false)
check("a player is kept", C.ShouldRemove({ class = "prop_ragdoll", isPlayer = true }) == false)
check("BallisticsKeep is kept", C.ShouldRemove({ class = "prop_ragdoll", keep = true }) == false)
check("a flag team is kept", C.ShouldRemove({ class = "prop_ragdoll", flagTeam = 1 }) == false)
check("flag team 0 does not spare a ragdoll", C.ShouldRemove({ class = "prop_ragdoll", flagTeam = 0 }) == true)
check("empty info removes nothing", C.ShouldRemove(nil) == false)
check("a loot drop on the floor is removed", C.ShouldRemove({ class = "tacrp_mp5", lootDrop = true }) == true)
check("a held loot drop stays", C.ShouldRemove({ class = "tacrp_mp5", lootDrop = true, held = true }) == false)
check("an unmarked weapon stays", C.ShouldRemove({ class = "tacrp_mp5" }) == false)
check("a player stays even if marked as a loot drop", C.ShouldRemove({ class = "tacrp_mp5", lootDrop = true, isPlayer = true }) == false)

local function readAll(path)
	local f = io.open(path, "r")
	if not f then return "" end
	local text = f:read("*a")
	f:close()
	return text
end

local roundSrc = readAll("gamemodes/ballistics/gamemode/core/sv_round.lua")
local cleanAt = roundSrc:find("Cleanup.Round", 1, true)
local spawnAt = cleanAt and roundSrc:find("spawnSlotted()", cleanAt, true)
check("cleanup runs before spawn", cleanAt ~= nil and spawnAt ~= nil)
check("cleanup does not use CleanUpMap", not roundSrc:find("CleanUpMap", 1, true))
local cleanSrc = readAll("gamemodes/ballistics/gamemode/modules/cleanup/sv_cleanup.lua")
	.. readAll("gamemodes/ballistics/gamemode/modules/cleanup/cl_cleanup.lua")
check("cleanup module does not use CleanUpMap", not cleanSrc:find("CleanUpMap", 1, true))
check("clients clear decals", cleanSrc:find("r_cleardecals", 1, true) ~= nil)

local removed = {}
local function ent(class, flag)
	local e = { class = class, flag = flag or 0 }
	function e:IsValid() return not removed[self] end
	function e:GetClass() return self.class end
	function e:GetNW2Int() return self.flag end
	function e:Remove() removed[self] = true end
	function e:RemoveAllDecals() self.decals = true end
	return e
end

local ragA = ent("prop_ragdoll")
local ragB = ent("prop_ragdoll")
local ragC = ent("prop_ragdoll")
local flag = ent("prop_dynamic", 1)
local alive = { bd_id = "live" }
function alive:IsValid() return true end
function alive:Alive() return true end
function alive:IsPlayer() return true end

local recA = { id = "live", corpse = ragA, puppet = ragA }
local recB = { id = "dead", corpse = ragB }
BODY_DAMAGE = { Records = { live = recA, dead = recB, other = { id = "other" } } }
PLAYER_BALLISTICS = {
	Bodies = {
		{ ent = ragA, id = "live", rec = recA, steam = "ALIVE" },
		{ ent = ragB, id = "dead", rec = recB, steam = "DEAD" },
	},
	ReleaseBodyHandle = function() end,
}
ents = {
	FindByClass = function(class)
		if class == "prop_ragdoll" then return { ragA, ragB, ragC } end
		return {}
	end,
	GetAll = function() return { ragA, ragB, ragC, flag, alive } end,
}
player.GetAll = function() return { alive } end
local worldDecals = false
game.GetWorld = function()
	return { RemoveAllDecals = function() worldDecals = true end, IsValid = function() return true end }
end
local broadcast = nil
BALLISTICS.Net = BALLISTICS.Net or {}
function BALLISTICS.Net.Broadcast(name) broadcast = name end

dofile("gamemodes/ballistics/gamemode/modules/cleanup/sv_cleanup.lua")
BALLISTICS.Cleanup.Round()

check("living owner's ragdoll is removed", removed[ragA] == true)
check("living owner's record is kept", BODY_DAMAGE.Records.live == recA)
check("living owner's corpse pointer is cleared", recA.corpse == nil and recA.puppet == nil)
check("dead body is removed", removed[ragB] == true)
check("dead record is dropped", BODY_DAMAGE.Records.dead == nil)
check("unrelated record stays", BODY_DAMAGE.Records.other ~= nil)
check("loose ragdoll is removed", removed[ragC] == true)
check("spawn flag stays", removed[flag] ~= true)
check("kept-body list is empty", #PLAYER_BALLISTICS.Bodies == 0)
check("decals cleared and clients told", worldDecals == true and flag.decals == true and broadcast == "bal_cleanup")

local gun = ent("tacrp_mp5")
gun.BallisticsLootDrop = true
local heldGun = ent("tacrp_ak47")
heldGun.BallisticsLootDrop = true
function heldGun:GetOwner() return alive end
local plain = ent("tacrp_mp5")
ents.GetAll = function() return { gun, heldGun, plain, alive } end
removed = {}
BALLISTICS.Cleanup.Round()
check("round cleanup removes a marked gun", removed[gun] == true)
check("round cleanup keeps a held marked gun", removed[heldGun] ~= true)
check("round cleanup keeps an unmarked gun", removed[plain] ~= true)

-- Client decal pass clears world and entity decals, and repeats later.
do
	local cmds, worldCleared, entCleared = {}, 0, 0
	RunConsoleCommand = function(c) cmds[#cmds + 1] = c end
	game = game or {}
	game.GetWorld = function() return { RemoveAllDecals = function() worldCleared = worldCleared + 1 end } end
	ents = ents or {}
	local oldAll = ents.GetAll
	ents.GetAll = function() return { { RemoveAllDecals = function() entCleared = entCleared + 1 end } } end
	local wasServer = SERVER
	CLIENT, SERVER = true, false
	dofile("gamemodes/ballistics/gamemode/modules/cleanup/cl_cleanup.lua")
	CLIENT, SERVER = nil, wasServer
	if BALLISTICS.Cleanup.ClientDecals then
		BALLISTICS.Cleanup.ClientDecals()
		check("client clears decals everywhere", cmds[1] == "r_cleardecals" and worldCleared == 1 and entCleared == 1)
		check("decal pass repeats after removals", #(BALLISTICS.Cleanup.DECAL_PASSES or {}) >= 2)
	else
		check("client decal pass exists", false)
	end
	-- Body Damage blood pools: its own PostCleanupMap clear runs each pass.
	local pools = 0
	local oldHook = hook
	hook = { GetTable = function() return { PostCleanupMap = { BodyDamage_Blood = function() pools = pools + 1 end } } end, Add = function() end }
	BALLISTICS.Cleanup.ClientDecals()
	check("Body Damage blood pools cleared", pools == 1)
	hook = { GetTable = function() return {} end, Add = function() end }
	check("no Body Damage is harmless", BALLISTICS.Cleanup.BodyDamagePuddles() == false)
	hook = oldHook
	ents.GetAll = oldAll
end

if failed then os.exit(1) end
