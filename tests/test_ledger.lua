-- Money ledger: spend, insufficient, pending, commit, reset, cap, refund.
-- Run: luajit tests/test_ledger.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_ledger.lua")

local function fresh(over)
	local cfg = {
		StartMoney = 800,
		MaxMoney = 0,
		Gains = { kill = 500, round_win = 1000, round_loss = 500 },
	}
	if over then
		for k, v in pairs(over) do cfg[k] = v end
	end
	return BALLISTICS.Ledger.new(cfg), cfg
end

local L, cfg = fresh()

local balance, pending = L:Get("p")
check("new account starts at StartMoney", balance == 800 and pending == 0)

local ok, err = L:Spend("p", 100)
balance, pending = L:Get("p")
check("spend draws balance", ok == true and err == 700 and balance == 700 and pending == 0)

ok, err = L:Spend("p", 701)
balance, pending = L:Get("p")
check("insufficient leaves balance", ok == false and err == "insufficient" and balance == 700 and pending == 0)

ok, err = L:Spend("p", 700)
balance = L:Get("p")
check("spend exact balance", ok == true and balance == 0)

ok, err = L:Spend("p", 1)
check("zero balance cannot spend", ok == false and err == "insufficient" and L:Get("p") == 0)

L:Reset("p")
ok, err = L:Spend("p", -5)
balance, pending = L:Get("p")
check("negative spend is invalid", ok == false and err == "invalid" and balance == 800)

ok, err = L:Spend("p", 0 / 0)
check("nan spend is invalid", ok == false and err == "invalid" and L:Get("p") == 800)

ok, err = L:Spend("p", 10.9)
check("spend floors to integer", ok == true and err == 790 and L:Get("p") == 790)

ok, err = L:Spend(nil, 1)
check("spend without player", ok == false and err == "player")

L:Reset("p")
ok, err = L:Earn("p", "kill")
balance, pending = L:Get("p")
check("earn kill looks up Gains into pending", ok == true and err == 500 and balance == 800 and pending == 500)

ok, err = L:Spend("p", 900)
balance, pending = L:Get("p")
check("pending is not spendable", ok == false and err == "insufficient" and balance == 800 and pending == 500)

ok, err = L:Earn("p", "round_win")
_, pending = L:Get("p")
check("earn stacks pending", ok == true and pending == 1500)

ok, err = L:Earn("p", "nope")
_, pending = L:Get("p")
check("unknown gain key", ok == false and err == "unknown" and pending == 1500)

ok, err = L:Earn("ghost", "nope")
local ids = L:Ids()
local ghost = false
for i = 1, #ids do
	if ids[i] == "ghost" then ghost = true end
end
check("unknown key does not open an account", ok == false and ghost == false)

ok, err = L:Earn("p", "kill", -1)
check("negative earn is invalid", ok == false and err == "invalid" and select(2, L:Get("p")) == 1500)

ok, err = L:Earn("p", "kill", 3)
_, pending = L:Get("p")
check("explicit amount skips the lookup", ok == true and pending == 1503)

ok, err = L:Commit("p")
balance, pending = L:Get("p")
check("commit folds pending into balance", ok == true and balance == 800 + 1503 and pending == 0)

ok = L:Commit("p")
balance, pending = L:Get("p")
check("commit with empty pending is stable", ok == true and balance == 2303 and pending == 0)

L:Earn("q", "round_loss")
L:Commit()
check("commit all", select(2, L:Get("p")) == 0 and L:Get("q") == 800 + 500)

cfg.StartMoney = 100
ok, err = L:Reset("p")
balance, pending = L:Get("p")
check("reset uses current StartMoney and clears pending", ok == true and balance == 100 and pending == 0)
check("reset one account leaves the other", L:Get("q") == 1300)

cfg.StartMoney = 800
L:Earn("q", "x", 20)
L:Reset()
check("reset all", L:Get("p") == 800 and select(2, L:Get("p")) == 0 and L:Get("q") == 800 and select(2, L:Get("q")) == 0)

local capped, capCfg = fresh({ MaxMoney = 1000 })
capped:Earn("p", "bonus", 500)
ok, err = capped:Commit("p")
balance, pending = capped:Get("p")
check("cap clamps commit", ok == true and balance == 1000 and pending == 0 and err == 1000)

ok, err = capped:Refund("p", 50)
check("refund respects cap", ok == true and err == 1000 and capped:Get("p") == 1000)

capCfg.MaxMoney = 0
capped:Earn("p", "bonus", 5000)
capped:Commit("p")
check("MaxMoney 0 does not cap", capped:Get("p") == 6000)

local refunded = fresh()
refunded:Spend("p", 800)
ok, err = refunded:Refund("p", 100)
check("refund adds to balance", ok == true and err == 100 and refunded:Get("p") == 100)

ok = refunded:Refund("p", -10)
check("negative refund is invalid", ok == false and refunded:Get("p") == 100)

local cappedStart = fresh({ StartMoney = 800, MaxMoney = 500 })
check("new account clamps to MaxMoney", cappedStart:Get("p") == 500)
cappedStart:Reset("p")
check("reset clamps to MaxMoney", cappedStart:Get("p") == 500)

local zero = fresh()
ok = zero:Spend("p", 0)
check("zero spend succeeds", ok == true and zero:Get("p") == 800)

ok = zero:Earn("p", "kill", 0)
check("zero earn succeeds", ok == true and select(2, zero:Get("p")) == 0)

dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_slots.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_money.lua")

local ply = {
	nw = {},
	admin = true,
}
function ply:SteamID64() return "765" end
function ply:SetNW2Int(key, value) self.nw[key] = value end
function ply:IsAdmin() return true end

local spendOk = BALLISTICS.Money.Spend(ply, 50)
local bal, pend = BALLISTICS.Money.Get(ply)
check("facade spend syncs NW2", spendOk == true and bal == 950 and pend == 0 and ply.nw.bal_money == 950 and ply.nw.bal_pending == 0)

local changed = 0
hook.Add("Ballistics_MoneyChanged", "ledger", function() changed = changed + 1 end)
BALLISTICS.Money.Earn(ply, "round_win")
bal, pend = BALLISTICS.Money.Get(ply)
check("facade earn uses Gains", bal == 950 and pend == 1000 and ply.nw.bal_pending == 1000 and changed == 1)

local broke = BALLISTICS.Money.Spend(ply, 951)
bal = BALLISTICS.Money.Get(ply)
check("facade insufficient", broke == false and bal == 950)

BALLISTICS.Money.Commit(ply)
bal, pend = BALLISTICS.Money.Get(ply)
check("facade commit", bal == 1950 and pend == 0 and ply.nw.bal_money == 1950)

BALLISTICS.Money.Refund(ply, 25)
check("facade refund", BALLISTICS.Money.Get(ply) == 1975 and ply.nw.bal_money == 1975)

BALLISTICS.Slots.Take(ply, TEAM_GOOD, 1)
BALLISTICS.Money.Reset()
bal, pend = BALLISTICS.Money.Get(ply)
check("facade reset to StartMoney", bal == 1000 and pend == 0 and ply.nw.bal_money == 1000)

-- Real GMod players are userdata, not tables: NW2 sync must still happen.
local ud = newproxy(true)
local udnw = {}
getmetatable(ud).__index = {
	SteamID64 = function() return "766" end,
	SetNW2Int = function(_, k, v) udnw[k] = v end,
	IsAdmin = function() return false end,
}
BALLISTICS.Money.Earn(ud, "kill")
check("userdata player gets NW2 money synced", udnw.bal_pending == 500)

if failed then os.exit(1) end
