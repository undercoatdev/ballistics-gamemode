if not SERVER then return end
local P = BALLISTICS.PushForce

hook.Add("EntityTakeDamage", "Ballistics_BulletPush", function(target, dmginfo)
	if not dmginfo then return end
	local isBullet = dmginfo.IsBulletDamage and dmginfo:IsBulletDamage() or false
	local m = P.ScaleFor(dmginfo:GetDamageType(), isBullet)
	if not m then return end
	local f = dmginfo:GetDamageForce()
	if f then dmginfo:SetDamageForce(f * m) end
end)
