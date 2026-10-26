-- Minimal GMod stubs so luajit can load gamemode files.

if _G.GMOD_STUB_LOADED then return end
_G.GMOD_STUB_LOADED = true

SERVER = true
CLIENT = false

function include(path) end
function AddCSLuaFile(path) end

function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function istable(v) return type(v) == "table" end
function isbool(v) return type(v) == "boolean" end
function isfunction(v) return type(v) == "function" end

function Vector(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end

function Angle(p, y, r)
	return { p = p or 0, y = y or 0, r = r or 0 }
end

function Color(r, g, b, a)
	return { r = r, g = g, b = b, a = a or 255 }
end

function CurTime() return 0 end
function RealTime() return 0 end
function FrameTime() return 0.1 end
function SysTime() return os.clock() end

hook = {}
local hooks = {}
function hook.Add(event, id, fn)
	hooks[event] = hooks[event] or {}
	hooks[event][id] = fn
end
function hook.Remove(event, id)
	if hooks[event] then hooks[event][id] = nil end
end
function hook.Run(event, ...)
	local list = hooks[event]
	if not list then return end
	for _, fn in pairs(list) do
		local r = fn(...)
		if r ~= nil then return r end
	end
end
function hook.GetTable()
	return hooks
end
hook.Call = hook.Run

timer = {}
function timer.Create() end
function timer.Simple() end
function timer.Remove() end
function timer.Exists() return false end

net = {}
function net.Start() end
function net.Send() end
function net.Broadcast() end
function net.Receive() end
function net.WriteTable() end
function net.ReadTable() return {} end
function net.WriteString() end
function net.ReadString() return "" end
function net.WriteUInt() end
function net.ReadUInt() return 0 end
function net.WriteInt() end
function net.ReadInt() return 0 end
function net.WriteBool() end
function net.ReadBool() return false end
function net.WriteEntity() end
function net.ReadEntity() return nil end
function net.WriteFloat() end
function net.ReadFloat() return 0 end

util = {}
function util.AddNetworkString() end
function util.TableToJSON() return "{}" end
function util.JSONToTable() return {} end

file = {}
function file.Find() return {}, {} end
function file.Exists() return false end
function file.Read() return nil end
function file.Write() end
function file.CreateDir() end

player = {}
function player.GetAll() return {} end
function player.GetHumans() return {} end
function player.GetBots() return {} end
function player.GetCount() return 0 end

team = {}
function team.SetUp() end
function team.GetName(id) return tostring(id) end
function team.GetColor() return Color(255, 255, 255) end

resource = {}
function resource.AddWorkshop() end

game = {}
function game.GetMap() return "gm_construct" end
function game.SinglePlayer() return true end

engine = {}
function engine.ActiveGamemode() return "ballistics" end

GM = GM or {}
GM.FolderName = "ballistics"
GM.Folder = "gamemodes/ballistics"
GM.Name = "Ballistics Game Mode"

function MsgN(...) print(...) end
function Msg(...) io.write(...) end
function ErrorNoHalt(...) print(...) end

function table.Copy(t)
	if type(t) ~= "table" then return t end
	local n = {}
	for k, v in pairs(t) do
		n[k] = type(v) == "table" and table.Copy(v) or v
	end
	return n
end

function table.Count(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

function string.StartWith(s, prefix)
	return s:sub(1, #prefix) == prefix
end

function string.EndsWith(s, suffix)
	return suffix == "" or s:sub(-#suffix) == suffix
end
