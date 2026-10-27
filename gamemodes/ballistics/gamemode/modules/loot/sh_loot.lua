-- Loot rules. No GMod calls.
-- Ammo moves in rounds, not magazines: one left click is one round and each
-- right click adds another round, up to the stack. Two guns can share a type
-- and their clips differ, so a magazine is the wrong unit. When BuyAmmoMags
-- is 0 the ammo row is omitted and ammo is not transferred.
-- The hold is client-side. Opening still has to pass the server checks.
-- +use is not swallowed: doors, Player Ballistics drag, and TacRP safety /
-- melee keep the button. A drag that moves the body cancels the hold.

BALLISTICS = BALLISTICS or {}
BALLISTICS.Loot = BALLISTICS.Loot or {}

local L = BALLISTICS.Loot

L.HOLD = 1
L.MOVE = 24
L.WATCH = 0.2
L.KNIFE = "tacrp_knife"
L.FIT = "Can't fit any more of this item"
L.GUNS = 2

local NOTES = {
	fit = L.FIT,
	busy = "Someone else is looting this body.",
	range = "Too far away.",
	los = "No line of sight.",
	phase = "Looting is closed.",
	giveonly = "They're awake.",
	down = "You can't loot right now.",
	alive = "You can't loot right now.",
	target = "Nothing to loot.",
	self = "Nothing to loot.",
}

local function whole(n, fallback)
	n = tonumber(n)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return math.floor(n)
end

local function clamp(n, lo, hi, fallback)
	n = whole(n, nil)
	if n == nil then return fallback end
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local function coord(v, key)
	if type(v) ~= "table" then return 0 end
	return tonumber(v[key]) or 0
end

function L.Note(err)
	if type(err) ~= "string" then return nil end
	return NOTES[err]
end

function L.PhaseOk(phase)
	return phase == "live" or phase == "post"
end

-- dead and unconscious are two-way. Awake is give only.
function L.TargetMode(alive, conscious)
	if alive ~= true then return "dead" end
	if conscious ~= true then return "unconscious" end
	return "awake"
end

function L.GiveOnly(mode)
	return mode == "awake"
end

-- Use is down when the usercmd says so OR the bound key is physically held
-- (singleplayer has no client-side usercmd buttons).
function L.UseDown(cmdDown, keyDown)
	return cmdDown == true or keyDown == true
end

function L.Range(cfg)
	cfg = type(cfg) == "table" and cfg or {}
	return clamp(cfg.LootRange, 32, 512, 96)
end

function L.Caps(cfg)
	cfg = type(cfg) == "table" and cfg or {}
	local guns = L.GUNS
	if BALLISTICS.Loadout and tonumber(BALLISTICS.Loadout.MAX_GUNS) then
		guns = math.floor(BALLISTICS.Loadout.MAX_GUNS)
	end
	if guns < 1 then guns = 1 end
	if guns > 2 then guns = 2 end
	return {
		meds = clamp(cfg.MedsMax, 0, 100, 3),
		nades = clamp(cfg.GrenadesMax, 0, 100, 3),
		guns = guns,
	}
end

function L.InfiniteAmmo(cfg, phase)
	local mags = nil
	if BALLISTICS.Ammo and type(BALLISTICS.Ammo.ActiveMags) == "function" then
		mags = BALLISTICS.Ammo.ActiveMags(cfg, phase or "live")
	else
		cfg = type(cfg) == "table" and cfg or {}
		mags = cfg.BuyAmmoMags
	end
	if BALLISTICS.Ammo and type(BALLISTICS.Ammo.WantInfinite) == "function" then
		return BALLISTICS.Ammo.WantInfinite(mags) == true
	end
	mags = tonumber(mags)
	if mags == nil or mags ~= mags then return true end
	return math.floor(mags) <= 0
end

function L.Dist(a, b)
	if a == nil or b == nil then return math.huge end
	local dx = coord(a, "x") - coord(b, "x")
	local dy = coord(a, "y") - coord(b, "y")
	local dz = coord(a, "z") - coord(b, "z")
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function L.InRange(dist, range)
	dist = tonumber(dist)
	range = tonumber(range)
	if dist == nil or range == nil then return false end
	if dist ~= dist or range ~= range then return false end
	return dist <= range
end

function L.Moved(a, b, limit)
	limit = tonumber(limit) or L.MOVE
	return L.Dist(a, b) > limit
end

-- In front of the looter, a little off the floor so the gun can settle.
function L.DropPos(origin, forward, dist)
	dist = tonumber(dist) or 40
	origin = type(origin) == "table" and origin or {}
	forward = type(forward) == "table" and forward or { x = 1, y = 0, z = 0 }
	return {
		x = coord(origin, "x") + coord(forward, "x") * dist,
		y = coord(origin, "y") + coord(forward, "y") * dist,
		z = coord(origin, "z") + 8,
	}
end

function L.BodyKey(id)
	if type(id) ~= "string" or id == "" then return nil end
	return "ply:" .. id
end

function L.Lock(map, key, id)
	if type(map) ~= "table" then return false end
	if type(key) ~= "string" or key == "" then return false end
	if type(id) ~= "string" or id == "" then return false end
	local cur = map[key]
	if cur ~= nil and cur ~= id then return false end
	map[key] = id
	return true
end

function L.Unlock(map, key, id)
	if type(map) ~= "table" or type(key) ~= "string" then return end
	if map[key] == nil then return end
	if id ~= nil and map[key] ~= id then return end
	map[key] = nil
end

function L.UnlockAll(map, id)
	if type(map) ~= "table" or id == nil then return end
	local drop = {}
	for key, holder in pairs(map) do
		if holder == id then drop[#drop + 1] = key end
	end
	for i = 1, #drop do
		map[drop[i]] = nil
	end
end

-- A player, or a ragdoll that still points at an owner / body id.
function L.AimOk(info)
	info = type(info) == "table" and info or {}
	if info.isSelf == true then return false end
	if info.isPlayer == true then return true end
	if info.isRagdoll ~= true then return false end
	if type(info.bodyId) == "string" and info.bodyId ~= "" then return true end
	if type(info.lootId) == "string" and info.lootId ~= "" then return true end
	if info.hasOwner == true then return true end
	return false
end

function L.CanOpen(ctx)
	ctx = type(ctx) == "table" and ctx or {}
	if not L.PhaseOk(ctx.phase) then return false, "phase" end
	if ctx.alive ~= true then return false, "alive" end
	if ctx.conscious ~= true then return false, "down" end
	if ctx.self == true then return false, "self" end
	if ctx.target ~= "player" and ctx.target ~= "corpse" then return false, "target" end
	if not L.InRange(ctx.dist, ctx.range) then return false, "range" end
	if ctx.los ~= true then return false, "los" end
	if ctx.busy == true then return false, "busy" end
	return true
end

-- Range, phase, and a live looter keep the window. Line of sight is per transfer.
function L.ShouldClose(ctx)
	ctx = type(ctx) == "table" and ctx or {}
	if not L.PhaseOk(ctx.phase) then return true, "phase" end
	if ctx.alive ~= true then return true, "alive" end
	if ctx.conscious ~= true then return true, "down" end
	if ctx.targetValid ~= true then return true, "target" end
	if not L.InRange(ctx.dist, ctx.range) then return true, "range" end
	return false
end

function L.BeginHold(now, origin)
	return { started = tonumber(now) or 0, origin = origin }
end

function L.HoldTick(hold, now, flags)
	flags = type(flags) == "table" and flags or {}
	local function cancel(reason)
		return { progress = 0, done = false, cancel = true, reason = reason }
	end
	if type(hold) ~= "table" then return cancel("idle") end
	if flags.down ~= true then return cancel("release") end
	if flags.valid ~= true then return cancel("invalid") end
	if flags.inRange ~= true then return cancel("range") end
	if flags.los ~= true then return cancel("los") end
	if flags.hurt == true then return cancel("hurt") end
	if flags.moved == true then return cancel("moved") end
	local held = (tonumber(now) or 0) - (tonumber(hold.started) or 0)
	if held < 0 then held = 0 end
	local progress = held / L.HOLD
	if progress > 1 then progress = 1 end
	return { progress = progress, done = progress >= 1, cancel = false }
end

-- Left press starts at one. Each right click adds one, capped at the stack.
function L.StackAmount(have, picked, clicks)
	have = whole(have, 0)
	if have < 1 then return 0 end
	local n = whole(picked, 1)
	if n < 1 then n = 1 end
	local extra = whole(clicks, 0)
	if extra < 0 then extra = 0 end
	n = n + extra
	if n > have then n = have end
	return n
end

function L.OtherSide(side)
	if side == "you" then return "them" end
	if side == "them" then return "you" end
	return nil
end

function L.SlotId(slot)
	if type(slot) ~= "table" then return "" end
	local index = whole(slot.index, 0)
	return tostring(slot.side or "") .. ":" .. tostring(slot.kind or "")
		.. ":" .. tostring(slot.key or "") .. ":" .. tostring(index)
end

-- A second press on the same slot inside the window is a double-click.
function L.DoubleClick(prev, now, slotId, window)
	if type(prev) ~= "table" or type(slotId) ~= "string" or slotId == "" then return false end
	if prev.id ~= slotId then return false end
	window = tonumber(window) or 0.28
	local dt = (tonumber(now) or 0) - (tonumber(prev.t) or 0)
	if dt ~= dt or dt < 0 or dt > window then return false end
	return true
end

-- Left release. The same slot cancels, so the first half of a double-click
-- does not move one item. A gun released outside both cards drops. A miss
-- inside a card, or anything else released outside, cancels.
function L.Release(drag, target, inside)
	if type(drag) ~= "table" then return "cancel" end
	if type(target) == "table" then
		local origin = {
			side = drag.from,
			kind = drag.kind,
			key = drag.key,
			index = drag.index,
		}
		if L.SlotId(target) ~= "" and L.SlotId(target) == L.SlotId(origin) then
			return "cancel"
		end
		return "move"
	end
	if inside == true then return "cancel" end
	if drag.kind == "gun" then return "drop" end
	return "cancel"
end

function L.MedById(id)
	id = tonumber(id)
	if id == nil then return nil end
	id = math.floor(id)
	local meds = BALLISTICS.Catalog and BALLISTICS.Catalog.Meds and BALLISTICS.Catalog.Meds()
	if type(meds) ~= "table" then return nil end
	for i = 1, #meds do
		if meds[i].id == id then return meds[i] end
	end
	return nil
end

function L.NadeByAmmo(ammo)
	if type(ammo) ~= "string" or ammo == "" then return nil end
	local nades = BALLISTICS.Catalog and BALLISTICS.Catalog.Throwables and BALLISTICS.Catalog.Throwables()
	if type(nades) ~= "table" then return nil end
	for i = 1, #nades do
		if nades[i].ammo == ammo then return nades[i] end
	end
	return nil
end

function L.WeaponName(class)
	if type(class) ~= "string" or class == "" then return "" end
	local cat = BALLISTICS.Catalog
	if cat and type(cat.Get) == "function" then
		local item = cat.Get(class)
		if type(item) == "table" and type(item.name) == "string" and item.name ~= "" then
			return item.name
		end
	end
	return class
end

local function copyAtts(list)
	local out = {}
	if type(list) ~= "table" then return out end
	for i = 1, #list do
		local row = list[i]
		if type(row) == "table" then
			local att = row.att
			if type(att) == "string" and att ~= "" then
				out[#out + 1] = { slot = whole(row.slot, 0), att = att }
			end
		end
	end
	return out
end

local function copyGun(gun)
	if type(gun) ~= "table" then return nil end
	local class = gun.class
	if type(class) ~= "string" or class == "" then return nil end
	local ammo = gun.ammo
	if type(ammo) ~= "string" or ammo == "" or ammo == "none" then ammo = nil end
	return {
		class = class,
		name = type(gun.name) == "string" and gun.name or L.WeaponName(class),
		clip1 = math.max(0, whole(gun.clip1, 0)),
		clip2 = math.max(0, whole(gun.clip2, 0)),
		ammo = ammo,
		attachments = copyAtts(gun.attachments),
	}
end

local function copyCounts(src)
	local out = {}
	if type(src) ~= "table" then return out end
	for key, n in pairs(src) do
		if type(key) == "string" and key ~= "" then
			local v = whole(n, 0)
			if v < 0 then v = 0 end
			out[key] = v
		end
	end
	return out
end

function L.Clone(inv)
	inv = type(inv) == "table" and inv or {}
	local guns = {}
	local src = inv.guns
	if type(src) == "table" then
		for i = 1, #src do
			local gun = copyGun(src[i])
			if gun then guns[#guns + 1] = gun end
		end
	end
	return {
		guns = guns,
		nades = copyCounts(inv.nades),
		meds = copyCounts(inv.meds),
		ammo = copyCounts(inv.ammo),
	}
end

function L.Blank()
	local inv = { guns = {}, nades = {}, meds = {}, ammo = {} }
	local cat = BALLISTICS.Catalog
	if not cat then return inv end
	local nades = cat.Throwables and cat.Throwables() or {}
	for i = 1, #nades do
		inv.nades[nades[i].key] = 0
	end
	local meds = cat.Meds and cat.Meds() or {}
	for i = 1, #meds do
		inv.meds[meds[i].key] = 0
	end
	return inv
end

local function knifeClass(knife)
	if type(knife) == "string" and knife ~= "" then return knife end
	return L.KNIFE
end

local function isKnife(class, knife)
	if type(class) ~= "string" or class == "" then return true end
	if class == knifeClass(knife) then return true end
	if class == L.KNIFE then return true end
	return false
end

local function sideInv(ctx, name)
	if name == "you" then return ctx.you end
	if name == "them" then return ctx.them end
	return nil
end

local function fail(err, you, them)
	return {
		ok = false,
		err = err,
		note = L.Note(err),
		you = you,
		them = them,
		drop = nil,
	}
end

local function findGun(guns, class)
	for i = 1, #guns do
		if guns[i].class == class then return i, guns[i] end
	end
	return nil
end

local function placeGun(guns, gun, slot, max)
	if #guns >= max then return false end
	if findGun(guns, gun.class) then return false end
	local idx = whole(slot, 0)
	if idx < 1 then idx = #guns + 1 end
	if idx > #guns + 1 then idx = #guns + 1 end
	if guns[idx] ~= nil then return false end
	guns[#guns + 1] = gun
	return true
end

local function takeGun(guns, class)
	local idx, gun = findGun(guns, class)
	if not idx then return nil end
	table.remove(guns, idx)
	return gun
end

local function countOf(map, key)
	if type(map) ~= "table" then return 0 end
	local n = whole(map[key], 0)
	if n < 0 then return 0 end
	return n
end

local function putCount(map, key, n)
	if n < 0 then n = 0 end
	map[key] = n
end

function L.Transfer(ctx)
	ctx = type(ctx) == "table" and ctx or {}
	local you = L.Clone(ctx.you)
	local them = L.Clone(ctx.them)
	local originYou = L.Clone(ctx.you)
	local originThem = L.Clone(ctx.them)
	local fromName = ctx.from
	local toName = ctx.to
	if fromName ~= "you" and fromName ~= "them" then
		return fail("side", originYou, originThem)
	end
	if toName ~= "you" and toName ~= "them" and toName ~= "drop" then
		return fail("side", originYou, originThem)
	end
	if ctx.giveOnly == true and fromName == "them" then
		return fail("giveonly", originYou, originThem)
	end
	if fromName == toName then
		return fail("same", originYou, originThem)
	end
	local kind = ctx.kind
	if kind ~= "gun" and kind ~= "nade" and kind ~= "med" and kind ~= "ammo" then
		return fail("kind", originYou, originThem)
	end
	if kind == "ammo" and ctx.infiniteAmmo == true then
		return fail("ammo", originYou, originThem)
	end
	local key = ctx.key
	if type(key) ~= "string" or key == "" then
		return fail("empty", originYou, originThem)
	end
	local knife = knifeClass(ctx.knife)
	if kind == "gun" and isKnife(key, knife) then
		return fail("knife", originYou, originThem)
	end
	local caps = ctx.caps or L.Caps(nil)
	local source = sideInv({ you = you, them = them }, fromName)
	local dest = nil
	if toName == "you" or toName == "them" then
		dest = sideInv({ you = you, them = them }, toName)
	end

	if kind == "gun" then
		local gun = takeGun(source.guns, key)
		if not gun then return fail("empty", originYou, originThem) end
		if toName == "drop" then
			return {
				ok = true,
				you = you,
				them = them,
				drop = gun,
				moved = 1,
			}
		end
		local maxGuns = whole(caps.guns, L.GUNS)
		if not placeGun(dest.guns, gun, ctx.slot, maxGuns) then
			return fail("fit", originYou, originThem)
		end
		return { ok = true, you = you, them = them, drop = nil, moved = 1 }
	end

	-- Only a gun can leave the window. A stack has nowhere to land.
	if toName == "drop" then
		return fail("kind", originYou, originThem)
	end

	local mapName = kind == "nade" and "nades" or (kind == "med" and "meds" or "ammo")
	local sourceCount = countOf(source[mapName], key)
	if sourceCount < 1 then return fail("empty", originYou, originThem) end
	local amount = whole(ctx.amount, 1)
	if ctx.whole == true then amount = sourceCount end
	if amount == nil or amount < 1 then return fail("amount", originYou, originThem) end
	local cap = 1000000
	if kind == "nade" then cap = whole(caps.nades, 3) end
	if kind == "med" then cap = whole(caps.meds, 3) end
	local destCount = dest and countOf(dest[mapName], key) or 0
	local space = cap - destCount
	if space < 1 then return fail("fit", originYou, originThem) end
	if amount > sourceCount then amount = sourceCount end
	if amount > space then amount = space end
	if amount < 1 then return fail("fit", originYou, originThem) end
	putCount(source[mapName], key, sourceCount - amount)
	putCount(dest[mapName], key, destCount + amount)
	return { ok = true, you = you, them = them, drop = nil, moved = amount }
end

-- Highlight: a slot accepts the drag when that drop would actually move.
function L.Accepts(drag, slot, ctx)
	if type(drag) ~= "table" or type(slot) ~= "table" then return false end
	if drag.kind ~= slot.kind then return false end
	if drag.kind ~= "gun" and drag.key ~= slot.key then return false end
	if drag.from == slot.side then return false end
	if slot.side ~= "you" and slot.side ~= "them" then return false end
	ctx = type(ctx) == "table" and ctx or {}
	local result = L.Transfer({
		you = ctx.you,
		them = ctx.them,
		from = drag.from,
		kind = drag.kind,
		key = drag.key,
		amount = drag.amount or 1,
		to = slot.side,
		slot = slot.index,
		giveOnly = ctx.giveOnly,
		caps = ctx.caps,
		infiniteAmmo = ctx.infinite,
		knife = ctx.knife,
		whole = false,
	})
	return result.ok == true
end

local function nadeAmmoSet()
	local skip = {}
	local nades = BALLISTICS.Catalog and BALLISTICS.Catalog.Throwables and BALLISTICS.Catalog.Throwables()
	if type(nades) ~= "table" then return skip end
	for i = 1, #nades do
		local ammo = nades[i].ammo
		if type(ammo) == "string" and ammo ~= "" then skip[ammo] = true end
	end
	return skip
end

function L.AmmoKeys(you, them, infinite)
	if infinite == true then return {} end
	local skip = nadeAmmoSet()
	local used = {}
	local function take(inv)
		local guns = type(inv) == "table" and inv.guns or nil
		if type(guns) ~= "table" then return end
		for i = 1, #guns do
			local ammo = guns[i] and guns[i].ammo
			if type(ammo) == "string" and ammo ~= "" and ammo ~= "none" and not skip[ammo] then
				used[ammo] = true
			end
		end
	end
	take(you)
	take(them)
	local keys = {}
	for key in pairs(used) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function stackRows(order, counts, cap)
	local rows = {}
	counts = type(counts) == "table" and counts or {}
	for i = 1, #order do
		local item = order[i]
		local n = whole(counts[item.key], 0)
		if n < 0 then n = 0 end
		rows[#rows + 1] = {
			key = item.key,
			name = item.name or item.key,
			id = item.id,
			count = n,
			cap = cap,
		}
	end
	return rows
end

function L.SideView(inv, caps, infinite, ammoKeys)
	inv = L.Clone(inv)
	caps = caps or L.Caps(nil)
	local guns = {}
	for i = 1, L.GUNS do
		local gun = inv.guns[i]
		local row = { slot = i }
		if gun then
			row.class = gun.class
			row.name = gun.name or L.WeaponName(gun.class)
			row.clip1 = gun.clip1 or 0
			row.ammo = gun.ammo
			row.attachments = gun.attachments or {}
		end
		guns[i] = row
	end
	local nadeOrder = {}
	local medOrder = {}
	local cat = BALLISTICS.Catalog
	if cat and cat.Throwables then nadeOrder = cat.Throwables() or {} end
	if cat and cat.Meds then medOrder = cat.Meds() or {} end
	if infinite == true then
		ammoKeys = {}
	elseif type(ammoKeys) ~= "table" then
		ammoKeys = L.AmmoKeys(inv, nil, false)
	end
	local ammo = {}
	for i = 1, #ammoKeys do
		local key = ammoKeys[i]
		ammo[i] = {
			key = key,
			name = key,
			count = countOf(inv.ammo, key),
		}
	end
	return {
		guns = guns,
		nades = stackRows(nadeOrder, inv.nades, caps.nades),
		meds = stackRows(medOrder, inv.meds, caps.meds),
		ammo = ammo,
	}
end

-- Both sides list every ammo type the guns on either side use, so a stack
-- has a slot to land in. Infinite ammo leaves the row empty.
function L.View(you, them, opts)
	opts = type(opts) == "table" and opts or {}
	local caps = opts.caps or L.Caps(nil)
	local infinite = opts.infinite == true
	local ammoKeys = L.AmmoKeys(you, them, infinite)
	return {
		open = opts.open ~= false,
		giveOnly = opts.giveOnly == true,
		infinite = infinite,
		note = type(opts.note) == "string" and opts.note or "",
		caps = caps,
		you = L.SideView(you, caps, infinite, ammoKeys),
		them = L.SideView(them, caps, infinite, ammoKeys),
	}
end

-- Client highlight uses the same transfer rules as the server. Rebuild the
-- inventory maps from the rows the state message carried.
function L.InvFromSide(side)
	side = type(side) == "table" and side or {}
	local inv = { guns = {}, nades = {}, meds = {}, ammo = {} }
	local guns = side.guns or {}
	for i = 1, #guns do
		local row = guns[i]
		if type(row) == "table" and type(row.class) == "string" and row.class ~= "" then
			inv.guns[#inv.guns + 1] = copyGun(row)
		end
	end
	local function counts(rows, into)
		if type(rows) ~= "table" then return end
		for i = 1, #rows do
			local row = rows[i]
			if type(row) == "table" and type(row.key) == "string" and row.key ~= "" then
				local n = whole(row.count, 0)
				if n < 0 then n = 0 end
				into[row.key] = n
			end
		end
	end
	counts(side.nades, inv.nades)
	counts(side.meds, inv.meds)
	counts(side.ammo, inv.ammo)
	return inv
end

-- Two centred halves with a gap. Same dark-panel idea as the buy wheel.
function L.PanelBox(scrW, scrH)
	scrW = tonumber(scrW) or 0
	scrH = tonumber(scrH) or 0
	if scrW ~= scrW or scrW < 1 then scrW = 1280 end
	if scrH ~= scrH or scrH < 1 then scrH = 720 end
	local gap = 16
	local w = math.floor((scrW - 48 - gap) / 2)
	if w > 520 then w = 520 end
	if w < 220 then w = 220 end
	local h = scrH - 48
	if h > 640 then h = 640 end
	if h < 280 then h = 280 end
	local total = w * 2 + gap
	local x = math.floor((scrW - total) / 2)
	local y = math.floor((scrH - h) / 2)
	if x < 0 then x = 0 end
	if y < 0 then y = 0 end
	return {
		gap = gap,
		left = { x = x, y = y, w = w, h = h },
		right = { x = x + w + gap, y = y, w = w, h = h },
	}
end

local function u8(n)
	n = whole(n, 0)
	if n < 0 then n = 0 end
	if n > 255 then n = 255 end
	return n
end

local function u16(n)
	n = whole(n, 0)
	if n < 0 then n = 0 end
	if n > 65535 then n = 65535 end
	return n
end

local function writeGun(w, row)
	local present = type(row) == "table" and type(row.class) == "string" and row.class ~= ""
	w.bool(present)
	if not present then return end
	w.string(row.class)
	w.string(row.name or "")
	w.uint16(u16(row.clip1))
	w.string(type(row.ammo) == "string" and row.ammo or "")
	local atts = row.attachments or {}
	w.uint8(#atts)
	for i = 1, #atts do
		w.uint8(u8(atts[i].slot))
		w.string(atts[i].att or "")
	end
end

local function readGun(r, slot)
	local row = { slot = slot }
	if r.bool() ~= true then return row end
	row.class = r.string()
	row.name = r.string()
	row.clip1 = r.uint16()
	local ammo = r.string()
	if ammo ~= "" then row.ammo = ammo end
	local n = r.uint8()
	row.attachments = {}
	for i = 1, n do
		local attSlot = r.uint8()
		local att = r.string()
		row.attachments[i] = { slot = attSlot, att = att }
	end
	return row
end

local function writeStack(w, row)
	w.string(row.key or "")
	w.string(row.name or "")
	w.uint16(u16(row.count))
	w.uint16(u16(row.cap))
end

local function readStack(r)
	return {
		key = r.string(),
		name = r.string(),
		count = r.uint16(),
		cap = r.uint16(),
	}
end

local function writeSide(w, side)
	side = type(side) == "table" and side or {}
	local guns = side.guns or {}
	writeGun(w, guns[1])
	writeGun(w, guns[2])
	local nades = side.nades or {}
	w.uint8(#nades)
	for i = 1, #nades do
		writeStack(w, nades[i])
	end
	local meds = side.meds or {}
	w.uint8(#meds)
	for i = 1, #meds do
		writeStack(w, meds[i])
		w.uint8(u8(meds[i].id))
	end
	local ammo = side.ammo or {}
	w.uint8(#ammo)
	for i = 1, #ammo do
		w.string(ammo[i].key or "")
		w.string(ammo[i].name or "")
		w.uint16(u16(ammo[i].count))
	end
end

local function readSide(r)
	local guns = { readGun(r, 1), readGun(r, 2) }
	local nades = {}
	local nadeCount = r.uint8()
	for i = 1, nadeCount do
		nades[i] = readStack(r)
	end
	local meds = {}
	local medCount = r.uint8()
	for i = 1, medCount do
		local row = readStack(r)
		row.id = r.uint8()
		meds[i] = row
	end
	local ammo = {}
	local ammoCount = r.uint8()
	for i = 1, ammoCount do
		ammo[i] = { key = r.string(), name = r.string(), count = r.uint16() }
	end
	return { guns = guns, nades = nades, meds = meds, ammo = ammo }
end

function L.WriteState(w, state)
	state = type(state) == "table" and state or {}
	w.bool(state.open == true)
	w.string(type(state.note) == "string" and state.note or "")
	if state.open ~= true then return end
	w.bool(state.giveOnly == true)
	w.bool(state.infinite == true)
	local caps = state.caps or {}
	w.uint16(u16(caps.meds or 3))
	w.uint16(u16(caps.nades or 3))
	w.uint8(u8(caps.guns or 2))
	writeSide(w, state.you)
	writeSide(w, state.them)
end

function L.ReadState(r)
	local open = r.bool() == true
	local note = r.string()
	if type(note) ~= "string" then note = "" end
	if not open then
		return { open = false, note = note }
	end
	local giveOnly = r.bool() == true
	local infinite = r.bool() == true
	local caps = {
		meds = r.uint16(),
		nades = r.uint16(),
		guns = r.uint8(),
	}
	return {
		open = true,
		note = note,
		giveOnly = giveOnly,
		infinite = infinite,
		caps = caps,
		you = readSide(r),
		them = readSide(r),
	}
end

function L.WriteAct(w, req)
	req = type(req) == "table" and req or {}
	w.string(type(req.from) == "string" and req.from or "")
	w.string(type(req.kind) == "string" and req.kind or "")
	w.string(type(req.key) == "string" and req.key or "")
	w.uint16(u16(req.amount))
	w.string(type(req.to) == "string" and req.to or "")
	w.uint8(u8(req.slot))
	w.bool(req.whole == true)
end

function L.ReadAct(r)
	return {
		from = r.string(),
		kind = r.string(),
		key = r.string(),
		amount = r.uint16(),
		to = r.string(),
		slot = r.uint8(),
		whole = r.bool() == true,
	}
end
