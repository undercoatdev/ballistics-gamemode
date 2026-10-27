-- Throwables key and the keybind list. No GMod calls.
-- Tap is a short press. Hold opens TacRP's throwable menu. 0 magazines of
-- input is not this file: callers pass key state in.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Keys = BALLISTICS.Keys or {}

local K = BALLISTICS.Keys

-- Source BUTTON and KEY enums used when the game constants are missing.
K.KEY_NONE = 0
K.KEY_4 = 5
K.KEY_G = 17
K.KEY_H = 18
K.KEY_F1 = 92
K.IN_GRENADE1 = 8388608
K.IN_GRENADE2 = 16777216
K.TAP = 0.25
K.PULSE = 3
K.REVEAL = 4
K.TAG = "F1 Keybinds"

local KEY_NAME = { [0] = "NONE" }
for i = 0, 9 do
	KEY_NAME[i + 1] = tostring(i)
end
for i = 1, 26 do
	KEY_NAME[10 + i] = string.char(64 + i)
end
KEY_NAME[92] = "F1"
KEY_NAME[93] = "F2"

function K.KeyName(code)
	code = tonumber(code)
	if not code then return "?" end
	return KEY_NAME[math.floor(code)] or tostring(math.floor(code))
end

-- A backup that IsKeyDown never reports, so G stops being TacRP's quick throw.
-- 0 is KEY_NONE. Later codes are F10–F12, then scroll lock.
function K.DeadBackup(isDown)
	local list = { 0, 101, 102, 103, 71 }
	if type(isDown) ~= "function" then return 0 end
	for i = 1, #list do
		if isDown(list[i]) ~= true then return list[i] end
	end
	return 0
end

function K.Fresh()
	return { down = false, pressedAt = nil, ticks = 0, menu = false }
end

-- typing cancels the gesture so a chat release cannot throw.
function K.Step(state, down, now, typing)
	state = type(state) == "table" and state or K.Fresh()
	local out = {
		down = state.down == true,
		pressedAt = state.pressedAt,
		ticks = tonumber(state.ticks) or 0,
		menu = state.menu == true,
	}
	if typing == true then
		out.down = false
		out.pressedAt = nil
		out.menu = false
		out.ticks = 0
		return out
	end
	down = down == true
	now = tonumber(now) or 0
	if down and not out.down then
		out.down = true
		out.pressedAt = now
		out.ticks = 0
		out.menu = false
		return out
	end
	if down and out.down then
		local held = now - (tonumber(out.pressedAt) or now)
		if held >= K.TAP then
			out.menu = true
			out.ticks = 0
		end
		return out
	end
	if (not down) and out.down then
		local held = now - (tonumber(out.pressedAt) or now)
		out.down = false
		out.menu = false
		out.pressedAt = nil
		if held >= 0 and held < K.TAP then
			out.ticks = K.PULSE
		else
			out.ticks = 0
		end
	end
	return out
end

function K.TakeTick(state)
	if type(state) ~= "table" then return false end
	local n = tonumber(state.ticks) or 0
	if n <= 0 then
		state.ticks = 0
		return false
	end
	state.ticks = n - 1
	return true
end

-- pulsing: release pulse wants IN_GRENADE1.
-- menu: hold wants IN_GRENADE2.
-- boundToThrow1 / boundToThrow2: the player's own bind is this key, so we must
-- not add the button a second time.
-- gDown + unbound +grenade1: TacRP's hardcoded G fallback, which we strip
-- unless this tick is our own pulse.
function K.Intent(opts)
	opts = type(opts) == "table" and opts or {}
	local add1 = opts.pulsing == true and opts.boundToThrow1 ~= true
	local add2 = opts.menu == true and opts.boundToThrow2 ~= true
	local strip = opts.gDown == true and opts.grenade1Bound ~= true and not add1
	return { add1 = add1, add2 = add2, strip = strip }
end

local function hasBit(n, mask)
	return math.floor(n / mask) % 2 == 1
end

local function setBit(n, mask, on)
	local onNow = hasBit(n, mask)
	if on and not onNow then return n + mask end
	if (not on) and onNow then return n - mask end
	return n
end

function K.ApplyButtons(buttons, intent)
	buttons = tonumber(buttons) or 0
	if buttons ~= buttons or buttons < 0 then buttons = 0 end
	buttons = math.floor(buttons)
	intent = type(intent) == "table" and intent or {}
	if intent.strip then buttons = setBit(buttons, K.IN_GRENADE1, false) end
	if intent.add1 then buttons = setBit(buttons, K.IN_GRENADE1, true) end
	if intent.add2 then buttons = setBit(buttons, K.IN_GRENADE2, true) end
	return buttons
end

function K.SameBind(bind, keyCode, lookup, codeOf)
	if type(lookup) ~= "function" or type(codeOf) ~= "function" then return false end
	local name = lookup(bind)
	if type(name) ~= "string" or name == "" then return false end
	local code = codeOf(string.lower(name))
	if code == nil then code = codeOf(name) end
	return tonumber(code) ~= nil and tonumber(code) == tonumber(keyCode)
end

function K.BlockBind(bind, throwKey)
	if type(bind) ~= "string" then return false end
	local name = string.lower(bind)
	if name == "gm_showhelp" then return true end
	if tonumber(throwKey) == K.KEY_4 and name == "slot4" then return true end
	return false
end

function K.Rows(binds)
	binds = type(binds) == "table" and binds or {}
	local function line(key, action)
		return { key = key, action = action }
	end
	local rows = {
		line(binds.customize or "C", "Customize / buy wheel"),
		line(binds.throw or "4", "Tap quick throw / hold menu"),
		line(binds.inspect or "G", "Medical / self-inspect"),
		line(binds.blindfire or "H", "Blindfire menu"),
		line(binds.safety or "E", "Safety / melee"),
		line(binds.teams or "F2", "Teams (lobby)"),
		line("1 2 3", "Weapons"),
	}
	if binds.isAdmin == true then
		rows[#rows + 1] = line(binds.admin or "F3", "Admin")
	end
	if type(binds.med) == "string" and binds.med ~= "" then
		rows[#rows + 1] = line(binds.med, "Medical wheel")
	end
	return rows
end

function K.Scale(scrW)
	scrW = tonumber(scrW) or 0
	if scrW ~= scrW or scrW <= 0 then scrW = 640 end
	return scrW / 640
end

-- Same anchor as TacRP DrawHints: a few pixels in from the left, centred on
-- the screen height. The open list is wider than TacRP's because the lines
-- are sentences. The collapsed tag is one row.
-- textW: widest line in pixels. Width hugs the text plus padding.
K.PAD = 8

function K.FitWidth(textW, s, open)
	local tw = tonumber(textW)
	if tw and tw == tw and tw > 0 then
		return math.floor(tw + 2 * K.PAD)
	end
	return math.floor((open and 140 or 70) * (tonumber(s) or 1))
end

function K.PanelBox(rowCount, scrW, scrH, open, textW)
	local s = K.Scale(scrW)
	local row = math.floor(12 * s)
	if row < 1 then row = 1 end
	local n = math.floor(tonumber(rowCount) or 0)
	if n < 1 then n = 1 end
	local h = open and (n * row) or row
	local scr = tonumber(scrH) or 0
	if scr ~= scr or scr < 0 then scr = 0 end
	return {
		x = math.max(8, math.floor(4 * s)),
		y = math.floor(scr / 2 - h / 2),
		w = K.FitWidth(textW, s, open),
		h = h,
		row = row,
	}
end

function K.ShowList(pinned, now, revealUntil)
	if pinned == true then return true end
	now = tonumber(now) or 0
	revealUntil = tonumber(revealUntil) or 0
	return now < revealUntil
end

-- Spawns and weapon switches no longer reveal the list (only F1 does).
function K.NoteSpawn(now)
	return 0
end

-- F1 closes a visible list (and cancels the spawn timer) or pins it open.
function K.ToggleList(pinned, now, revealUntil)
	now = tonumber(now) or 0
	if K.ShowList(pinned, now, revealUntil) then
		return false, now
	end
	return true, revealUntil
end
