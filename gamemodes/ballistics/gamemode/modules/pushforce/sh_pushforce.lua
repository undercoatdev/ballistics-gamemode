-- Bullet push force. TacRP has no force convar: hitscan bullets use Force = 1,
-- so the engine pushes by damage x phys_pushscale, and physical bullets set
-- the damage force directly. Either way it lands in the bullet dmginfo, so we
-- scale that force (EntityTakeDamage) by Config.BulletPushForce (default 0.5).
-- Players included: the killing shot's force is what launches the corpse.
BALLISTICS = BALLISTICS or {}
BALLISTICS.PushForce = BALLISTICS.PushForce or {}
local P = BALLISTICS.PushForce

P.DMG_BULLET = 2

function P.Mult()
	local cfg = BALLISTICS.Config or {}
	local m = tonumber(cfg.BulletPushForce)
	if not m then return 0.5 end
	if m < 0 then m = 0 end
	return m
end

-- dmgType: number bitmask. Returns the multiplier to apply, or nil to skip.
function P.ScaleFor(dmgType, isBullet)
	local bullet = isBullet == true or (type(dmgType) == "number" and bit and bit.band(dmgType, P.DMG_BULLET) ~= 0)
	if not bullet then return nil end
	local m = P.Mult()
	if m == 1 then return nil end
	return m
end
