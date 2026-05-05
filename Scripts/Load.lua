-- AutoDeflect Loader — always fetches latest, bypasses GitHub CDN cache
-- Usage: loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/Load.lua"))()

-- Kill any old instance first
if _G._AutoCircleCleanup then pcall(_G._AutoCircleCleanup) _G._AutoCircleCleanup = nil end
if _G._AutoDeflectCleanup then pcall(_G._AutoDeflectCleanup) _G._AutoDeflectCleanup = nil end

-- Bust cache with millisecond timestamp
local t = math.floor(tick() * 1000)
local url = "https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/AutoDeflect.lua?t=" .. t

local ok, src = pcall(game.HttpGet, game, url)
if not ok or #src < 100 then
    error("[AutoDeflect] Failed to fetch: " .. tostring(src))
end

local fn, err = loadstring(src)
if not fn then error("[AutoDeflect] Compile error: " .. tostring(err)) end
fn()
