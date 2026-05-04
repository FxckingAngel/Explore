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
	local target = findByPath(payload.TargetPath)
	if type(payload) ~= "table" then return end
	if payload.Type == "ScriptViewerSync" then
		local source = payload.Source
		if type(source) ~= "string" then return end
		if not target or not target:IsA("LuaSourceContainer") then return end

		-- WARNING: Most live games block Source edits on server for security.
		local ok, err = pcall(function()
			target.Source = source
		end)
		if not ok then
			warn("[DexBridge] Failed to apply source from", player, err)
		end
	elseif payload.Type == "ExplorerLiveEdit" and payload.Action == "Delete" then
		if target then
			pcall(function()
				target:Destroy()
			end)
		end
	elseif payload.Type == "ExplorerLiveEdit" and type(payload.Action) == "string" and payload.Action:sub(1,16) == "PropertyChanged:" then
		-- Hook point for server-side property sync if you want strict mirroring.
		-- Keeping as a log by default to avoid unsafe arbitrary property writes.
		warn("[DexBridge] Property change from", player, payload.Action, payload.TargetPath)
	elseif payload.Type == "PropertiesLiveEdit" then
		warn("[DexBridge] Properties edit from", player, payload.Action, payload.TargetPath)
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
