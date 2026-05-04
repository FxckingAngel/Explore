-- Server-side example bridge handler for ScriptViewer live editing.
-- Place this in ServerScriptService and ensure a RemoteEvent named "DexBridge"
-- (or "ScriptBridge" / "LocalGUIEnabler") exists in ReplicatedStorage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local bridge = ReplicatedStorage:FindFirstChild("DexBridge")
if not bridge then
	bridge = Instance.new("RemoteEvent")
	bridge.Name = "DexBridge"
	bridge.Parent = ReplicatedStorage
end

local listFn = ReplicatedStorage:FindFirstChild("DexBridgeList")
if not listFn then
	listFn = Instance.new("RemoteFunction")
	listFn.Name = "DexBridgeList"
	listFn.Parent = ReplicatedStorage
end

local function findByPath(path)
	if type(path) ~= "string" or path == "" then return nil end
	local cur = game
	for part in path:gmatch("[^%.]+") do
		cur = cur:FindFirstChild(part)
		if not cur then return nil end
	end
	return cur
end

bridge.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" or payload.Type ~= "ScriptViewerSync" then return end
	local source = payload.Source
	if type(source) ~= "string" then return end

	local target = findByPath(payload.TargetPath)
	if not target or not target:IsA("LuaSourceContainer") then return end

	-- WARNING: Most live games block Source edits on server for security.
	-- This works only in Studio/plugins/authorized environments.
	local ok, err = pcall(function()
		target.Source = source
	end)
	if not ok then
		warn("[DexBridge] Failed to apply source from", player, err)
	end
end)

listFn.OnServerInvoke = function()
	local sss = game:FindFirstChild("ServerScriptService")
	if not sss then return {} end
	local out = {}
	for _, obj in ipairs(sss:GetDescendants()) do
		if obj:IsA("LuaSourceContainer") then
			out[#out+1] = {Name = obj.Name, Path = obj:GetFullName(), ClassName = obj.ClassName}
		end
	end
	return out
end
