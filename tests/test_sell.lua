-- Run: luajit tests/test_sell.lua
BALLISTICS = {}
dofile("gamemodes/ballistics/gamemode/modules/sell/sh_sell.lua")
local S, failed = BALLISTICS.Sell, false
local function check(n, ok) print((ok and "ok   " or "FAIL ") .. n); if not ok then failed = true end end
local gun = { kind = "weapon", key = "ak", class = "tacrp_ak" }
local base = { phase = "buy", alive = true, slotted = true, item = gun, have = 1, price = 2700, attRefund = 800 }
local r = S.Plan(base)
check("gun sells for price plus attachments", r.ok and r.refund == 3500)
local c = {} for k, v in pairs(base) do c[k] = v end
c.phase = "live"; check("only in buy phase", S.Plan(c).err == "phase")
c.phase = "buy"; c.item = { kind = "weapon", key = "tacrp_knife", class = "tacrp_knife" }; check("knife never sells", S.Plan(c).err == "knife")
c.item = gun; c.have = 0; check("must own it", S.Plan(c).err == "none")
c.have = 2; c.item = { kind = "med", key = "bandage" }; c.price = 300
check("meds ignore attachment refund", S.Plan(c).refund == 300)
c.alive = false; check("dead cannot sell", S.Plan(c).err == "player")
check("label", S.Label(500) == "+$500")
local used = { phase = "buy", alive = true, slotted = true, item = gun, have = 1, price = 2700, attRefund = 0, fresh = 0 }
check("carried-over gear is used", S.Plan(used).ok == false and S.Plan(used).err == "used")
used.fresh = 1
check("fresh gear can sell", S.Plan(used).ok == true and S.Plan(used).refund == 2700)
used.fresh = nil
check("a plan without fresh still sells", S.Plan(used).ok == true)
local enc = S.Encode({ b = 2, a = 1, c = 0 })
check("encode keeps positive counts in key order", enc == "a:1,b:2")
local dec = S.Decode(enc)
check("decode roundtrip", dec.a == 1 and dec.b == 2 and S.Encode(dec) == enc and S.Encode(S.Decode("")) == "")
local fresh = { ak = 2 }
check("fresh take decrements", S.FreshTake(fresh, "ak") == true and fresh.ak == 1)
check("fresh take removes at zero", S.FreshTake(fresh, "ak") == true and fresh.ak == nil)
check("fresh take misses a missing key", S.FreshTake(fresh, "ak") == false)
S.FreshAdd(fresh, "ak", 1)
check("fresh add starts a count", fresh.ak == 1)
local row = { weapons = 1, nades = { frag = 2 } }
S.Unbuy(row, gun); S.Unbuy(row, gun)
check("weapon buys go down, never below 0", row.weapons == 0)
S.Unbuy(row, { kind = "nade", key = "frag" })
check("grenade count goes down by one", row.nades.frag == 1)
S.Unbuy(row, { kind = "nade", key = "frag" }); S.Unbuy(row, { kind = "nade", key = "frag" })
check("grenade count stops at 0", (row.nades.frag or 0) == 0)
local svSrc = io.open("gamemodes/ballistics/gamemode/modules/sell/sv_sell.lua"):read("*a")
check("sell server defines its own GOOD/BAD team ids", svSrc:find("local GOOD = TEAM_GOOD", 1, true) ~= nil and svSrc:find("local BAD = TEAM_BAD", 1, true) ~= nil)
check("sell prefers the stored twin", svSrc:find("ClearTwin", 1, true) ~= nil and svSrc:find("Load.Twin", 1, true) ~= nil)
if failed then os.exit(1) end
