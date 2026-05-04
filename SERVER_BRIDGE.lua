--[[
	Dex Server Bridge — FxckingAngel/Explore
	
	Place this Script in ServerScriptService.
	It creates the RemoteEvent/RemoteFunction instances the client loader expects,
	and handles all client -> server messages with detailed prints so you can
	see exactly what's happening on the server side.
	
	Bridge objects created in ReplicatedStorage:
	  DexBridge      — RemoteEvent  (fire-and-forget both directions)
	  DexBridgeList  — RemoteFunction (client requests server script list)
	  DexBridgeFn    — RemoteFunction (client invokes server actions)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local BRIDGE_NAME      = "DexBridge"
local BRIDGE_LIST_NAME = "DexBridgeList"
local BRIDGE_FN_NAME   = "DexBridgeFn"

-- ============================================================
-- LOGGING
-- ============================================================

local function log(tag, msg)
	print(("[DexServer][%s] %s"):format(tag, tostring(msg)))
end

local function warn_tag(tag, msg)
	warn(("[DexServer][%s] %s"):format(tag, tostring(msg)))
end

-- ============================================================
-- CREATE REMOTES
-- ============================================================

log("Init", "=== Dex Server Bridge starting ===")

local function getOrCreate(class, name, parent)
	local existing = parent:FindFirstChild(name)
	if existing then
		log("Init", name .. " already exists, reusing")
		return existing
	end
	local inst = Instance.new(class)
	inst.Name = name
	inst.Parent = parent
	log("Init", "Created " .. class .. " '" .. name .. "' in " .. parent.Name)
	return inst
end

local bridge     = getOrCreate("RemoteEvent",    BRIDGE_NAME,      ReplicatedStorage)
local bridgeList = getOrCreate("RemoteFunction", BRIDGE_LIST_NAME, ReplicatedStorage)
local bridgeFn   = getOrCreate("RemoteFunction", BRIDGE_FN_NAME,   ReplicatedStorage)

log("Init", "All remotes ready")

-- ============================================================
-- HELPERS
-- ============================================================

local function getPlayerName(player)
	return player and player.Name or "unknown"
end

-- Walk a dot-separated path from game root
local function findByPath(path)
	if type(path) ~= "string" or path == "" then return nil end
	local cur = game
	for part in path:gmatch("[^%.]+") do
		if cur == game and part == "game" then continue end
		cur = cur:FindFirstChild(part)
		if not cur then
			warn_tag("Path", "Could not find child '" .. part .. "' in path: " .. path)
			return nil
		end
	end
	return cur
end

-- Send a message back to a specific client
local function sendToClient(player, payload)
	log("Bridge", "← Sending to " .. getPlayerName(player) .. ": type=" .. tostring(payload.Type))
	local ok, err = pcall(bridge.FireClient, bridge, player, payload)
	if not ok then
		warn_tag("Bridge", "FireClient failed for " .. getPlayerName(player) .. ": " .. tostring(err))
	end
end

-- ============================================================
-- CLIENT -> SERVER EVENT HANDLER
-- ============================================================

bridge.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then
		warn_tag("Bridge", "Non-table payload from " .. getPlayerName(player) .. ": " .. type(payload))
		return
	end

	local pType = tostring(payload.Type)
	log("Bridge", "→ Event from " .. getPlayerName(player) .. ": type=" .. pType)

	-- ---- Ping / Pong ----
	if pType == "Ping" then
		log("Bridge", "Ping received from " .. getPlayerName(player) .. " at t=" .. tostring(payload.Time))
		sendToClient(player, {Type = "Pong", Time = tick(), ServerTime = os.clock()})
		log("Bridge", "Pong sent to " .. getPlayerName(player))

	elseif pType == "Pong" then
		local latency = payload.Time and (tick() - payload.Time) or -1
		log("Bridge", "Pong back from " .. getPlayerName(player) .. " latency~=" .. string.format("%.3f", latency) .. "s")

	-- ---- Script Source Push (client wants to update a server script's source) ----
	elseif pType == "ScriptViewerSync" then
		local path   = tostring(payload.TargetPath or "")
		local source = payload.Source

		if type(source) ~= "string" then
			warn_tag("Bridge", "ScriptViewerSync from " .. getPlayerName(player) .. " — Source is not a string")
			return
		end

		log("Bridge", "ScriptViewerSync from " .. getPlayerName(player) .. " target=" .. path .. " source_len=" .. #source)

		local target = findByPath(path)
		if not target then
			warn_tag("Bridge", "ScriptViewerSync: target not found: " .. path)
			sendToClient(player, {Type="ServerLog", Message="[Error] Script not found: " .. path})
			return
		end
		if not target:IsA("LuaSourceContainer") then
			warn_tag("Bridge", "ScriptViewerSync: target is not a LuaSourceContainer: " .. path)
			sendToClient(player, {Type="ServerLog", Message="[Error] Not a script: " .. path})
			return
		end

		local ok, err = pcall(function() target.Source = source end)
		if ok then
			log("Bridge", "Source applied to " .. path .. " (" .. #source .. " bytes)")
			sendToClient(player, {Type="ServerLog", Message="[OK] Source updated: " .. path})
		else
			warn_tag("Bridge", "Source apply failed for " .. path .. ": " .. tostring(err))
			sendToClient(player, {Type="ServerLog", Message="[Error] Failed to apply source: " .. tostring(err)})
		end

	-- ---- Explorer Live Edit: Delete ----
	elseif pType == "ExplorerLiveEdit" and payload.Action == "Delete" then
		local path = tostring(payload.TargetPath or "")
		log("Bridge", "ExplorerLiveEdit Delete from " .. getPlayerName(player) .. " target=" .. path)

		local target = findByPath(path)
		if not target then
			warn_tag("Bridge", "Delete: target not found: " .. path)
			sendToClient(player, {Type="ServerLog", Message="[Error] Not found: " .. path})
			return
		end

		local ok, err = pcall(target.Destroy, target)
		if ok then
			log("Bridge", "Destroyed: " .. path)
			sendToClient(player, {Type="ServerLog", Message="[OK] Destroyed: " .. path})
		else
			warn_tag("Bridge", "Destroy failed for " .. path .. ": " .. tostring(err))
			sendToClient(player, {Type="ServerLog", Message="[Error] Destroy failed: " .. tostring(err)})
		end

	-- ---- Explorer Live Edit: Property Change ----
	elseif pType == "ExplorerLiveEdit" and type(payload.Action) == "string" and payload.Action:sub(1,16) == "PropertyChanged:" then
		local path     = tostring(payload.TargetPath or "")
		local propName = payload.Action:sub(17)
		local value    = payload.Value

		log("Bridge", "PropertyChanged from " .. getPlayerName(player) .. " target=" .. path .. " prop=" .. propName .. " value=" .. tostring(value))

		local target = findByPath(path)
		if not target then
			warn_tag("Bridge", "PropertyChanged: target not found: " .. path)
			sendToClient(player, {Type="ServerLog", Message="[Error] Not found: " .. path})
			return
		end

		local ok, err = pcall(function() target[propName] = value end)
		if ok then
			log("Bridge", "Property '" .. propName .. "' set on " .. path)
			sendToClient(player, {Type="ServerLog", Message="[OK] " .. propName .. " set on " .. path})
		else
			warn_tag("Bridge", "Property set failed: " .. tostring(err))
			sendToClient(player, {Type="ServerLog", Message="[Error] " .. propName .. " set failed: " .. tostring(err)})
		end

	-- ---- Properties Live Edit ----
	elseif pType == "PropertiesLiveEdit" then
		log("Bridge", "PropertiesLiveEdit from " .. getPlayerName(player) .. " action=" .. tostring(payload.Action) .. " target=" .. tostring(payload.TargetPath))
		-- Forwarded to PropertyChanged handler above if needed
		sendToClient(player, {Type="ServerLog", Message="[Info] PropertiesLiveEdit received: " .. tostring(payload.Action)})

	-- ---- Unknown ----
	else
		warn_tag("Bridge", "Unknown event type '" .. pType .. "' from " .. getPlayerName(player))
	end
end)

log("Bridge", "OnServerEvent handler registered")

-- ============================================================
-- SERVER SCRIPT LIST (DexBridgeList)
-- ============================================================

bridgeList.OnServerInvoke = function(player)
	log("List", "Script list requested by " .. getPlayerName(player))

	local out = {}
	local ok, err = pcall(function()
		for _, obj in ipairs(ServerScriptService:GetDescendants()) do
			if obj:IsA("LuaSourceContainer") then
				out[#out+1] = {
					Name      = obj.Name,
					Path      = obj:GetFullName(),
					ClassName = obj.ClassName,
					Disabled  = obj.Disabled,
					SourceLen = #obj.Source,
				}
			end
		end
	end)

	if not ok then
		warn_tag("List", "GetDescendants failed: " .. tostring(err))
		return {}
	end

	log("List", "Returning " .. #out .. " scripts to " .. getPlayerName(player))
	return out
end

log("List", "DexBridgeList handler registered")

-- ============================================================
-- GENERIC INVOKE (DexBridgeFn)
-- ============================================================

bridgeFn.OnServerInvoke = function(player, payload)
	if type(payload) ~= "table" then
		warn_tag("Fn", "Non-table invoke from " .. getPlayerName(player))
		return {Success=false, Error="payload must be a table"}
	end

	local pType = tostring(payload.Type or "")
	log("Fn", "Invoke from " .. getPlayerName(player) .. ": type=" .. pType)

	-- Get script source
	if pType == "GetSource" then
		local path = tostring(payload.Path or "")
		log("Fn", "GetSource: " .. path)

		local target = findByPath(path)
		if not target or not target:IsA("LuaSourceContainer") then
			warn_tag("Fn", "GetSource: not found or not a script: " .. path)
			return {Success=false, Error="Not found: " .. path}
		end

		local src = ""
		local ok, err = pcall(function() src = target.Source end)
		if not ok then
			warn_tag("Fn", "GetSource read failed: " .. tostring(err))
			return {Success=false, Error=tostring(err)}
		end

		log("Fn", "GetSource returning " .. #src .. " bytes for " .. path)
		return {Success=true, Source=src, Path=path}

	-- Set property
	elseif pType == "SetProperty" then
		local path     = tostring(payload.Path or "")
		local propName = tostring(payload.Property or "")
		local value    = payload.Value

		log("Fn", "SetProperty: " .. path .. "." .. propName .. " = " .. tostring(value))

		local target = findByPath(path)
		if not target then
			return {Success=false, Error="Not found: " .. path}
		end

		local ok, err = pcall(function() target[propName] = value end)
		if ok then
			log("Fn", "SetProperty OK: " .. path .. "." .. propName)
			return {Success=true}
		else
			warn_tag("Fn", "SetProperty failed: " .. tostring(err))
			return {Success=false, Error=tostring(err)}
		end

	-- Call a function on an object
	elseif pType == "CallMethod" then
		local path   = tostring(payload.Path or "")
		local method = tostring(payload.Method or "")
		local args   = type(payload.Args) == "table" and payload.Args or {}

		log("Fn", "CallMethod: " .. path .. ":" .. method .. "(" .. #args .. " args)")

		local target = findByPath(path)
		if not target then
			return {Success=false, Error="Not found: " .. path}
		end

		local fn = target[method]
		if type(fn) ~= "function" then
			return {Success=false, Error="Method not found: " .. method}
		end

		local ok, result = pcall(fn, target, unpack(args))
		if ok then
			log("Fn", "CallMethod OK: " .. path .. ":" .. method)
			return {Success=true, Result=tostring(result)}
		else
			warn_tag("Fn", "CallMethod failed: " .. tostring(result))
			return {Success=false, Error=tostring(result)}
		end

	else
		warn_tag("Fn", "Unknown invoke type: " .. pType)
		return {Success=false, Error="Unknown type: " .. pType}
	end
end

log("Fn", "DexBridgeFn handler registered")

-- ============================================================
-- PLAYER TRACKING
-- ============================================================

Players.PlayerAdded:Connect(function(player)
	log("Players", player.Name .. " joined — bridge available")
end)

Players.PlayerRemoving:Connect(function(player)
	log("Players", player.Name .. " left")
end)

-- ============================================================
-- DONE
-- ============================================================

log("Init", "=== Dex Server Bridge ready ===")
log("Init", "Listening on: " .. BRIDGE_NAME .. ", " .. BRIDGE_LIST_NAME .. ", " .. BRIDGE_FN_NAME)
