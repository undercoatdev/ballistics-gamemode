-- Injury panel closes when buy starts. Run: luajit tests/test_inspect_close.lua
dofile("tests/support/gmod_stub.lua")
CLIENT = true

local failed = false
local function check(name, ok)
	print((ok and "ok " or "FAIL ") .. name)
	if not ok then failed = true end
end

local phase = ""
local ply = {
	GetNW2String = function(_, key, fallback)
		if key == "bal_phase" then return phase end
		return fallback
	end,
}
function LocalPlayer() return ply end
function IsValid(ent) return type(ent) == "table" and ent.valid == true end

dofile("gamemodes/ballistics/gamemode/modules/buy/cl_inspect_close.lua")
check("close inspect is installed", type(BALLISTICS.CloseInspect) == "function")

local closes = 0
BODY_DAMAGE = {
	ClosePanel = function()
		closes = closes + 1
		BODY_DAMAGE.Panel = nil
	end,
	Panel = { valid = true },
}
hook.Run("Ballistics_PhaseChanged", "live", "post")
check("leaving live does not close the panel", closes == 0 and BODY_DAMAGE.Panel ~= nil)
hook.Run("Ballistics_PhaseChanged", "post", "buy")
check("buy closes through ClosePanel", closes == 1 and BODY_DAMAGE.Panel == nil)
hook.Run("Ballistics_PhaseChanged", "buy", "live")
check("live does not close again", closes == 1)

phase = "live"
hook.Run("Think")
check("a live phase does not close", closes == 1)
phase = "buy"
hook.Run("Think")
check("the networked buy phase closes", closes == 2)
hook.Run("Think")
check("staying in buy does not close again", closes == 2)
phase = "post"
hook.Run("Think")
phase = "buy"
hook.Run("Think")
check("the next buy closes again", closes == 3)

BODY_DAMAGE.ClosePanel = nil
local panel = { valid = true, closed = false, removed = false }
function panel:Close() self.closed = true end
function panel:Remove() self.removed = true self.valid = false end
BODY_DAMAGE.Panel = panel
BALLISTICS.CloseInspect()
check("a panel without ClosePanel is closed and removed", panel.closed == true and panel.removed == true and BODY_DAMAGE.Panel == nil)

BODY_DAMAGE = nil
local ok = pcall(BALLISTICS.CloseInspect)
check("a missing body damage table is ignored", ok == true)

if failed then os.exit(1) end
