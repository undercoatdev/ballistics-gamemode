-- Money and round HUD models. The phase line must miss the capture bars.
-- Run: luajit tests/test_hud.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/modules/objective/sh_capture.lua")
dofile("gamemodes/ballistics/gamemode/modules/hud/sh_money.lua")
dofile("gamemodes/ballistics/gamemode/modules/hud/sh_round.lua")

local M = BALLISTICS.MoneyHud
local R = BALLISTICS.RoundHud

local balance, pending = M.Parts(1000, 500)
check("balance and pending text", balance == "$1000" and pending == "+500")
balance, pending = M.Parts(nil, nil)
check("missing money is zero", balance == "$0" and pending == "+0")
balance, pending = M.Parts(-4, 3.9)
check("money text floors and clamps", balance == "$0" and pending == "+3")

local colors = M.Colors()
check("pending is green", colors.pending.g > colors.pending.r and colors.pending.g > colors.pending.b and colors.pending.g > 180)

local place = M.Place(1920, 1080, 80, 40, 12)
local mid = (place.balance.x + place.pending.x + place.pending.w) / 2
check("pending sits to the right of the balance", place.pending.x >= place.balance.x + place.balance.w and place.pending.y == place.balance.y)
check("the pair is bottom-middle", math.abs(mid - 960) < 2 and place.y > 1080 * 0.75 and place.y + place.h <= 1080)

check("the clock formats", R.Clock(600) == "10:00" and R.Clock(90) == "1:30" and R.Clock(0) == "0:00" and R.Clock(9) == "0:09" and R.Clock(9.2) == "0:10" and R.Clock(-5) == "0:00")
check("live shows phase and clock", R.Label("live", 600) == "LIVE  10:00")
check("lobby has no countdown", R.Label("lobby", 10) == "LOBBY" and R.Label("lobby", nil) == "LOBBY")
check("post and buy show a clock", R.Label("post", 5) == "POST  0:05" and R.Label("buy", 10) == "BUY  0:10")
check("squad shows a clock", R.Label("squad", 30) == "SQUAD  0:30")
check("an unknown phase is hidden", R.Label("LIVE", 10) == nil and R.Label(nil, 10) == nil)

check("nothing is drawn before a sync", R.Line(0) == nil and R.Seen() == false)
R.Apply({ phase = "live", endsAt = 1000, round = 3, winner = "" })
check("a synced live round counts down", R.Line(400) == "LIVE  10:00" and R.TimeLeft(400) == 600 and R.Snapshot().round == 3)
R.Apply({ phase = "live", endsAt = 1000 })
check("a partial update keeps the round number", R.Snapshot().round == 3)
R.Apply({ phase = "lobby", endsAt = 0 })
check("lobby drops the clock", R.Line(50) == "LOBBY" and R.TimeLeft(50) == nil)
R.Apply({ phase = "post", endsAt = 50 })
check("post counts the remaining seconds", R.Line(45) == "POST  0:05")
R.Apply({ phase = "nope", endsAt = 10 })
check("a bad phase does not replace the current one", R.Snapshot().phase == "post")

local function hit(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local widths = { 1920, 1280, 800 }
local counts = { 0, 1, 2 }
local clear = true
local topped = true
local below = true
for w = 1, #widths do
	for c = 1, #counts do
		local sw = widths[w]
		local n = counts[c]
		local chip = R.Place(sw, n)
		local bars = BALLISTICS.Capture.BarRects(sw, n)
		for i = 1, #bars do
			if hit(chip, bars[i]) then clear = false end
		end
		local centre = chip.x + chip.w / 2
		if math.abs(centre - sw / 2) > 1 then clear = false end
		if n == 0 and chip.y > 20 then topped = false end
		if n > 0 and chip.y < bars[#bars].y + bars[#bars].h then below = false end
		if chip.y < 0 or chip.x < 0 then clear = false end
	end
end
check("the phase line does not overlap a capture bar", clear)
check("with no bar the phase line stays at the top", topped)
check("with bars the phase line sits below them", below)

-- Client files must load. Paint runs with no LocalPlayer and no draw state.
CLIENT = true
SERVER = false
dofile("gamemodes/ballistics/gamemode/modules/hud/cl_money.lua")
dofile("gamemodes/ballistics/gamemode/modules/hud/cl_round.lua")
dofile("gamemodes/ballistics/gamemode/modules/admin/cl_tab_rules.lua")
local painted = pcall(function()
	hook.Run("HUDPaint")
	if BALLISTICS.Admin and BALLISTICS.Admin.BuildRules then
		BALLISTICS.Admin.BuildRules(nil, "general")
	end
end)
check("client hud files paint without a player", painted == true)

if failed then os.exit(1) end
