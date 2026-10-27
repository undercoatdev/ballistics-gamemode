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
if failed then os.exit(1) end
