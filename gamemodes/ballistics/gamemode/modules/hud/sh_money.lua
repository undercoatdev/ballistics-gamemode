-- Money HUD model. No GMod calls.
-- "$balance" sits bottom-middle. "+pending" sits to its right, in green.

BALLISTICS = BALLISTICS or {}
BALLISTICS.MoneyHud = BALLISTICS.MoneyHud or {}

local H = BALLISTICS.MoneyHud

local HEIGHT = 24
local MARGIN = 36

local function whole(n)
	n = tonumber(n)
	if not n or n ~= n or n == math.huge or n == -math.huge then return 0 end
	n = math.floor(n)
	if n < 0 then return 0 end
	return n
end

function H.Parts(balance, pending)
	return "$" .. tostring(whole(balance)), "+" .. tostring(whole(pending))
end

function H.Colors()
	return {
		balance = { r = 245, g = 245, b = 245 },
		pending = { r = 80, g = 220, b = 110 },
	}
end

-- Widths are measured by the client. The pair is centred as one line.
function H.Place(screenW, screenH, balanceWidth, pendingWidth, gap)
	gap = tonumber(gap) or 12
	if gap < 0 then gap = 0 end
	local bw = tonumber(balanceWidth) or 0
	local pw = tonumber(pendingWidth) or 0
	if bw < 0 then bw = 0 end
	if pw < 0 then pw = 0 end
	local sw = tonumber(screenW) or 0
	local sh = tonumber(screenH) or 0
	if sw < 0 then sw = 0 end
	if sh < 0 then sh = 0 end
	local total = bw + gap + pw
	local x = math.floor((sw - total) / 2)
	if x < 0 then x = 0 end
	local y = math.floor(sh - MARGIN - HEIGHT)
	if y < 0 then y = 0 end
	return {
		y = y,
		h = HEIGHT,
		balance = { x = x, y = y, w = bw, h = HEIGHT },
		pending = { x = x + bw + gap, y = y, w = pw, h = HEIGHT },
	}
end
