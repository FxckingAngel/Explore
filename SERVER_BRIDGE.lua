--[[
	Dex Server Bridge — FxckingAngel/Explore
	
	Place this Script in ServerScriptService.
	Handles all client -> server live edit events and applies them in real-time.
	
	Remotes in ReplicatedStorage:
	  DexBridge      — RemoteEvent  (fire-and-forget)
	  DexBridgeList  — RemoteFunction (script list)
	  DexBridgeFn    — RemoteFunction (invoke actions)
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")
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
	if existing and existing:IsA(class) then
		log("Init", name .. " already exists")
		return existing
	end
	if existing then pcall(existing.Destroy, existing) end
	local inst = Instance.new(class)
	inst.Name = name
	inst.Parent = parent
	log("Init", "Created " .. class .. " '" .. name .. "'")
	return inst
end

local bridge     = getOrCreate("RemoteEvent",    BRIDGE_NAME,      ReplicatedStorage)
local bridgeList = getOrCreate("RemoteFunction", BRIDGE_LIST_NAME, ReplicatedStorage)
local bridgeFn   = getOrCreate("RemoteFunction", BRIDGE_FN_NAME,   ReplicatedStorage)

log("Init", "All remotes ready")

-- ============================================================
-- HELPERS
-- ============================================================

local function playerName(player)
	return player and player.Name or "unknown"
end

local function findByPath(path)
	if type(path) ~= "string" or path == "" then return nil end
	local cur = game
	for part in path:gmatch("[^%.]+") do
		if cur == game and part == "game" then continue end
		cur = cur:FindFirstChild(part)
		if not cur then return nil end
	end
	return cur
end

local function sendToClient(player, payload)
	pcall(bridge.FireClient, bridge, player, payload)
end

-- ============================================================
-- VALUE DESERIALIZER
-- Reconstructs Roblox types from the serialized table the
-- client sends (mirrors serializeValue() in Properties.lua)
-- ============================================================

local function deserializeValue(s)
	if type(s) ~= "table" then return s end
	local t = s.t
	if t == "nil" then return nil
	elseif t == "number" or t == "boolean" or t == "string" then return s.v
	elseif t == "Vector3" then return Vector3.new(s.x, s.y, s.z)
	elseif t == "Vector2" then return Vector2.new(s.x, s.y)
	elseif t == "Color3" then return Color3.new(s.r, s.g, s.b)
	elseif t == "CFrame" then
		if type(s.c) == "table" then
			return CFrame.new(table.unpack(s.c))
		end
		return CFrame.new()
	elseif t == "UDim" then return UDim.new(s.s, s.o)
	elseif t == "UDim2" then return UDim2.new(s.xs, s.xo, s.ys, s.yo)
	elseif t == "BrickColor" then return BrickColor.new(s.n)
	elseif t == "EnumItem" then
		local ok, item = pcall(function()
			return Enum[s.et]:FromValue(s.ev)
		end)
		return ok and item or nil
	elseif t == "NumberRange" then return NumberRange.new(s.min, s.max)
	elseif t == "NumberSequence" then
		local kps = {}
		for _, kp in ipairs(s.kps or {}) do
			kps[#kps+1] = NumberSequenceKeypoint.new(kp.t, kp.v, kp.e or 0)
		end
		return NumberSequence.new(kps)
	elseif t == "ColorSequence" then
		local kps = {}
		for _, kp in ipairs(s.kps or {}) do
			kps[#kps+1] = ColorSequenceKeypoint.new(kp.t, Color3.new(kp.r, kp.g, kp.b))
		end
		return ColorSequence.new(kps)
	elseif t == "Rect" then
		return Rect.new(s.x0, s.y0, s.x1, s.y1)
	elseif t == "Ray" then
		return Ray.new(Vector3.new(s.ox, s.oy, s.oz), Vector3.new(s.dx, s.dy, s.dz))
	elseif t == "PhysicalProperties" then
		return PhysicalProperties.new(s.d, s.f, s.e, s.fw, s.ew)
	elseif t == "Instance" then
		return findByPath(s.path)
	end
	return tostring(s.v or "")
end

-- ============================================================
-- MAIN EVENT HANDLER
-- ============================================================

bridge.OnServerEvent:Connect(function(player, payload)
	if type(payload) ~= "table" then
		warn_tag("Bridge", "Non-table payload from " .. playerName(player))
		return
	end

	local pType = tostring(payload.Type or "")
	local path  = tostring(payload.TargetPath or "")

	-- ---- Ping ----
	if pType == "Ping" then
		log("Bridge", "Ping from " .. playerName(player))
		sendToClient(player, {Type="Pong", Time=tick()})
		return

	elseif pType == "Pong" then
		log("Bridge", "Pong from " .. playerName(player))
		return
	end

	-- ---- ExplorerLiveEdit ----
	if pType == "ExplorerLiveEdit" then
		local action = tostring(payload.Action or "")
		log("Explorer", playerName(player) .. " action=" .. action .. " path=" .. path)

		-- DELETE
		if action == "Delete" then
			local target = findByPath(path)
			if not target then
				warn_tag("Explorer", "Delete: not found: " .. path)
				sendToClient(player, {Type="ServerLog", Message="[Error] Not found: " .. path})
				return
			end
			local ok, err = pcall(target.Destroy, target)
			if ok then
				log("Explorer", "Deleted: " .. path)
				sendToClient(player, {Type="ServerLog", Message="[OK] Deleted: " .. path})
			else
				warn_tag("Explorer", "Delete failed: " .. tostring(err))
				sendToClient(player, {Type="ServerLog", Message="[Error] Delete failed: " .. tostring(err)})
			end

		-- RENAME
		elseif action == "Rename" then
			local target = findByPath(path)
			local newName = tostring(payload.NewName or "")
			if not target then
				warn_tag("Explorer", "Rename: not found: " .. path)
				sendToClient(player, {Type="ServerLog", Message="[Error] Not found: " .. path})
				return
			end
			if newName == "" then
				sendToClient(player, {Type="ServerLog", Message="[Error] Empty name"})
				return
			end
			local ok, err = pcall(function() target.Name = newName end)
			if ok then
				log("Explorer", "Renamed " .. path .. " -> " .. newName)
				sendToClient(player, {Type="ServerLog", Message="[OK] Renamed to: " .. newName})
			else
				warn_tag("Explorer", "Rename failed: " .. tostring(err))
				sendToClient(player, {Type="ServerLog", Message="[Error] Rename failed: " .. tostring(err)})
			end

		-- PASTE / DUPLICATE (clone already happened client-side, we replicate it server-side)
		elseif action == "Paste" then
			local clonePath  = tostring(payload.ClonePath or "")
			local parentPath = tostring(payload.ParentPath or "")
			-- The cloned instance already exists on the client but NOT on server
			-- We need to find the original (before clone) and clone it server-side
			-- Best effort: find by path after the paste
			local cloned = findByPath(clonePath)
			if cloned then
				log("Explorer", "Paste already visible server-side: " .. clonePath)
				sendToClient(player, {Type="ServerLog", Message="[OK] Paste visible: " .. clonePath})
			else
				-- Try to find parent and create a placeholder note
				warn_tag("Explorer", "Paste: clone not visible server-side yet: " .. clonePath)
				sendToClient(player, {Type="ServerLog", Message="[Info] Paste: " .. clonePath .. " (may need server script to replicate)"})
			end

		-- CREATE INSTANCE (from Group etc)
		elseif action == "CreateInstance" then
			local className  = tostring(payload.ClassName or "Model")
			local parentPath = tostring(payload.ParentPath or "")
			local instPath   = tostring(payload.InstancePath or "")
			-- Check if already exists (client created it, may be replicated)
			local existing = findByPath(instPath)
			if existing then
				log("Explorer", "CreateInstance already server-side: " .. instPath)
				sendToClient(player, {Type="ServerLog", Message="[OK] Instance exists: " .. instPath})
			else
				local parent = findByPath(parentPath)
				if not parent then
					warn_tag("Explorer", "CreateInstance: parent not found: " .. parentPath)
					sendToClient(player, {Type="ServerLog", Message="[Error] Parent not found: " .. parentPath})
				else
					local ok, inst = pcall(function()
						local i = Instance.new(className)
						i.Parent = parent
						return i
					end)
					if ok and inst then
						log("Explorer", "Created " .. className .. " in " .. parentPath)
						sendToClient(player, {Type="ServerLog", Message="[OK] Created " .. className .. " in " .. parentPath})
					else
						warn_tag("Explorer", "CreateInstance failed: " .. tostring(inst))
						sendToClient(player, {Type="ServerLog", Message="[Error] Create failed: " .. tostring(inst)})
					end
				end
			end

		-- REPARENT
		elseif action == "Reparent" then
			local target    = findByPath(path)
			local newParent = findByPath(tostring(payload.NewParentPath or ""))
			if not target then
				warn_tag("Explorer", "Reparent: target not found: " .. path)
				sendToClient(player, {Type="ServerLog", Message="[Error] Target not found: " .. path})
				return
			end
			if not newParent then
				warn_tag("Explorer", "Reparent: parent not found: " .. tostring(payload.NewParentPath))
				sendToClient(player, {Type="ServerLog", Message="[Error] Parent not found: " .. tostring(payload.NewParentPath)})
				return
			end
			local ok, err = pcall(function() target.Parent = newParent end)
			if ok then
				log("Explorer", "Reparented " .. path .. " -> " .. tostring(payload.NewParentPath))
				sendToClient(player, {Type="ServerLog", Message="[OK] Reparented to: " .. tostring(payload.NewParentPath)})
			else
				warn_tag("Explorer", "Reparent failed: " .. tostring(err))
				sendToClient(player, {Type="ServerLog", Message="[Error] Reparent failed: " .. tostring(err)})
			end

		else
			log("Explorer", "Unknown Explorer action: " .. action)
		end

		return
	end

	-- ---- PropertiesLiveEdit ----
	if pType == "PropertiesLiveEdit" then
		local action = tostring(payload.Action or "")
		log("Properties", playerName(player) .. " action=" .. action .. " path=" .. path)

		-- PropertyChanged:PropName
		if action:sub(1,16) == "PropertyChanged:" then
			local propName = action:sub(17)
			local target = findByPath(path)

			if not target then
				warn_tag("Properties", "Target not found: " .. path)
				sendToClient(player, {Type="ServerLog", Message="[Error] Not found: " .. path})
				return
			end

			-- Deserialize the value
			local value = deserializeValue(payload.Value)

			-- Handle attribute edits (propName starts with "Attribute:")
			if propName:sub(1,10) == "Attribute:" then
				local attrName = propName:sub(11)
				local ok, err = pcall(function()
					target:SetAttribute(attrName, value)
				end)
				if ok then
					log("Properties", "Attribute '" .. attrName .. "' set on " .. path .. " = " .. tostring(value))
					sendToClient(player, {Type="ServerLog", Message="[OK] Attr " .. attrName .. " = " .. tostring(value)})
				else
					warn_tag("Properties", "Attribute set failed: " .. tostring(err))
					sendToClient(player, {Type="ServerLog", Message="[Error] " .. attrName .. " failed: " .. tostring(err)})
				end
			else
				-- Regular property
				local ok, err = pcall(function()
					target[propName] = value
				end)
				if ok then
					log("Properties", "'" .. propName .. "' set on " .. path .. " = " .. tostring(value))
					sendToClient(player, {Type="ServerLog", Message="[OK] " .. propName .. " = " .. tostring(value)})
				else
					warn_tag("Properties", "Property set failed for " .. propName .. ": " .. tostring(err))
					sendToClient(player, {Type="ServerLog", Message="[Error] " .. propName .. " failed: " .. tostring(err)})
				end
			end

		else
			log("Properties", "Unknown Properties action: " .. action)
		end

		return
	end

	-- ---- ScriptViewerSync ----
	if pType == "ScriptViewerSync" then
		local source = payload.Source
		if type(source) ~= "string" then
			warn_tag("Script", "ScriptViewerSync: Source is not a string")
			sendToClient(player, {Type="ServerLog", Message="[Error] Source must be a string"})
			return
		end
		local target = findByPath(path)
		if not target or not target:IsA("LuaSourceContainer") then
			warn_tag("Script", "ScriptViewerSync: not a script: " .. path)
			sendToClient(player, {Type="ServerLog", Message="[Error] Not a script: " .. path})
			return
		end
		local ok, err = pcall(function() target.Source = source end)
		if ok then
			log("Script", "Source updated: " .. path .. " (" .. #source .. " bytes)")
			sendToClient(player, {Type="ServerLog", Message="[OK] Source updated: " .. path})
		else
			warn_tag("Script", "Source update failed: " .. tostring(err))
			sendToClient(player, {Type="ServerLog", Message="[Error] Source update failed: " .. tostring(err)})
		end
		return
	end

	warn_tag("Bridge", "Unknown payload type '" .. pType .. "' from " .. playerName(player))
end)

log("Bridge", "OnServerEvent handler registered")

-- ============================================================
-- SCRIPT LIST
-- ============================================================

bridgeList.OnServerInvoke = function(player)
	log("List", "Requested by " .. playerName(player))
	local out = {}
	pcall(function()
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
	log("List", "Returning " .. #out .. " scripts to " .. playerName(player))
	return out
end

-- ============================================================
-- GENERIC INVOKE
-- ============================================================

bridgeFn.OnServerInvoke = function(player, payload)
	if type(payload) ~= "table" then return {Success=false, Error="payload must be table"} end
	local pType = tostring(payload.Type or "")
	log("Fn", playerName(player) .. " type=" .. pType)

	if pType == "GetSource" then
		local target = findByPath(tostring(payload.Path or ""))
		if not target or not target:IsA("LuaSourceContainer") then
			return {Success=false, Error="Not a script: " .. tostring(payload.Path)}
		end
		local ok, src = pcall(function() return target.Source end)
		if not ok then return {Success=false, Error=tostring(src)} end
		log("Fn", "GetSource " .. tostring(payload.Path) .. " (" .. #src .. " bytes)")
		return {Success=true, Source=src, Path=payload.Path}

	elseif pType == "SetProperty" then
		local target = findByPath(tostring(payload.Path or ""))
		if not target then return {Success=false, Error="Not found: " .. tostring(payload.Path)} end
		local value = deserializeValue(payload.Value)
		local ok, err = pcall(function() target[tostring(payload.Property)] = value end)
		if ok then
			log("Fn", "SetProperty " .. tostring(payload.Property) .. " on " .. tostring(payload.Path))
			return {Success=true}
		end
		return {Success=false, Error=tostring(err)}

	elseif pType == "CallMethod" then
		local target = findByPath(tostring(payload.Path or ""))
		if not target then return {Success=false, Error="Not found: " .. tostring(payload.Path)} end
		local method = tostring(payload.Method or "")
		local fn = target[method]
		if type(fn) ~= "function" then return {Success=false, Error="No method: " .. method} end
		local args = type(payload.Args) == "table" and payload.Args or {}
		local ok, result = pcall(fn, target, table.unpack(args))
		if ok then
			log("Fn", "CallMethod " .. method .. " on " .. tostring(payload.Path))
			return {Success=true, Result=tostring(result)}
		end
		return {Success=false, Error=tostring(result)}
	end

	return {Success=false, Error="Unknown type: " .. pType}
end

-- ============================================================
-- PLAYER TRACKING
-- ============================================================

Players.PlayerAdded:Connect(function(p)
	log("Players", p.Name .. " joined")
end)
Players.PlayerRemoving:Connect(function(p)
	log("Players", p.Name .. " left")
end)

-- ============================================================
-- DONE
-- ============================================================

log("Init", "=== Dex Server Bridge ready ===")
log("Init", "Listening: " .. BRIDGE_NAME .. " | " .. BRIDGE_LIST_NAME .. " | " .. BRIDGE_FN_NAME)
