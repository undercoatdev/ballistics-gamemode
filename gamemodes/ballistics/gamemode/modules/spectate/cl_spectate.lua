-- Helmet cam while dead in a round: a camera up and right of the watched
-- teammate's head, slightly wide, smoothed. Player Ballistics' own death /
-- down camera is skipped while we follow someone (its hook is wrapped at
-- runtime, its file is not touched). Name shown bottom middle.

if not CLIENT then return end

BALLISTICS = BALLISTICS or {}
BALLISTICS.Spectate = BALLISTICS.Spectate or {}
local S = BALLISTICS.Spectate

local smoothPos, smoothAng, lastTarget

local function phase()
	local ply = LocalPlayer and LocalPlayer()
	if not IsValid(ply) or not ply.GetNW2String then return nil end
	local p = ply:GetNW2String("bal_phase", "")
	return p ~= "" and p or nil
end

function S.Target()
	local ply = LocalPlayer and LocalPlayer()
	if not IsValid(ply) or ply:Alive() then return nil end
	if not S.PhaseFollows(phase()) then return nil end
	local t = ply.GetNW2Entity and ply:GetNW2Entity("bal_spec") or nil
	if not IsValid(t) or not t:IsPlayer() or not t:Alive() then return nil end
	return t
end

local function headPos(t)
	local bone = t.LookupBone and t:LookupBone("ValveBiped.Bip01_Head1")
	if bone then
		local m = t:GetBoneMatrix(bone)
		if m then return m:GetTranslation() end
	end
	return t:EyePos()
end

local wrapped = setmetatable({}, { __mode = "k" })
local function wrapOthers()
	local list = hook.GetTable().CalcView
	if type(list) ~= "table" then return end
	for name, fn in pairs(list) do
		if name ~= "Ballistics_Spectate" and type(fn) == "function" and not wrapped[fn]
			and type(name) == "string" and name:sub(1, 17) == "PlayerBallistics_" then
			local orig = fn
			local guard = function(...)
				if S.Target() then return end
				return orig(...)
			end
			wrapped[guard] = true
			hook.Add("CalcView", name, guard)
		end
	end
end

hook.Add("Think", "Ballistics_SpectateWrap", wrapOthers)

hook.Add("CalcView", "Ballistics_Spectate", function(_, _, _, fov)
	local t = S.Target()
	if not t then
		smoothPos, smoothAng, lastTarget = nil, nil, nil
		return
	end
	local ang = t:EyeAngles()
	local pos = headPos(t) + ang:Up() * S.CAM_UP + ang:Right() * S.CAM_RIGHT + ang:Forward() * S.CAM_FORWARD
	if t ~= lastTarget or not smoothPos then
		smoothPos, smoothAng, lastTarget = pos, ang, t
	else
		local k = S.Blend(FrameTime())
		smoothPos = LerpVector(k, smoothPos, pos)
		smoothAng = LerpAngle(k, smoothAng, ang)
	end
	return { origin = smoothPos, angles = smoothAng, fov = (fov or 90) + S.FOV_ADD, drawviewer = false }
end)

-- Hide the watched player's head so the camera never sees inside it.
hook.Add("PrePlayerDraw", "Ballistics_Spectate", function(ply)
	local t = S.Target()
	if t and ply == t then
		local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
		if bone then ply:ManipulateBoneScale(bone, Vector(0.01, 0.01, 0.01)) end
		ply.balHeadHidden = true
	elseif ply.balHeadHidden then
		local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
		if bone then ply:ManipulateBoneScale(bone, Vector(1, 1, 1)) end
		ply.balHeadHidden = nil
	end
end)

-- Name: bottom middle, above the money bar.
hook.Add("HUDPaint", "Ballistics_SpectateName", function()
	local t = S.Target()
	if not t then return end
	local text = S.Label(t:Nick())
	if not text then return end
	local x, y = ScrW() / 2, ScrH() - 110
	draw.SimpleTextOutlined(text, "DermaLarge", x, y, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, 200))
	draw.SimpleTextOutlined("Left click next   Right click previous", "DermaDefault", x, y + 22, Color(220, 220, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
end)
