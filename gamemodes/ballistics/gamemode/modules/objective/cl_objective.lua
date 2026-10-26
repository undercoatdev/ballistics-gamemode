-- Capture progress for the HUD. The 2 m circles are drawn with the flags
-- in the spawns module; this file only keeps the synced bar values.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Capture = BALLISTICS.Capture or {}

local view = { good = 0, bad = 0 }

local function clamp01(n)
	n = tonumber(n) or 0
	if n ~= n or n < 0 then return 0 end
	if n > 1 then return 1 end
	return n
end

function BALLISTICS.Capture.SetView(good, bad)
	view.good = clamp01(good)
	view.bad = clamp01(bad)
end

function BALLISTICS.Capture.View()
	return view.good, view.bad
end

if BALLISTICS.Net and BALLISTICS.Net.Register then
	BALLISTICS.Net.Register("bal_capture_sync", function(payload)
		if type(payload) ~= "table" then return end
		BALLISTICS.Capture.SetView(payload.good, payload.bad)
	end, {
		read = function()
			return {
				good = net.ReadFloat(),
				bad = net.ReadFloat(),
			}
		end,
	})
end
