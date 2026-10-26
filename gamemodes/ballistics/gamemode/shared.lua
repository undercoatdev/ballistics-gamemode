-- Ballistics Game Mode: shared entry point. Loader + includes only.
GM.Name = "Ballistics Game Mode"
GM.Author = "undercoatdev"
GM.Email = ""
GM.Website = "https://github.com/undercoatdev/ballistics-gamemode"
DeriveGamemode("base")

BALLISTICS = BALLISTICS or {}

if SERVER then
	AddCSLuaFile("core/sh_loader.lua")
end
include("core/sh_loader.lua")
