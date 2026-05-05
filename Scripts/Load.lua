-- AutoDeflect Bootstrap — always gets latest version
-- GitHub API bypasses CDN cache
local function getLatest()
    local apiUrl = "https://api.github.com/repos/FxckingAngel/Explore/contents/Scripts/AutoDeflect.lua"
    local ok, result = pcall(function()
        local data = game:HttpGet(apiUrl)
        local json = game:GetService("HttpService"):JSONDecode(data)
        -- Content is base64 encoded
        local content = json.content:gsub("\n", "")
        return game:GetService("HttpService"):JSONDecode('{"s":"' .. content .. '"}')
    end)
    -- Fallback to raw URL if API fails
    if not ok then
        return game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/AutoDeflect.lua?bust=" .. os.time())
    end
end

-- Simpler: just use the no-cache header trick via Roblox HttpService
local HttpService = game:GetService("HttpService")
local url = "https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/AutoDeflect.lua"

-- Add timestamp to URL to bypass cache
local src = game:HttpGet(url .. "?t=" .. tostring(os.time()))
local fn, err = loadstring(src)
if fn then fn()
else error("[AutoDeflect] Load failed: " .. tostring(err)) end
