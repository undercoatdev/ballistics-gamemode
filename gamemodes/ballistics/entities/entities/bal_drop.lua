-- A grenade or med stack dropped from a loot or inventory window.
-- Picked up only with E (no touch pickup). The real TacRP / Player Ballistics
-- pickup entities auto-collect on touch and PB's med Think errors at runtime,
-- so drops use this entity instead. The item is granted next tick, never
-- inside the engine's Use dispatch.
AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Dropped item"
ENT.Spawnable = false
ENT.AdminOnly = false

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "ItemKey")
	self:NetworkVar("Int", 0, "Count")
end

if SERVER then
	function ENT:Initialize()
		local model = self.BalModel
		if type(model) ~= "string" or model == "" then model = "models/items/healthkit.mdl" end
		self:SetModel(model)
		if self.BalMedId and PLAYER_BALLISTICS and type(PLAYER_BALLISTICS.ApplyMedLook) == "function" then
			pcall(PLAYER_BALLISTICS.ApplyMedLook, self, self.BalMedId)
		end
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_VPHYSICS)
		self:SetSolid(SOLID_VPHYSICS)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		self:SetUseType(SIMPLE_USE)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:Wake() end
	end

	function ENT:Use(activator)
		if self.balTaking then return end
		if not IsValid(activator) or not activator:IsPlayer() then return end
		self.balTaking = true
		local ent = self
		timer.Simple(0, function()
			if not IsValid(ent) then return end
			ent.balTaking = false
			if not IsValid(activator) then return end
			local L = BALLISTICS and BALLISTICS.Loot
			if not L or type(L.TakeDrop) ~= "function" then return end
			local ok, left = pcall(L.TakeDrop, activator, ent:GetItemKey(), ent:GetCount())
			left = ok and tonumber(left) or nil
			if left == nil then return end
			if left <= 0 then
				ent:Remove()
			else
				ent:SetCount(left)
			end
		end)
	end
end

if CLIENT then
	function ENT:Draw()
		self:DrawModel()
	end
end
