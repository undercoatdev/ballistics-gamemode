-- Loot rules, the server session, and the client hold. Run: luajit tests/test_loot.lua
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
dofile("gamemodes/ballistics/gamemode/core/sh_config.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_teams.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_net.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_deps.lua")
dofile("gamemodes/ballistics/gamemode/core/sh_catalog.lua")
dofile("gamemodes/ballistics/gamemode/modules/buy/sh_buy.lua")
dofile("gamemodes/ballistics/gamemode/modules/loadout/sh_loadout.lua")
dofile("gamemodes/ballistics/gamemode/modules/loadout/sv_loadout.lua")
dofile("gamemodes/ballistics/gamemode/modules/ammo/sh_ammo.lua")
dofile("gamemodes/ballistics/gamemode/core/sv_slots.lua")
dofile("gamemodes/ballistics/gamemode/modules/loot/sh_loot.lua")

local L = BALLISTICS.Loot

local function readAll(path)
	local f = io.open(path, "r")
	if not f then return "" end
	local text = f:read("*a")
	f:close()
	return text
end

check("hold is one second", L.HOLD == 1)
check("a body that moves 24 units has not moved", L.Moved({ x = 0, y = 0, z = 0 }, { x = 24, y = 0, z = 0 }, L.MOVE) == false)
check("a body that moves past 24 units has moved", L.Moved({ x = 0, y = 0, z = 0 }, { x = 24.1, y = 0, z = 0 }, L.MOVE) == true)
check("the range edge is still in range", L.InRange(96, 96) == true and L.InRange(96.1, 96) == false)
check("loot is live and post only", L.PhaseOk("live") == true and L.PhaseOk("post") == true and L.PhaseOk("buy") == false and L.PhaseOk("lobby") == false and L.PhaseOk("squad") == false)
check("dead and unconscious are two-way", L.GiveOnly(L.TargetMode(false, false)) == false and L.GiveOnly(L.TargetMode(true, false)) == false)
check("awake is give only", L.TargetMode(true, true) == "awake" and L.GiveOnly("awake") == true)
check("default caps", L.Caps(nil).meds == 3 and L.Caps(nil).nades == 3 and L.Caps(nil).guns == 2)
check("zero magazines is infinite ammo", L.InfiniteAmmo({ BuyAmmoMags = 0 }, "live") == true and L.InfiniteAmmo({ BuyAmmoMags = 3 }, "live") == false)

local hold = L.BeginHold(10, { x = 1, y = 2, z = 3 })
local flags = { down = true, valid = true, inRange = true, los = true, hurt = false, moved = false }
local tick = L.HoldTick(hold, 10.5, flags)
check("half a hold is half a ring", math.abs(tick.progress - 0.5) < 1e-9 and tick.done == false and tick.cancel == false)
tick = L.HoldTick(hold, 11, flags)
check("a full hold requests open", tick.progress == 1 and tick.done == true and tick.cancel == false)
tick = L.HoldTick(hold, 10.5, { down = false, valid = false, inRange = false, los = false, hurt = true, moved = true })
check("releasing the button cancels before the other reasons", tick.cancel == true and tick.reason == "release" and tick.progress == 0)
tick = L.HoldTick(hold, 10.5, { down = true, valid = false, inRange = false, los = false, hurt = true, moved = true })
check("an invalid target cancels before range", tick.reason == "invalid")
tick = L.HoldTick(hold, 10.5, { down = true, valid = true, inRange = false, los = false, hurt = true, moved = true })
check("range cancels before line of sight", tick.reason == "range")
tick = L.HoldTick(hold, 10.5, { down = true, valid = true, inRange = true, los = false, hurt = true, moved = true })
check("line of sight cancels before damage", tick.reason == "los")
tick = L.HoldTick(hold, 10.5, { down = true, valid = true, inRange = true, los = true, hurt = true, moved = true })
check("damage cancels before a drag", tick.reason == "hurt")
tick = L.HoldTick(hold, 10.5, { down = true, valid = true, inRange = true, los = true, hurt = false, moved = true })
check("a dragged body cancels the hold", tick.reason == "moved")

check("one click takes one", L.StackAmount(5, 1, 0) == 1)
check("right clicks add one more up to the stack", L.StackAmount(5, 1, 2) == 3 and L.StackAmount(2, 1, 9) == 2)
check("an empty stack stays empty", L.StackAmount(0, 1, 3) == 0)

check("a player is lootable", L.AimOk({ isPlayer = true }) == true)
check("your own body is not lootable", L.AimOk({ isSelf = true, isPlayer = true, isRagdoll = true, bodyId = "x" }) == false)
check("a linked ragdoll is lootable", L.AimOk({ isRagdoll = true, bodyId = "body" }) == true)
check("a marked ragdoll is lootable", L.AimOk({ isRagdoll = true, lootId = "ply" }) == true)
check("an owned ragdoll is lootable", L.AimOk({ isRagdoll = true, hasOwner = true }) == true)
check("a bare prop is not lootable", L.AimOk({ isRagdoll = false }) == false)

local openOk, openErr = L.CanOpen({ phase = "buy", alive = true, conscious = true, target = "player", dist = 10, range = 96, los = true })
check("buy phase is refused first", openOk == false and openErr == "phase")
openOk, openErr = L.CanOpen({ phase = "live", alive = false, conscious = false, target = "player", dist = 10, range = 96, los = true })
check("a dead looter is refused", openOk == false and openErr == "alive")
openOk, openErr = L.CanOpen({ phase = "live", alive = true, conscious = false, target = "player", dist = 10, range = 96, los = true })
check("an unconscious looter is refused", openOk == false and openErr == "down")
openOk, openErr = L.CanOpen({ phase = "live", alive = true, conscious = true, self = true, target = "player", dist = 10, range = 96, los = true })
check("looting yourself is refused", openOk == false and openErr == "self")
openOk, openErr = L.CanOpen({ phase = "live", alive = true, conscious = true, target = "nope", dist = 10, range = 96, los = true })
check("a bad target is refused", openOk == false and openErr == "target")
openOk, openErr = L.CanOpen({ phase = "live", alive = true, conscious = true, target = "corpse", dist = 100, range = 96, los = false })
check("range is refused before line of sight", openOk == false and openErr == "range")
openOk, openErr = L.CanOpen({ phase = "live", alive = true, conscious = true, target = "corpse", dist = 10, range = 96, los = false })
check("line of sight is required to open", openOk == false and openErr == "los")
openOk, openErr = L.CanOpen({ phase = "post", alive = true, conscious = true, target = "player", dist = 96, range = 96, los = true, busy = true })
check("a locked body is busy", openOk == false and openErr == "busy")
openOk = L.CanOpen({ phase = "live", alive = true, conscious = true, target = "player", dist = 96, range = 96, los = true })
check("a live player in range can be opened", openOk == true)

local shut, why = L.ShouldClose({ phase = "live", alive = true, conscious = true, targetValid = true, dist = 10, range = 96 })
check("line of sight does not close the window", shut == false)
shut, why = L.ShouldClose({ phase = "live", alive = true, conscious = true, targetValid = true, dist = 97, range = 96 })
check("leaving range closes the window", shut == true and why == "range")
check("the fit note is the exact sentence", L.Note("fit") == "Can't fit any more of this item" and L.FIT == "Can't fit any more of this item")
check("a quiet error has no banner", L.Note("same") == nil and L.Note("knife") == nil and L.Note("empty") == nil)

local you = L.Blank()
local them = L.Blank()
you.guns[1] = { class = "tacrp_mp5", clip1 = 12, ammo = "smg1", attachments = { { slot = 1, att = "optic_test" } } }
you.nades.nade_frag = 2
you.meds.med_pills = 1
you.ammo.smg1 = 40
them.nades.nade_frag = 1
them.meds.med_pills = 3
them.ammo.smg1 = 5
local moved = L.Transfer({
	you = you, them = them, from = "you", kind = "gun", key = "tacrp_mp5",
	amount = 1, to = "them", slot = 2, caps = L.Caps(nil),
})
check("a gun keeps its mag and attachments", moved.ok == true and moved.them.guns[1].class == "tacrp_mp5" and moved.them.guns[1].clip1 == 12 and moved.them.guns[1].attachments[1].att == "optic_test" and #moved.you.guns == 0)
check("an empty slot 2 still lands in the first free slot", #moved.them.guns == 1)
local dup = L.Transfer({
	you = { guns = { { class = "tacrp_mp5", clip1 = 1 } }, nades = {}, meds = {}, ammo = {} },
	them = moved.them, from = "you", kind = "gun", key = "tacrp_mp5", amount = 1, to = "them", slot = 0,
})
check("a duplicate gun does not fit", dup.ok == false and dup.err == "fit" and dup.note == L.FIT)
local knife = L.Transfer({
	you = { guns = { { class = "tacrp_knife", clip1 = 0 } }, nades = {}, meds = {}, ammo = {} },
	them = L.Blank(), from = "you", kind = "gun", key = "tacrp_knife", amount = 1, to = "them", slot = 0,
})
check("the knife is never transferred", knife.ok == false and knife.err == "knife")
local full = L.Transfer({
	you = { guns = { { class = "tacrp_mp5" }, { class = "tacrp_ex_ak47" } }, nades = {}, meds = {}, ammo = {} },
	them = { guns = { { class = "tacrp_spr" } }, nades = {}, meds = {}, ammo = {} },
	from = "them", kind = "gun", key = "tacrp_spr", amount = 1, to = "you", slot = 0, caps = { guns = 2, meds = 3, nades = 3 },
})
check("a third gun does not fit", full.ok == false and full.err == "fit")
local give = L.Transfer({
	you = L.Blank(), them = L.Blank(), from = "them", kind = "med", key = "med_pills",
	amount = 1, to = "you", giveOnly = true, caps = L.Caps(nil),
})
check("an awake body cannot be taken from", give.ok == false and give.err == "giveonly" and give.note == "They're awake.")
local partial = L.Transfer({
	you = { guns = {}, nades = {}, meds = { med_pills = 2 }, ammo = {} },
	them = { guns = {}, nades = {}, meds = { med_pills = 4 }, ammo = {} },
	from = "them", kind = "med", key = "med_pills", amount = 4, to = "you", caps = { meds = 3, nades = 3, guns = 2 },
})
check("a stack moves until the cap", partial.ok == true and partial.moved == 1 and partial.you.meds.med_pills == 3 and partial.them.meds.med_pills == 3)
local none = L.Transfer({
	you = { guns = {}, nades = {}, meds = { med_pills = 3 }, ammo = {} },
	them = { guns = {}, nades = {}, meds = { med_pills = 1 }, ammo = {} },
	from = "them", kind = "med", key = "med_pills", amount = 1, to = "you", caps = { meds = 3, nades = 3, guns = 2 },
})
check("a full med stack fits nothing", none.ok == false and none.note == "Can't fit any more of this item")
local whole = L.Transfer({
	you = L.Blank(), them = { guns = {}, nades = { nade_frag = 2 }, meds = {}, ammo = {} },
	from = "them", kind = "nade", key = "nade_frag", amount = 1, to = "you", whole = true, caps = L.Caps(nil),
})
check("a double-click moves the whole stack", whole.ok == true and whole.moved == 2 and whole.you.nades.nade_frag == 2 and whole.them.nades.nade_frag == 0)
local ammoMove = L.Transfer({
	you = { guns = { { class = "tacrp_mp5", ammo = "smg1" } }, nades = {}, meds = {}, ammo = { smg1 = 10 } },
	them = { guns = { { class = "tacrp_mp5", ammo = "smg1" } }, nades = {}, meds = {}, ammo = { smg1 = 1 } },
	from = "you", kind = "ammo", key = "smg1", amount = 4, to = "them",
})
check("ammo moves in rounds", ammoMove.ok == true and ammoMove.moved == 4 and ammoMove.you.ammo.smg1 == 6 and ammoMove.them.ammo.smg1 == 5)
local ammoNo = L.Transfer({
	you = ammoMove.you, them = ammoMove.them, from = "you", kind = "ammo", key = "smg1",
	amount = 1, to = "them", infiniteAmmo = true,
})
check("infinite ammo is not transferred", ammoNo.ok == false and ammoNo.err == "ammo")
local dropped = L.Transfer({
	you = { guns = { { class = "tacrp_mp5", clip1 = 4, attachments = { { slot = 2, att = "supp" } } } }, nades = {}, meds = {}, ammo = {} },
	them = L.Blank(), from = "you", kind = "gun", key = "tacrp_mp5", amount = 1, to = "drop",
})
check("a gun can be dropped", dropped.ok == true and dropped.drop.class == "tacrp_mp5" and dropped.drop.clip1 == 4 and dropped.drop.attachments[1].att == "supp" and #dropped.you.guns == 0)
local stackDrop = L.Transfer({
	you = { guns = {}, nades = { nade_frag = 1 }, meds = {}, ammo = {} },
	them = L.Blank(), from = "you", kind = "nade", key = "nade_frag", amount = 1, to = "drop",
})
check("a stack cannot be dropped", stackDrop.ok == false and stackDrop.err == "kind")
local selfNade = L.Transfer({
	you = { guns = {}, nades = { nade_frag = 3 }, meds = {}, ammo = {} },
	them = L.Blank(), from = "you", kind = "nade", key = "nade_frag", amount = 5, to = "drop",
	selfDrop = true,
})
check("own inventory drops a grenade stack", selfNade.ok == true and selfNade.drop.entity == "tacrp_ammo_frag" and selfNade.drop.amount == 3 and selfNade.drop.ammo == "grenade" and selfNade.you.nades.nade_frag == 0)
local selfMed = L.Transfer({
	you = { guns = {}, nades = {}, meds = { med_small = 2 }, ammo = {} },
	them = L.Blank(), from = "you", kind = "med", key = "med_small", amount = 2, to = "drop",
	selfDrop = true,
})
check("own inventory drops a med stack", selfMed.ok == true and selfMed.drop.entity == "pb_med_small" and selfMed.drop.id == 2 and selfMed.drop.amount == 2 and selfMed.you.meds.med_small == 0)
local selfAmmo = L.Transfer({
	you = { guns = { { class = "tacrp_mp5", ammo = "smg1" } }, nades = {}, meds = {}, ammo = { smg1 = 5 } },
	them = L.Blank(), from = "you", kind = "ammo", key = "smg1", amount = 5, to = "drop",
	selfDrop = true,
})
check("ammo still cannot be dropped", selfAmmo.ok == false and selfAmmo.err == "kind")
local function gunSlot(guns, class)
	for i = 1, #(guns or {}) do
		if guns[i].class == class then return guns[i].slot end
	end
	return nil
end
local landed = L.Transfer({
	you = { guns = { { class = "tacrp_pistol", slot = 2 } }, nades = {}, meds = {}, ammo = {} },
	them = { guns = { { class = "tacrp_mp5", slot = 1 } }, nades = {}, meds = {}, ammo = {} },
	from = "them", kind = "gun", key = "tacrp_mp5", amount = 1, to = "you", slot = 0, caps = L.Caps(nil),
})
check("a gun with no slot lands in the first free slot", landed.ok == true and gunSlot(landed.you.guns, "tacrp_mp5") == 1 and gunSlot(landed.you.guns, "tacrp_pistol") == 2)
local droppedSlot = L.Transfer({
	you = {
		guns = { { class = "tacrp_mp5", slot = 1 }, { class = "tacrp_pistol", slot = 2 } },
		nades = {}, meds = {}, ammo = {},
	},
	them = L.Blank(), from = "you", kind = "gun", key = "tacrp_mp5", amount = 1, to = "drop",
})
local droppedView = L.SideView(droppedSlot.you, L.Caps(nil), true)
check("dropping slot 1 keeps the other gun in slot 2", droppedSlot.ok == true and droppedView.guns[1].class == nil and droppedView.guns[1].slot == 1 and droppedView.guns[2].class == "tacrp_pistol" and droppedView.guns[2].slot == 2)
local reslot = L.Transfer({
	you = { guns = { { class = "tacrp_mp5", slot = 1 } }, nades = {}, meds = {}, ammo = {} },
	them = L.Blank(), from = "you", kind = "gun", key = "tacrp_mp5", amount = 1, to = "you", slot = 2,
})
check("re-slot moves a gun into an empty slot", reslot.ok == true and reslot.drop == nil and reslot.you.guns[1].class == "tacrp_mp5" and reslot.you.guns[1].slot == 2)
local swap = L.Transfer({
	you = {
		guns = { { class = "tacrp_mp5", slot = 1 }, { class = "tacrp_pistol", slot = 2 } },
		nades = {}, meds = {}, ammo = {},
	},
	them = L.Blank(), from = "you", kind = "gun", key = "tacrp_mp5", amount = 1, to = "you", slot = 2,
})
check("re-slot swaps the two gun slots", swap.ok == true and swap.drop == nil and gunSlot(swap.you.guns, "tacrp_mp5") == 2 and gunSlot(swap.you.guns, "tacrp_pistol") == 1)
local sameNade = L.Transfer({
	you = { guns = {}, nades = { nade_frag = 1 }, meds = {}, ammo = {} },
	them = L.Blank(), from = "you", kind = "nade", key = "nade_frag", amount = 1, to = "you",
})
check("a non-gun cannot move on the same side", sameNade.ok == false and sameNade.err == "same")
check("a double-click does nothing on your own inventory", L.WantsWhole(true, true) == false and L.WantsWhole(false, true) == true)
local openSelf = L.CanOpenSelf({ phase = "live", alive = true, spectating = false, slotted = true, conscious = true })
check("own inventory opens in live", openSelf == true)
local shutSelf = L.CanOpenSelf({ phase = "buy", alive = true, spectating = false, slotted = true, conscious = true })
check("own inventory opens in buy", shutSelf == true)
local buyLoot, buyLootErr = L.CanOpen({ phase = "buy", alive = true, conscious = true, target = "player", dist = 10, range = 96, los = true })
check("looting stays closed in buy", buyLoot == false and buyLootErr == "phase")
check("buy does not close own inventory", L.ShouldCloseSelf({ phase = "buy", alive = true, spectating = false, slotted = true, conscious = true }) == false)
local deadSelf, deadWhy = L.CanOpenSelf({ phase = "post", alive = false, spectating = false, slotted = true, conscious = false })
check("a dead player cannot open their inventory", deadSelf == false and deadWhy == "alive")
local specSelf, specWhy = L.CanOpenSelf({ phase = "live", alive = true, spectating = true, slotted = true, conscious = true })
check("a spectator cannot open their inventory", specSelf == false and specWhy == "spec")
local slotSelf, slotWhy = L.CanOpenSelf({ phase = "live", alive = true, spectating = false, slotted = false, conscious = true })
check("an unslotted player cannot open their inventory", slotSelf == false and slotWhy == "slot")
local koSelf, koWhy = L.CanOpenSelf({ phase = "live", alive = true, spectating = false, slotted = true, conscious = false })
check("a knocked-out player cannot open their inventory", koSelf == false and koWhy == "down")
local closeSelf, closeWhy = L.ShouldCloseSelf({ phase = "lobby", alive = true, spectating = false, slotted = true, conscious = true })
check("leaving live closes own inventory", closeSelf == true and closeWhy == "phase")

local keys = L.AmmoKeys(
	{ guns = { { class = "tacrp_mp5", ammo = "smg1" }, { class = "tacrp_ex_m1911", ammo = "pistol" } } },
	{ guns = { { class = "tacrp_spr", ammo = "SniperPenetratedRound" } } },
	false
)
check("ammo rows are the guns on either side, sorted", #keys == 3 and keys[1] == "SniperPenetratedRound" and keys[2] == "pistol" and keys[3] == "smg1")
check("grenade ammo is not an ammo row", L.AmmoKeys({ guns = { { class = "x", ammo = "grenade" } } }, nil, false)[1] == nil)
check("infinite ammo hides the row", #L.AmmoKeys({ guns = { { ammo = "pistol" } } }, nil, true) == 0)

local drag = { from = "you", kind = "med", key = "med_pills", amount = 1 }
local slot = { side = "them", kind = "med", key = "med_pills", index = 0 }
check("a matching stack slot accepts the drag", L.Accepts(drag, slot, {
	you = { guns = {}, nades = {}, meds = { med_pills = 1 }, ammo = {} },
	them = L.Blank(), caps = L.Caps(nil),
}) == true)
check("the same side is not a target", L.Accepts(drag, { side = "you", kind = "med", key = "med_pills" }, {
	you = { guns = {}, nades = {}, meds = { med_pills = 1 }, ammo = {} }, them = L.Blank(),
}) == false)
check("a gun accepts another slot on the same side", L.Accepts(
	{ from = "you", kind = "gun", key = "tacrp_mp5", index = 1 },
	{ side = "you", kind = "gun", index = 2 },
	{ you = { guns = { { class = "tacrp_mp5", slot = 1 } }, nades = {}, meds = {}, ammo = {} }, them = L.Blank(), caps = L.Caps(nil) }
) == true)
check("a full slot does not accept the drag", L.Accepts(drag, slot, {
	you = { guns = {}, nades = {}, meds = { med_pills = 1 }, ammo = {} },
	them = { guns = {}, nades = {}, meds = { med_pills = 3 }, ammo = {} },
	caps = L.Caps(nil),
}) == false)

local slotId = L.SlotId({ side = "you", kind = "gun", key = "tacrp_mp5", index = 1 })
check("a second press inside the window is a double-click", L.DoubleClick({ id = slotId, t = 1 }, 1.28, slotId, 0.28) == true)
check("a later press is a new drag", L.DoubleClick({ id = slotId, t = 1 }, 1.29, slotId, 0.28) == false)
local origin = { from = "you", kind = "gun", key = "tacrp_mp5", index = 1 }
check("releasing on the same slot cancels", L.Release(origin, { side = "you", kind = "gun", key = "tacrp_mp5", index = 1 }, true) == "cancel")
check("releasing on another slot moves", L.Release(origin, { side = "them", kind = "gun", key = "", index = 1 }, true) == "move")
check("a gun released outside drops", L.Release(origin, nil, false) == "drop")
check("a gun released inside the card cancels", L.Release(origin, nil, true) == "cancel")
check("a stack released outside cancels", L.Release({ from = "you", kind = "nade", key = "nade_frag", index = 0 }, nil, false) == "cancel")
check("own inventory drops a grenade released outside", L.Release({ from = "you", kind = "nade", key = "nade_frag", index = 0 }, nil, false, true) == "drop")
check("own inventory drops a med released outside", L.Release({ from = "you", kind = "med", key = "med_small", index = 0 }, nil, false, true) == "drop")
check("own inventory cancels ammo released outside", L.Release({ from = "you", kind = "ammo", key = "smg1", index = 0 }, nil, false, true) == "cancel")
check("own inventory moves a gun onto another gun slot", L.Release({ from = "you", kind = "gun", key = "tacrp_mp5", index = 1 }, { side = "you", kind = "gun", key = "", index = 2 }, true, true) == "move")
check("own inventory cancels a gun released on its own slot", L.Release({ from = "you", kind = "gun", key = "tacrp_mp5", index = 1 }, { side = "you", kind = "gun", key = "tacrp_mp5", index = 1 }, true, true) == "cancel")
check("own inventory cancels a stack released on a slot", L.Release({ from = "you", kind = "nade", key = "nade_frag", index = 0 }, { side = "you", kind = "nade", key = "nade_frag", index = 0 }, true, true) == "cancel")

local box = L.PanelBox(1280, 720)
check("the two halves leave a gap", box.right.x == box.left.x + box.left.w + box.gap and box.gap == 16 and box.left.y == box.right.y and box.left.w == box.right.w)
local one = L.SelfBox(1280, 720)
check("own inventory is one centred card", one.left.w == box.left.w and one.left.h == box.left.h and one.left.x == math.floor((1280 - one.left.w) / 2) and one.right.w == 0)

local function pipe()
	local q, i = {}, 1
	local w = {
		bool = function(v) q[#q + 1] = v and true or false end,
		string = function(v) q[#q + 1] = v or "" end,
		uint8 = function(n) q[#q + 1] = n end,
		uint16 = function(n) q[#q + 1] = n end,
	}
	local r = {
		bool = function() i = i + 1 return q[i - 1] end,
		string = function() i = i + 1 return q[i - 1] end,
		uint8 = function() i = i + 1 return q[i - 1] end,
		uint16 = function() i = i + 1 return q[i - 1] end,
	}
	return w, r
end

local view = L.View(you, them, { open = true, giveOnly = false, infinite = false, note = "", caps = L.Caps(nil) })
local w, r = pipe()
L.WriteState(w, view)
local back = L.ReadState(r)
check("state round-trips", back.open == true and back.self == false and back.giveOnly == false and back.infinite == false and back.caps.meds == 3 and back.you.guns[1].class == "tacrp_mp5" and back.you.guns[1].clip1 == 12 and back.you.guns[1].attachments[1].att == "optic_test" and back.you.guns[2].class == nil)
local selfView = L.View(you, L.Blank(), { open = true, self = true, infinite = false, note = "", caps = L.Caps(nil) })
w, r = pipe()
L.WriteState(w, selfView)
local selfBack = L.ReadState(r)
check("a self state round-trips", selfBack.open == true and selfBack.self == true and selfBack.you.guns[1].class == "tacrp_mp5" and selfBack.them.guns[1].class == nil)
local rebuilt = L.InvFromSide(back.you)
check("a side rebuilds into an inventory", rebuilt.guns[1].class == "tacrp_mp5" and rebuilt.nades.nade_frag == 2 and rebuilt.meds.med_pills == 1 and rebuilt.ammo.smg1 == 40)
w, r = pipe()
L.WriteState(w, { open = false, note = "Too far away." })
back = L.ReadState(r)
check("a closed state is just the note", back.open == false and back.note == "Too far away." and back.you == nil)
w, r = pipe()
L.WriteAct(w, { from = "them", kind = "ammo", key = "smg1", amount = 6, to = "you", slot = 0, whole = true })
local act = L.ReadAct(r)
check("an action round-trips", act.from == "them" and act.kind == "ammo" and act.key == "smg1" and act.amount == 6 and act.to == "you" and act.slot == 0 and act.whole == true)

local locks = {}
check("the first looter locks the body", L.Lock(locks, "ply:a", "a") == true)
check("someone else is refused", L.Lock(locks, "ply:a", "b") == false)
check("the same looter can refresh", L.Lock(locks, "ply:a", "a") == true)
L.Unlock(locks, "ply:a", "a")
check("closing releases the lock", locks["ply:a"] == nil)

local pos = L.DropPos({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, 40)
check("a drop sits in front of the looter", pos.x == 0 and pos.y == 40 and pos.z == 8)
local down = L.DropPos({ x = 0, y = 0, z = 0 }, { x = 0, y = 0.6, z = -0.8 }, 40)
check("looking down still drops a full step ahead", math.abs(down.y - 40) < 1e-6 and down.x == 0 and down.z == 8)
local sky = L.DropPos({ x = 5, y = 0, z = 0 }, { x = 0, y = 0, z = 1 }, 40, L.DROP_UP)
check("looking straight up still steps forward at chest height", sky.x == 45 and sky.y == 0 and sky.z == L.DROP_UP)
local realDropType = type
type = function(v)
	if realDropType(v) == "userdata" then return "Vector" end
	return realDropType(v)
end
local function dropVec(x, y, z)
	local u = newproxy(true)
	getmetatable(u).__index = function(_, k)
		if k == "x" then return x end
		if k == "y" then return y end
		if k == "z" then return z end
		return nil
	end
	return u
end
local ahead = L.DropPos(dropVec(10, 20, 30), dropVec(0, 1, 0), 40, L.DROP_UP)
type = realDropType
check("drop position reads gmod vectors", ahead.x == 10 and ahead.y == 60 and ahead.z == 78)

local clientSrc = readAll("gamemodes/ballistics/gamemode/modules/loot/cl_loot.lua")
local serverSrc = readAll("gamemodes/ballistics/gamemode/modules/loot/sv_loot.lua")
check("the loot client compiles", loadfile("gamemodes/ballistics/gamemode/modules/loot/cl_loot.lua") ~= nil)
check("the client does not consume the use button", not clientSrc:find("RemoveKey", 1, true) and not clientSrc:find("PlayerButtonDown", 1, true) and not clientSrc:find("name == \"+use\"", 1, true))
check("the client keeps the keyboard for movement", clientSrc:find("SetKeyboardInputEnabled", 1, true) ~= nil)
check("the server does not hook the use button", not serverSrc:find("PlayerButtonDown", 1, true) and not serverSrc:find("RemoveKey", 1, true))
check("loot has no init hook", not clientSrc:find('hook.Add("Initialize"', 1, true) and not clientSrc:find('hook.Add("InitPostEntity"', 1, true) and not serverSrc:find('hook.Add("Initialize"', 1, true) and not serverSrc:find('hook.Add("InitPostEntity"', 1, true))
check("the inventory key is polled", clientSrc:find("bal_loot_self", 1, true) ~= nil and clientSrc:find("IsKeyDown", 1, true) ~= nil and clientSrc:find("IsGameUIVisible", 1, true) ~= nil)
check("the server opens a self session", serverSrc:find("function L.OpenSelf", 1, true) ~= nil and serverSrc:find("bal_loot_self", 1, true) ~= nil)
check("the drag ghost paints the whole slot above the window", clientSrc:find("PostRenderVGUI", 1, true) ~= nil and clientSrc:find("PaintManual", 1, true) ~= nil and clientSrc:find("balGhost", 1, true) ~= nil and clientSrc:find('hook.Add("HUDPaint", "Ballistics_LootDrag"', 1, true) == nil)
check("the held slot is greyed from the drag source", clientSrc:find("IsDragSource", 1, true) ~= nil and clientSrc:find("PaintOver", 1, true) ~= nil)

-- Server session. Players are tables; the server only calls methods.
local phaseName = "live"
BALLISTICS.Round = { Phase = function() return phaseName end }
local pbMax = 5
local medCalls = {}
PLAYER_BALLISTICS = {
	MedMax = function() return pbMax end,
	MedBag = function(p) return p.pbMed end,
	GiveMed = function(p, id, n)
		medCalls[#medCalls + 1] = { id = id, n = n }
		local have = p.pbMed.counts[id] or 0
		local nextCount = have + n
		if nextCount < 0 then nextCount = 0 end
		if nextCount > pbMax then nextCount = pbMax end
		p.pbMed.counts[id] = nextCount
		return true
	end,
}
local see = true
util.TraceLine = function()
	if see then return { Entity = nil, Fraction = 1, Hit = false } end
	return { Entity = {}, Fraction = 0.4, Hit = true }
end

local function makeWep(class, ammo, clip, att)
	local wep = {
		class = class,
		Primary = { Ammo = ammo or "pistol", ClipSize = clip or 0 },
		Attachments = { [1] = {} },
		clip1 = clip or 0,
	}
	if att then wep.Attachments[1].Installed = att end
	function wep:IsValid() return true end
	function wep:GetClass() return self.class end
	function wep:Clip1() return self.clip1 or 0 end
	function wep:Clip2() return 0 end
	function wep:SetClip1(n) self.clip1 = n end
	function wep:SetClip2() end
	function wep:Attach(slot, name)
		self.Attachments[slot] = self.Attachments[slot] or {}
		self.Attachments[slot].Installed = name
	end
	return wep
end

local function makePly(sid)
	local p = {
		sid = sid,
		pos = { x = 0, y = 0, z = 0 },
		alive = true,
		pbDown = false,
		weapons = {},
		order = {},
		ammo = {},
		pbMed = { counts = { 0, 0, 0, 0 } },
		chats = {},
		obs = 0,
	}
	function p:IsValid() return true end
	function p:IsPlayer() return true end
	function p:SteamID64() return self.sid end
	function p:Alive() return self.alive == true end
	function p:EyePos() return { x = self.pos.x, y = self.pos.y, z = self.pos.z + 64 } end
	function p:GetPos() return { x = self.pos.x, y = self.pos.y, z = self.pos.z } end
	function p:GetForward() return { x = 1, y = 0, z = 0 } end
	function p:EyeAngles() return { p = 0, y = 0, r = 0 } end
	function p:WorldSpaceCenter() return self:EyePos() end
	function p:NearestPoint() return self:EyePos() end
	function p:GetWeapons() return self.order end
	function p:HasWeapon(class) return self.weapons[class] ~= nil end
	function p:GetWeapon(class) return self.weapons[class] end
	function p:Give(class)
		local wep = self.weapons[class]
		if wep then return wep end
		wep = makeWep(class, "pistol", 0, nil)
		self.weapons[class] = wep
		self.order[#self.order + 1] = wep
		return wep
	end
	function p:StripWeapon(class)
		self.weapons[class] = nil
		local kept = {}
		for i = 1, #self.order do
			if self.order[i].class ~= class then kept[#kept + 1] = self.order[i] end
		end
		self.order = kept
	end
	function p:GetObserverMode() return self.obs or 0 end
	function p:GetAmmoCount(ammoType) return self.ammo[ammoType] or 0 end
	function p:SetAmmo(n, ammoType) self.ammo[ammoType] = n end
	function p:ChatPrint(text) self.chats[#self.chats + 1] = text end
	return p
end

local function arm(p, class, spec)
	spec = spec or {}
	local wep = makeWep(class, spec.ammo or "pistol", spec.clip or 0, spec.att)
	p.weapons[class] = wep
	p.order[#p.order + 1] = wep
	return wep
end

local looter = makePly("76561198000000001")
local victim = makePly("76561198000000002")
local other = makePly("76561198000000003")
player.GetAll = function() return { looter, victim, other } end

local droppedEnts = {}
local failCreate = false
local failAfter = nil
local stackPickup = false
ents = ents or {}
function ents.Create(class)
	if failCreate then return nil end
	if failAfter ~= nil then
		if failAfter <= 0 then return nil end
		failAfter = failAfter - 1
	end
	local e = makeWep(class, "pistol", 0, nil)
	e.nw = {}
	function e:SetPos(pos) self.pos = pos end
	function e:SetAngles(ang) self.ang = ang end
	e.touches = 0
	function e:StartTouch(who)
		self.touches = (self.touches or 0) + 1
		self.lastTouch = who
	end
	-- Scripted Spawn puts the ENT touch method back, which drops a wrap made
	-- before Spawn. The drop must arm grace again afterwards.
	function e:Spawn()
		function self:StartTouch(who)
			self.touches = (self.touches or 0) + 1
			self.lastTouch = who
		end
	end
	function e:DropToFloor() self.fell = true end
	function e:Activate() end
	function e:Remove() self.removed = true end
	function e:SetNW2Bool(key, value) self.nw[key] = value end
	if stackPickup then
		function e:SetAmmo(n) self.ammoSet = n end
	end
	droppedEnts[#droppedEnts + 1] = e
	return e
end

dofile("gamemodes/ballistics/gamemode/modules/loot/sv_loot.lua")

local snapHook = hook.GetTable().DoPlayerDeath and hook.GetTable().DoPlayerDeath.Ballistics_LootSnap
check("death snapshot hook returns nothing", snapHook ~= nil and select("#", snapHook(nil)) == 0)

local function wipe(p)
	p.weapons = {}
	p.order = {}
	p.ammo = {}
	p.pbMed = { counts = { 0, 0, 0, 0 } }
	p.chats = {}
	p.alive = true
	p.pbDown = false
	p.obs = 0
	p.pos = { x = 0, y = 0, z = 0 }
	if BALLISTICS.Loadout and BALLISTICS.Loadout.Reset then
		BALLISTICS.Loadout.Reset(p, "tacrp_knife")
	end
end

local function settle()
	phaseName = "live"
	see = true
	pbMax = 5
	failCreate = false
	failAfter = nil
	stackPickup = false
	BALLISTICS.Config.BuyAmmoMags = 3
	BALLISTICS.Config.MedsMax = 3
	BALLISTICS.Config.GrenadesMax = 3
	medCalls = {}
	droppedEnts = {}
	L.Reset()
	wipe(looter)
	wipe(victim)
	wipe(other)
end

local function classes(side)
	local out = {}
	local guns = side and side.guns or {}
	for i = 1, #guns do
		if guns[i].class then out[#out + 1] = guns[i].class end
	end
	return out
end

local function stack(side, kind, key)
	local rows = side and side[kind] or {}
	for i = 1, #rows do
		if rows[i].key == key then return rows[i].count end
	end
	return nil
end

settle()
phaseName = "buy"
local ok, err = L.Open(looter, victim)
check("the server refuses loot during buy", ok == false and err == "phase" and looter.chats[#looter.chats] == "Ballistics: Looting is closed.")
phaseName = "lobby"
ok, err = L.Open(looter, victim)
check("the server refuses loot in the lobby", ok == false and err == "phase")

settle()
phaseName = "post"
ok = L.Open(looter, victim)
check("post round can open", ok == true and L.Last(looter).open == true and L.Last(looter).giveOnly == true)
check("opening does not chat", #looter.chats == 0)

settle()
looter.alive = false
ok, err = L.Open(looter, victim)
check("a dead looter cannot open", ok == false and err == "alive")
settle()
looter.pbDown = true
ok, err = L.Open(looter, victim)
check("an unconscious looter cannot open", ok == false and err == "down")
settle()
ok, err = L.Open(looter, looter)
check("opening yourself finds nothing", ok == false and err == "target" and looter.chats[#looter.chats] == "Ballistics: Nothing to loot.")

settle()
local ownRag = {
	class = "prop_ragdoll",
	bd_owner = looter,
	pos = { x = 0, y = 0, z = 0 },
}
function ownRag:IsValid() return true end
function ownRag:GetClass() return "prop_ragdoll" end
function ownRag:GetPos() return self.pos end
function ownRag:WorldSpaceCenter() return { x = 0, y = 0, z = 64 } end
function ownRag:NearestPoint() return self:WorldSpaceCenter() end
ok, err = L.Open(looter, ownRag)
check("your own ragdoll is refused", ok == false and err == "self")

settle()
see = false
ok, err = L.Open(looter, victim)
check("the server rechecks line of sight", ok == false and err == "los" and looter.chats[#looter.chats] == "Ballistics: No line of sight.")
see = true
victim.pos = { x = 0, y = 0, z = 400 }
ok, err = L.Open(looter, victim)
check("the server rechecks range", ok == false and err == "range")

settle()
arm(victim, "tacrp_knife", { clip = 0 })
arm(victim, "tacrp_mp5", { ammo = "smg1", clip = 12, att = "optic_test" })
victim.pbDown = true
ok = L.Open(looter, victim)
local last = L.Last(looter)
check("an unconscious player is two-way", ok == true and last.giveOnly == false)
check("the knife is not listed", classes(last.them)[1] == "tacrp_mp5" and classes(last.them)[2] == nil)
ok, err = L.Act(looter, { from = "them", kind = "gun", key = "tacrp_mp5", amount = 1, to = "you", slot = 2, whole = false })
last = L.Last(looter)
local taken = looter.weapons.tacrp_mp5
check("taking a gun keeps the mag and the attachment", ok == true and taken ~= nil and taken.clip1 == 12 and taken.Attachments[1].Installed == "optic_test")
check("the gun fills the first free loadout slot", BALLISTICS.Loadout.Guns(looter)[1] == "tacrp_mp5" and victim.weapons.tacrp_mp5 == nil)
check("slot 2 on an empty list still lands", classes(last.you)[1] == "tacrp_mp5")

settle()
arm(looter, "tacrp_mp5", { ammo = "smg1", clip = 3, att = "supp" })
victim.pbDown = true
L.Open(looter, victim)
ok = L.Act(looter, { from = "you", kind = "gun", key = "tacrp_mp5", amount = 1, to = "drop", slot = 0 })
local drop = droppedEnts[#droppedEnts]
check("dropping a gun spawns it in front of the looter", ok == true and drop ~= nil and drop.class == "tacrp_mp5" and drop.BallisticsLootDrop == true and drop.nw.bal_loot_drop == true)
check("the dropped gun keeps its mag and attachment", drop.clip1 == 3 and drop.Attachments[1].Installed == "supp" and drop.pos.x == 40 and drop.pos.z == L.DROP_UP and drop.fell == true)
check("the dropped gun leaves the looter", looter.weapons.tacrp_mp5 == nil)
check("the dropper cannot take the gun back yet", drop.BallisticsDropOwner == looter and drop.BallisticsDropUntil == L.DROP_GRACE and L.PickupBlocked(looter, drop, 0) == true and L.PickupBlocked(looter, drop, L.DROP_GRACE) == false and L.PickupBlocked(victim, drop, 0) == false)
local useLooter, useVictim = hook.Run("PlayerUse", looter, drop), hook.Run("PlayerUse", victim, drop)

check("PlayerUse blocks only the dropper during grace", useLooter == false and useVictim == nil)

settle()
arm(looter, "tacrp_mp5", { clip = 1 })
failCreate = true
L.Open(looter, victim)
ok, err = L.Act(looter, { from = "you", kind = "gun", key = "tacrp_mp5", amount = 1, to = "drop", slot = 0 })
check("a failed drop leaves the gun in hand", ok == false and err == "drop" and looter.weapons.tacrp_mp5 ~= nil and L.Last(looter).note == "Could not drop that.")

settle()
arm(looter, "tacrp_mp5", { ammo = "smg1" })
arm(looter, "tacrp_ex_ak47", { ammo = "ar2" })
arm(victim, "tacrp_spr", { ammo = "SniperPenetratedRound" })
victim.pbDown = true
L.Open(looter, victim)
ok, err = L.Act(looter, { from = "them", kind = "gun", key = "tacrp_spr", amount = 1, to = "you", slot = 0 })
check("two guns is the limit", ok == false and err == "fit" and L.Last(looter).note == "Can't fit any more of this item" and #looter.chats == 0)
check("a refused fit does not move the gun", victim.weapons.tacrp_spr ~= nil and looter.weapons.tacrp_spr == nil)

settle()
arm(looter, "tacrp_mp5")
arm(victim, "tacrp_mp5")
victim.pbDown = true
L.Open(looter, victim)
ok = L.Act(looter, { from = "them", kind = "gun", key = "tacrp_mp5", amount = 1, to = "you", slot = 0 })
check("a duplicate class does not fit", ok == false and looter.weapons.tacrp_mp5 ~= nil and victim.weapons.tacrp_mp5 ~= nil)

settle()
looter.pbMed.counts[1] = 2
victim.pbMed.counts[1] = 2
victim.pbDown = true
L.Open(looter, victim)
ok = L.Act(looter, { from = "them", kind = "med", key = "med_pills", amount = 2, to = "you", slot = 0 })
last = L.Last(looter)
check("meds move through GiveMed up to the cap", ok == true and looter.pbMed.counts[1] == 3 and victim.pbMed.counts[1] == 1 and stack(last.you, "meds", "med_pills") == 3)
check("the med call is a delta", #medCalls == 2)

settle()
pbMax = 2
looter.pbMed.counts[1] = 2
victim.pbMed.counts[1] = 1
victim.pbDown = true
L.Open(looter, victim)
ok = L.Act(looter, { from = "them", kind = "med", key = "med_pills", amount = 1, to = "you", slot = 0 })
check("the Player Ballistics med cap wins when it is lower", ok == false and looter.pbMed.counts[1] == 2 and #medCalls == 0)

settle()
looter.ammo.grenade = 1
victim.ammo.grenade = 2
victim.pbDown = true
L.Open(looter, victim)
ok = L.Act(looter, { from = "them", kind = "nade", key = "nade_frag", amount = 1, to = "you", slot = 0, whole = true })
check("a double-click moves every grenade that fits", ok == true and looter.ammo.grenade == 3 and victim.ammo.grenade == 0)

settle()
looter.ammo.grenade = 3
victim.ammo.grenade = 1
victim.pbDown = true
L.Open(looter, victim)
ok = L.Act(looter, { from = "them", kind = "nade", key = "nade_frag", amount = 1, to = "you", slot = 0 })
check("a full grenade stack is refused without a charge", ok == false and looter.ammo.grenade == 3 and victim.ammo.grenade == 1 and L.Last(looter).note == L.FIT)

settle()
arm(looter, "tacrp_mp5", { ammo = "smg1" })
arm(victim, "tacrp_ex_ak47", { ammo = "ar2" })
looter.ammo.smg1 = 10
victim.ammo.ar2 = 4
victim.pbDown = true
L.Open(looter, victim)
ok = L.Act(looter, { from = "you", kind = "ammo", key = "smg1", amount = 1, to = "them", slot = 0 })
check("one click moves one round", ok == true and looter.ammo.smg1 == 9 and victim.ammo.ar2 == 4 and victim.ammo.smg1 == 1)

settle()
BALLISTICS.Config.BuyAmmoMags = 0
arm(looter, "tacrp_mp5", { ammo = "smg1" })
arm(victim, "tacrp_mp5", { ammo = "smg1" })
looter.ammo.smg1 = 10
victim.ammo.smg1 = 4
victim.pbDown = true
L.Open(looter, victim)
last = L.Last(looter)
check("infinite ammo hides the ammo row", last.infinite == true and #last.you.ammo == 0 and #last.them.ammo == 0)
ok = L.Act(looter, { from = "you", kind = "ammo", key = "smg1", amount = 1, to = "them", slot = 0 })
check("infinite ammo refuses the transfer", ok == false and looter.ammo.smg1 == 10 and victim.ammo.smg1 == 4)

settle()
L.Open(looter, victim)
ok = L.Act(looter, { from = "them", kind = "med", key = "med_pills", amount = 1, to = "you", slot = 0 })
check("an awake player cannot be looted", ok == false and L.Last(looter).open == true and L.Last(looter).giveOnly == true and L.Last(looter).note == "They're awake.")
looter.pbMed.counts[1] = 1
ok = L.Act(looter, { from = "you", kind = "med", key = "med_pills", amount = 1, to = "them", slot = 0 })
check("an awake player can be given to", ok == true and victim.pbMed.counts[1] == 1 and looter.pbMed.counts[1] == 0)

settle()
victim.pbDown = true
L.Open(looter, victim)
victim.pbDown = false
L.Watch()
check("waking switches the window to give only", L.Last(looter).open == true and L.Last(looter).giveOnly == true)
victim.pbDown = true
L.Watch()
check("falling unconscious switches the window back", L.Last(looter).open == true and L.Last(looter).giveOnly == false)

settle()
arm(victim, "tacrp_mp5", { ammo = "smg1", clip = 8, att = "optic_test" })
victim.ammo.smg1 = 15
victim.pbMed.counts[1] = 2
victim.ammo.grenade = 1
victim.pbDown = true
L.Open(looter, victim)
hook.Run("DoPlayerDeath", victim)
victim.alive = false
wipe(victim)
victim.alive = false
hook.Run("PlayerDeath", victim)
last = L.Last(looter)
check("death keeps the window on the snapshot", last.open == true and last.giveOnly == false and classes(last.them)[1] == "tacrp_mp5" and last.them.guns[1].clip1 == 8 and last.them.guns[1].attachments[1].att == "optic_test")
check("the snapshot keeps meds, grenades, and reserve", stack(last.them, "meds", "med_pills") == 2 and stack(last.them, "nades", "nade_frag") == 1 and stack(last.them, "ammo", "smg1") == 15)
ok = L.Act(looter, { from = "them", kind = "gun", key = "tacrp_mp5", amount = 1, to = "you", slot = 0 })
check("taking from a corpse edits the snapshot", ok == true and looter.weapons.tacrp_mp5 ~= nil and classes(L.Last(looter).them)[1] == nil)

settle()
arm(victim, "tacrp_ex_m1911", { ammo = "pistol", clip = 6 })
hook.Run("DoPlayerDeath", victim)
victim.alive = false
victim.weapons = {}
victim.order = {}
local rag = {
	class = "prop_ragdoll",
	bd_owner = victim,
	pos = { x = 0, y = 0, z = 0 },
}
function rag:IsValid() return true end
function rag:GetClass() return "prop_ragdoll" end
function rag:GetPos() return self.pos end
function rag:WorldSpaceCenter() return { x = 0, y = 0, z = 64 } end
function rag:NearestPoint() return self:WorldSpaceCenter() end
ok = L.Open(looter, rag)
check("a death ragdoll opens the snapshot", ok == true and classes(L.Last(looter).them)[1] == "tacrp_ex_m1911" and L.Last(looter).giveOnly == false)

settle()
see = true
L.Open(looter, victim)
see = false
ok, err = L.Act(looter, { from = "you", kind = "med", key = "med_pills", amount = 1, to = "them", slot = 0 })
check("lost line of sight keeps the window and refuses the move", ok == false and err == "los" and L.Last(looter).open == true and L.Last(looter).note == "No line of sight.")
see = true
victim.pos = { x = 0, y = 0, z = 500 }
L.Watch()
check("walking out of range closes the window", L.Last(looter).open == false and looter.chats[#looter.chats] == "Ballistics: Too far away.")

settle()
L.Open(looter, victim)
ok = L.Open(other, victim)
check("one looter at a time", ok == false and L.Last(other).note == "Someone else is looting this body.")
L.Act(looter, { kind = "close" })
check("close is quiet", L.Last(looter).open == false and (L.Last(looter).note or "") == "" and #looter.chats == 0)
ok = L.Open(other, victim)
check("the lock is free after close", ok == true and L.Last(other).open == true)

settle()
L.Open(looter, victim)
hook.Run("PlayerDisconnected", looter)
local gone = L.Last(looter)
check("disconnect closes the session", gone == nil or gone.open == false)
ok = L.Open(other, victim)
check("disconnect frees the body", ok == true)

settle()
arm(victim, "tacrp_mp5", { clip = 2 })
hook.Run("DoPlayerDeath", victim)
victim.alive = false
phaseName = "buy"
hook.Run("Ballistics_PhaseChanged", "live", "buy")
check("leaving live clears the window", L.Last(looter) == nil or L.Last(looter).open ~= true)
phaseName = "live"
local freshRag = {
	class = "prop_ragdoll",
	bd_owner = victim,
	pos = { x = 0, y = 0, z = 0 },
}
function freshRag:IsValid() return true end
function freshRag:GetClass() return "prop_ragdoll" end
function freshRag:GetPos() return self.pos end
function freshRag:WorldSpaceCenter() return { x = 0, y = 0, z = 64 } end
function freshRag:NearestPoint() return self:WorldSpaceCenter() end
ok = L.Open(looter, freshRag)
check("a new round does not keep the old snapshot", ok == true and classes(L.Last(looter).them)[1] == nil)

local GOOD = TEAM_GOOD or 1
local function seat(p, slot)
	return BALLISTICS.Slots.Take(p, GOOD, slot or 1)
end
local function liveDrops()
	local list = {}
	for i = 1, #droppedEnts do
		if not droppedEnts[i].removed then list[#list + 1] = droppedEnts[i] end
	end
	return list
end

settle()
ok, err = L.OpenSelf(looter)
check("an unslotted player cannot open their own inventory", ok == false and err == "slot")
seat(looter)
phaseName = "buy"
ok, err = L.OpenSelf(looter)
check("own inventory opens during buy", ok == true and L.Last(looter).open == true and L.Last(looter).self == true)
phaseName = "post"
ok = L.OpenSelf(looter)
check("own inventory opens after the round", ok == true and L.Last(looter).open == true and L.Last(looter).self == true and L.Last(looter).giveOnly == false)
see = false
looter.pos = { x = 0, y = 0, z = 900 }
ok = L.OpenSelf(looter)
check("own inventory ignores range and line of sight", ok == true and L.Last(looter).self == true)

settle()
seat(looter)
looter.alive = false
ok, err = L.OpenSelf(looter)
check("a dead player cannot open their own inventory", ok == false and err == "alive")
settle()
seat(looter)
looter.pbDown = true
ok, err = L.OpenSelf(looter)
check("a knocked-out player cannot open their own inventory", ok == false and err == "down")
settle()
seat(looter)
looter.obs = 4
ok, err = L.OpenSelf(looter)
check("a spectator cannot open their own inventory", ok == false and err == "spec")

settle()
seat(looter)
arm(looter, "tacrp_mp5", { ammo = "smg1", clip = 3, att = "supp" })
L.Open(looter, victim)
L.OpenSelf(looter)
check("opening your inventory drops the body lock", L.Last(looter).self == true)
ok = L.Open(other, victim)
check("someone else can loot that body", ok == true)
L.Act(other, { kind = "close" })
ok = L.Act(looter, { from = "you", kind = "gun", key = "tacrp_mp5", amount = 1, to = "drop", slot = 0 })
local selfGun = liveDrops()[1]
check("dropping your gun keeps the mag and the attachment", ok == true and selfGun ~= nil and selfGun.class == "tacrp_mp5" and selfGun.clip1 == 3 and selfGun.Attachments[1].Installed == "supp" and selfGun.BallisticsLootDrop == true and selfGun.pos.x == 40 and selfGun.pos.z == L.DROP_UP and selfGun.fell == true and selfGun.BallisticsDropOwner == looter and selfGun.BallisticsDropUntil == L.DROP_GRACE)
check("the dropped gun leaves your inventory", looter.weapons.tacrp_mp5 == nil and classes(L.Last(looter).you)[1] == nil)

settle()
seat(looter)
looter.ammo.grenade = 3
L.OpenSelf(looter)
ok = L.Act(looter, { from = "you", kind = "nade", key = "nade_frag", amount = 1, to = "drop", slot = 0, whole = true })
local nades = liveDrops()
check("a whole-stack flag still drops one grenade", ok == true and looter.ammo.grenade == 2 and #nades == 1 and nades[1].class == "tacrp_ammo_frag" and nades[1].BallisticsLootDrop == true and nades[1].nw.bal_loot_drop == true)
ok = L.Act(looter, { from = "you", kind = "nade", key = "nade_frag", amount = 2, to = "drop", slot = 0 })
nades = liveDrops()
check("each grenade is its own pickup", ok == true and looter.ammo.grenade == 0 and #nades == 3 and nades[3].class == "tacrp_ammo_frag" and nades[3].pos.y == 8 and nades[3].pos.z == L.DROP_UP and nades[3].fell == true and nades[3].BallisticsDropOwner == looter and nades[3].BallisticsLootDrop == true)

settle()
seat(looter)
stackPickup = true
looter.ammo.grenade = 3
L.OpenSelf(looter)
ok = L.Act(looter, { from = "you", kind = "nade", key = "nade_frag", amount = 3, to = "drop", slot = 0 })
nades = liveDrops()
check("a grenade entity that stores a count takes the stack", ok == true and looter.ammo.grenade == 0 and #nades == 1 and nades[1].ammoSet == 3)

settle()
seat(looter)
looter.ammo.grenade = 2
failAfter = 1
L.OpenSelf(looter)
ok, err = L.Act(looter, { from = "you", kind = "nade", key = "nade_frag", amount = 2, to = "drop", slot = 0 })
check("a failed grenade drop leaves them in hand", ok == false and err == "drop" and looter.ammo.grenade == 2 and #liveDrops() == 0)

settle()
seat(looter)
looter.pbMed.counts[2] = 2
stackPickup = true
L.OpenSelf(looter)
medCalls = {}
ok = L.Act(looter, { from = "you", kind = "med", key = "med_small", amount = 2, to = "drop", slot = 0 })
local meds = liveDrops()
check("each med is its own pickup", ok == true and #meds == 2 and meds[1].class == "pb_med_small" and meds[2].class == "pb_med_small" and meds[1].BallisticsLootDrop == true and meds[2].pos.y == 8 and meds[2].pos.z == L.DROP_UP and meds[1].fell == true and meds[1].BallisticsDropOwner == looter)
check("meds leave through GiveMed", looter.pbMed.counts[2] == 0 and #medCalls == 1 and medCalls[1].id == 2 and medCalls[1].n == -2)

settle()
seat(looter)
arm(looter, "tacrp_mp5", { ammo = "smg1" })
looter.ammo.smg1 = 10
L.OpenSelf(looter)
ok, err = L.Act(looter, { from = "you", kind = "ammo", key = "smg1", amount = 4, to = "drop", slot = 0 })
check("ammo cannot be dropped from your inventory", ok == false and err == "ammo" and looter.ammo.smg1 == 10 and L.Last(looter).note == "Ammo can't be dropped." and #liveDrops() == 0)
ok, err = L.Act(looter, { from = "you", kind = "gun", key = "tacrp_mp5", amount = 1, to = "them", slot = 0 })
check("own inventory does not move onto another side", ok == false and err == "side" and looter.weapons.tacrp_mp5 ~= nil)

settle()
seat(looter)
L.OpenSelf(looter)
looter.pbDown = true
L.Watch()
check("falling unconscious closes your inventory", L.Last(looter).open == false)
settle()
seat(looter)
L.OpenSelf(looter)
BALLISTICS.Slots.Leave(looter)
L.Watch()
check("leaving the slot closes your inventory", L.Last(looter).open == false)
settle()
seat(looter)
L.OpenSelf(looter)
looter.alive = false
hook.Run("PlayerDeath", looter)
check("dying closes your inventory", L.Last(looter).open ~= true)

-- Singleplayer: KeyDown(IN_USE) is false client-side, the bound key still counts.
check("use counts from the raw key when the usercmd has none", L.UseDown(false, true) == true)
check("use counts from the usercmd", L.UseDown(true, false) == true)
check("no use when neither", L.UseDown(false, false) == false)
-- Vectors are userdata in GMod: distance and moved must read them.
local function uvec(x, y, z)
	local u = newproxy(true)
	getmetatable(u).__index = function(_, k) return ({ x = x, y = y, z = z })[k] end
	return u
end
-- Mirror GMod: type() of a Vector is "Vector", not "userdata".
local realType = type
type = function(v) if realType(v) == "userdata" then return "Vector" end return realType(v) end
check("distance reads userdata vectors", math.abs(L.Dist(uvec(0, 0, 0), uvec(30, 40, 0)) - 50) < 1e-6)
check("a still body has not moved", L.Moved({ x = 10, y = 20, z = 30 }, uvec(10, 20, 30), 24) == false)
type = realType
local cat = {
	Get = function(k)
		if k == "nade_frag" then return { key = k, entity = "tacrp_ammo_frag" } end
		if k == "med_small" then return { key = k, entity = "pb_med_small" } end
		return nil
	end,
}
check("gun slot icon by class", L.IconItem({ kind = "gun", class = "tacrp_mp5" }, cat).class == "tacrp_mp5")
check("gun slot icon by key when class is absent", L.IconItem({ kind = "gun", key = "tacrp_mr96" }, cat).class == "tacrp_mr96")
check("grenade slot icon from catalog", L.IconItem({ kind = "nade", key = "nade_frag" }, cat).entity == "tacrp_ammo_frag")
check("empty and ammo slots have no icon", L.IconItem({ kind = "gun", empty = true }, cat) == nil and L.IconItem({ kind = "ammo", key = "pistol" }, cat) == nil)
check("an empty grenade slot still has an icon", L.IconItem({ kind = "nade", key = "nade_frag", empty = true, count = 0 }, cat).entity == "tacrp_ammo_frag")
check("an empty med slot still has an icon", L.IconItem({ kind = "med", key = "med_small", empty = true, count = 0 }, cat).entity == "pb_med_small")
check("the held slot is the drag source", L.IsDragSource({ side = "you", kind = "gun", key = "tacrp_mr96", index = 1 }, { from = "you", kind = "gun", key = "tacrp_mr96", index = 1 }) == true)
check("another slot is not the drag source", L.IsDragSource({ side = "you", kind = "gun", key = "tacrp_mr96", index = 2, empty = false }, { from = "you", kind = "gun", key = "tacrp_mr96", index = 1 }) == false and L.IsDragSource({ side = "you", kind = "gun", key = "tacrp_mr96", index = 1, empty = true }, { from = "you", kind = "gun", key = "tacrp_mr96", index = 1 }) == false)
local graceWep = { BallisticsDropOwner = looter, BallisticsDropUntil = 1.5 }
check("pickup grace blocks only the dropper", L.PickupBlocked(looter, graceWep, 0) == true and L.PickupBlocked(looter, graceWep, 1.5) == false and L.PickupBlocked(victim, graceWep, 0) == false and L.PickupBlocked(looter, {}, 0) == false)

-- Client: the 5 key toggles your inventory and stays quiet while blocked.
CLIENT = true
dofile("gamemodes/ballistics/gamemode/modules/fkeys/sh_fkeys.lua")
local phaseNow, aliveNow, teamNow, obsNow, downNow = "live", true, 1, 0, false
local keysDown = {}
local menuUp, consoleUp = false, false
local sent = {}
local clockRt = 0
function RealTime() return clockRt end
function IsValid(ent) return ent ~= nil and ent ~= false end
input = {
	IsKeyDown = function(code) return keysDown[code] == true end,
	IsMouseDown = function() return false end,
	LookupBinding = function() return "e" end,
	GetKeyCode = function() return 0 end,
}
gui = {
	IsGameUIVisible = function() return menuUp end,
	IsConsoleVisible = function() return consoleUp end,
	HideGameUI = function() end,
}
BALLISTICS.Keys = BALLISTICS.Keys or {}
function BALLISTICS.Keys.InventoryKey() return 6 end
function LocalPlayer()
	return {
		IsValid = function() return true end,
		Alive = function() return aliveNow end,
		Team = function() return teamNow end,
		pbDown = downNow,
		GetObserverMode = function() return obsNow end,
		GetNW2String = function(_, key)
			if key == "bal_phase" then return phaseNow end
			return ""
		end,
		KeyDown = function() return false end,
	}
end
function net.Start(name) sent[#sent + 1] = name end
function net.SendToServer() end
dofile("gamemodes/ballistics/gamemode/modules/loot/cl_loot.lua")

local function releaseKey()
	keysDown[6] = false
	hook.Run("Think")
end
local function tap(at)
	clockRt = at
	keysDown[6] = true
	hook.Run("Think")
	local n = #sent
	releaseKey()
	return n
end
local function resetGate()
	phaseNow, aliveNow, teamNow, obsNow, downNow = "live", true, 1, 0, false
	menuUp, consoleUp = false
	sent = {}
	releaseKey()
end

resetGate()
tap(1)
check("5 asks the server to open your inventory", #sent == 1 and sent[1] == "bal_loot_self")
tap(1.1)
check("a second tap inside the debounce does nothing", #sent == 1)
tap(2)
check("a later tap asks again", #sent == 2 and sent[2] == "bal_loot_self")

resetGate()
L.ApplyClientState({
	open = true, self = true, note = "", giveOnly = false, infinite = false,
	caps = { meds = 3, nades = 3, guns = 2 },
	you = { guns = {}, nades = {}, meds = {}, ammo = {} },
	them = { guns = {}, nades = {}, meds = {}, ammo = {} },
})
tap(5)
check("5 again closes your inventory", #sent == 1 and sent[1] == "bal_loot_act")

resetGate()
L.ApplyClientState({ open = true, self = true, note = "", you = {}, them = {} })
sent = {}
local esc = hook.Run("OnPauseMenuShow")
check("escape sends the close", esc == false and #sent == 1 and sent[1] == "bal_loot_act")

resetGate()
phaseNow = "buy"
tap(10)
check("5 opens during buy", #sent == 1 and sent[1] == "bal_loot_self")
resetGate()
phaseNow = "post"
tap(11)
check("5 opens during the post round", #sent == 1 and sent[1] == "bal_loot_self")
resetGate()
aliveNow = false
tap(12)
check("5 does nothing while dead", #sent == 0)
resetGate()
obsNow = 4
tap(13)
check("5 does nothing while spectating", #sent == 0)
resetGate()
teamNow = TEAM_SPEC or 1002
tap(14)
check("5 does nothing while unslotted", #sent == 0)
resetGate()
downNow = true
tap(15)
check("5 does nothing while knocked out", #sent == 0)
resetGate()
hook.Run("StartChat")
tap(16)
hook.Run("FinishChat")
check("5 does nothing while typing", #sent == 0)
resetGate()
menuUp = true
tap(17)
check("5 does nothing in a menu", #sent == 0)
resetGate()
consoleUp = true
tap(18)
check("5 does nothing in the console", #sent == 0)
if failed then os.exit(1) end
