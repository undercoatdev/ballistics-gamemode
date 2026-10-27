-- While TacRP's customize menu is open, skip Player Ballistics / Body Damage
-- HUD (medical row, vitals, body figure) and our own HUD (keybinds, money,
-- capture, round). Their HUDPaint hooks are wrapped at runtime; no files edited.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.HudHide = BALLISTICS.HudHide or {}
local H = BALLISTICS.HudHide
local wrapped = setmetatable({}, { __mode = "k" })

function H.Active()
	if not LocalPlayer then return false end
	local ply = LocalPlayer()
	if not IsValid(ply) or not ply.GetActiveWeapon then return false end
	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) then return false end
	return H.Customizing(wep)
end

function H.Wrap()
	if not (hook and hook.GetTable) then return end
	local list = hook.GetTable().HUDPaint
	if type(list) ~= "table" then return end
	for name, fn in pairs(list) do
		if type(fn) == "function" and not wrapped[fn] and H.ShouldHide(name) then
			local orig = fn
			local guard = function(...)
				if H.Active() then return end
				return orig(...)
			end
			wrapped[guard] = true
			hook.Add("HUDPaint", name, guard)
		end
	end
end

if hook and hook.Add then
	hook.Add("InitPostEntity", "Ballistics_HudHideWrap", function() H.Wrap() end) -- never return a value: it would stop later hooks (TacRP indexes quick nades here)
end
-- Mods add HUDPaint hooks late or re-add them; rewrap every second.
if timer and timer.Create then
	timer.Create("Ballistics_HudHideWrap", 1, 0, H.Wrap)
end
