-- Buy phase god mode. Run: luajit tests/test_godmode.lua
local failed = false
local function check(name, ok)
	if ok then print("ok " .. name) else failed = true print("FAIL " .. name) end
end

dofile("tests/support/gmod_stub.lua")
local events = {}
local realAdd = hook.Add
hook.Add = function(e, n, f) events[e] = events[e] or {}; events[e][n] = f; realAdd(e, n, f) end
hook.GetTable = function() return events end

BALLISTICS = BALLISTICS or {}
local phase = "buy"
BALLISTICS.Round = { Phase = function() return phase end }
local organHits = 0
hook.Add("EntityTakeDamage", "BodyDamage_Track", function() organHits = organHits + 1 end)

dofile("gamemodes/ballistics/gamemode/modules/godmode/sh_godmode.lua")
dofile("gamemodes/ballistics/gamemode/modules/godmode/sv_godmode.lua")
BALLISTICS.GodMode.WrapHooks()

local ply = {}
function ply:IsPlayer() return true end
function ply:IsValid() return true end
local prop = {}
function prop:IsPlayer() return false end
local dmg = { d = 50 }
function dmg:SetDamage(n) self.d = n end
function dmg:ScaleDamage(n) self.d = self.d * n end

local E = events.EntityTakeDamage
check("only buy is protected", BALLISTICS.GodMode.Active("buy") and not BALLISTICS.GodMode.Active("live") and not BALLISTICS.GodMode.Active("lobby"))
check("buy: our hook blocks damage", E.Ballistics_BuyGod(ply, dmg) == true and dmg.d == 0)
E.BodyDamage_Track(ply, dmg)
check("buy: Body Damage hook skipped for players", organHits == 0)
check("buy: bleed start cancelled", events.BodyDamage_OrganBleed.Ballistics_BuyGod(ply) == true)
check("buy: fall damage zero", events.GetFallDamage.Ballistics_BuyGod(ply) == 0)
check("buy: PlayerShouldTakeDamage false", events.PlayerShouldTakeDamage.Ballistics_BuyGod(ply) == false)
E.BodyDamage_Track(prop, dmg)
check("buy: props still take damage", organHits == 1)
phase = "live"
dmg.d = 50
check("live: damage goes through", E.Ballistics_BuyGod(ply, dmg) == nil and dmg.d == 50)
E.BodyDamage_Track(ply, dmg)
check("live: Body Damage hook runs again", organHits == 2)
BALLISTICS.GodMode.WrapHooks()
E.BodyDamage_Track(ply, dmg)
check("rewrap does not double wrap", organHits == 3)

-- Passive drain is frozen in buy.
local rec = { blood = 80, bleedPerSecond = 3, oxygenDebt = 20, waterDebt = 5, stress = 40 }
local kills = 0
BODY_DAMAGE = {
	FindRecord = function() return rec end,
	OxygenOutput = function() return 10 end,
	KillBledOut = function() kills = kills + 1 end,
}
BALLISTICS.GodMode.WrapBodyDamage()
phase = "buy"
BALLISTICS.GodMode.Pin(ply)
rec.blood = 60
BALLISTICS.GodMode.Pin(ply)
check("buy: bleed, debt and stress pinned", rec.bleedPerSecond == 0 and rec.oxygenDebt == 0 and rec.waterDebt == 0 and rec.stress == 0)
check("buy: lost blood put back", rec.blood == 80)
check("buy: weak organs still give full oxygen", BODY_DAMAGE.OxygenOutput({}, nil, ply) == 100)
BODY_DAMAGE.KillBledOut(ply)
check("buy: bled-out kill refused", kills == 0)
phase = "live"
check("live: oxygen output normal again", BODY_DAMAGE.OxygenOutput({}, nil, ply) == 10)
BODY_DAMAGE.KillBledOut(ply)
check("live: bled-out kill works", kills == 1)
rec.bleedPerSecond = 2
BALLISTICS.GodMode.Pin(ply)
check("live: bleeding not touched", rec.bleedPerSecond == 2)
BALLISTICS.GodMode.WrapBodyDamage()
BODY_DAMAGE.KillBledOut(ply)
check("no double wrap", kills == 2)

if failed then os.exit(1) end
