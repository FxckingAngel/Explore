--[[
	Dex Loader — FxckingAngel/Explore
	
	Client-side entry point. Loads all modules, builds the full Dex UI,
	and establishes the client<->server bridge (DexBridge RemoteEvent).
	
	Usage:
	  loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/refs/heads/main/loader.lua"))()
]]

-- ============================================================
-- 0. CONSTANTS
-- ============================================================

local BASE_URL  = "https://raw.githubusercontent.com/FxckingAngel/Explore/refs/heads/main/Modules/"

-- ============================================================
-- 1. HELPERS
-- ============================================================

local function log(tag, msg)
	print(("[Dex][%s] %s"):format(tag, tostring(msg)))
end

local function warn_tag(tag, msg)
	warn(("[Dex][%s] %s"):format(tag, tostring(msg)))
end

local function fetch(module)
	log("Loader", "Fetching module: " .. module .. " ...")
	local ok, src = pcall(function()
		return game:HttpGet(BASE_URL .. module .. ".lua")
	end)
	if not ok or not src or #src == 0 then
		error(("[Dex][Loader] HTTP failed for '%s': %s"):format(module, tostring(src)), 2)
	end
	log("Loader", module .. " fetched (" .. #src .. " bytes)")

	local fn, err = loadstring(src)
	if not fn then
		error(("[Dex][Loader] Compile error in '%s': %s"):format(module, tostring(err)), 2)
	end

	local ok2, result = pcall(fn)
	if not ok2 then
		error(("[Dex][Loader] Runtime error in '%s': %s"):format(module, tostring(result)), 2)
	end
	log("Loader", module .. " loaded OK")
	return result
end

-- ============================================================
-- 2. FETCH MODULE CONTROL TABLES
-- ============================================================

log("Loader", "=== Starting Dex ===")
log("Loader", "Fetching Lib...")
local LibControl        = fetch("Lib")
log("Loader", "Fetching Explorer...")
local ExplorerControl   = fetch("Explorer")
log("Loader", "Fetching Properties...")
local PropertiesControl = fetch("Properties")
log("Loader", "Fetching ScriptViewer...")
local SVControl         = fetch("ScriptViewer")
log("Loader", "All modules fetched")

-- ============================================================
-- 3. SERVICES + PLAYER
-- ============================================================

local service = setmetatable({}, {__index = function(self, name)
	local s = game:GetService(name)
	self[name] = s
	return s
end})

local plr = service.Players.LocalPlayer
	or service.Players.PlayerAdded:Wait()

log("Loader", "Player: " .. tostring(plr.Name))

-- ============================================================
-- 4. SETTINGS
-- ============================================================

local Settings = {}

local function applyDefaults(defaults, target)
	for k, v in pairs(defaults) do
		if type(v) == "table" and v._Recurse then
			target[k] = target[k] or {}
			applyDefaults(v, target[k])
		else
			target[k] = v
		end
	end
end

applyDefaults({
	Explorer = {
		_Recurse = true,
		Sorting = true,
		TeleportToOffset = Vector3.new(0,0,0),
		ClickToRename = true,
		AutoUpdateSearch = true,
		AutoUpdateMode = 0,
		LiveEditMode = true,
		PartSelectionBox = true,
		GuiSelectionBox = true,
		CopyPathUseGetChildren = true,
		UseNameWidth = false,
	},
	Properties = {
		_Recurse = true,
		MaxConflictCheck = 50,
		ShowDeprecated = false,
		ShowHidden = false,
		ClearOnFocus = false,
		LoadstringInput = true,
		NumberRounding = 3,
		ShowAttributes = false,
		LiveEditMode = true,
		MaxAttributes = 50,
		ScaleType = 1,
	},
	Theme = {
		_Recurse = true,
		Main1 = Color3.fromRGB(52,52,52),
		Main2 = Color3.fromRGB(45,45,45),
		Outline1 = Color3.fromRGB(33,33,33),
		Outline2 = Color3.fromRGB(55,55,55),
		Outline3 = Color3.fromRGB(30,30,30),
		TextBox = Color3.fromRGB(38,38,38),
		Menu = Color3.fromRGB(32,32,32),
		ListSelection = Color3.fromRGB(11,90,175),
		Button = Color3.fromRGB(60,60,60),
		ButtonHover = Color3.fromRGB(68,68,68),
		ButtonPress = Color3.fromRGB(40,40,40),
		Highlight = Color3.fromRGB(75,75,75),
		Text = Color3.fromRGB(255,255,255),
		PlaceholderText = Color3.fromRGB(100,100,100),
		Important = Color3.fromRGB(255,0,0),
		ExplorerIconMap = "",
		MiscIconMap = "",
		Syntax = {
			Text = Color3.fromRGB(204,204,204),
			Background = Color3.fromRGB(36,36,36),
			Selection = Color3.fromRGB(255,255,255),
			SelectionBack = Color3.fromRGB(11,90,175),
			Operator = Color3.fromRGB(204,204,204),
			Number = Color3.fromRGB(255,198,0),
			String = Color3.fromRGB(173,241,149),
			Comment = Color3.fromRGB(102,102,102),
			Keyword = Color3.fromRGB(248,109,124),
			Error = Color3.fromRGB(255,0,0),
			FindBackground = Color3.fromRGB(141,118,0),
			MatchingWord = Color3.fromRGB(85,85,85),
			BuiltIn = Color3.fromRGB(132,214,247),
			CurrentLine = Color3.fromRGB(45,50,65),
			LocalMethod = Color3.fromRGB(253,251,172),
			LocalProperty = Color3.fromRGB(97,161,241),
			Nil = Color3.fromRGB(255,198,0),
			Bool = Color3.fromRGB(255,198,0),
			Function = Color3.fromRGB(248,109,124),
			Local = Color3.fromRGB(248,109,124),
			Self = Color3.fromRGB(248,109,124),
			FunctionName = Color3.fromRGB(253,251,172),
			Bracket = Color3.fromRGB(204,204,204),
		},
	},
}, Settings)

log("Loader", "Settings applied")

-- ============================================================
-- 5. GUI HOLDER + HELPERS
-- ============================================================

local elevated = pcall(function() game:GetService("CoreGui"):GetFullName() end)
local GuiHolder = elevated and game:GetService("CoreGui") or plr:FindFirstChildOfClass("PlayerGui")
log("Loader", "Elevated: " .. tostring(elevated) .. "  GuiHolder: " .. tostring(GuiHolder))

local create = function(data)
	local insts = {}
	for i,v in pairs(data) do insts[v[1]] = Instance.new(v[2]) end
	for _,v in pairs(data) do
		for prop,val in pairs(v[3]) do
			if type(val) == "table" then insts[v[1]][prop] = insts[val[1]]
			else insts[v[1]][prop] = val end
		end
	end
	return insts[1]
end

local createSimple = function(class, props)
	local inst = Instance.new(class)
	for i,v in next, props do inst[i] = v end
	return inst
end

-- ============================================================
-- 6. LIB INIT (must happen before API fetch so ParseXML exists)
-- ============================================================

local Main = {
	Elevated = elevated,
	GuiHolder = GuiHolder,
	Mouse = plr:GetMouse(),
	DisplayOrders = {SideWindow=8, Window=10, Menu=100000, Core=101000},
	MiscIcons = nil,
	LargeIcons = nil,
	Apps = {},
	AppControls = {},
	MenuApps = {},
}

local env = {}
local Apps = Main.Apps

local deps = {
	Main=Main, Lib=nil, Apps=Apps, Settings=Settings,
	API=nil, RMD=nil, env=env, service=service, plr=plr,
	create=create, createSimple=createSimple,
}

log("Lib", "Running Lib.Main()...")
LibControl.InitDeps(deps)
local Lib = LibControl.Main()
deps.Lib = Lib
log("Lib", "Lib ready")

-- Build icon maps
Main.MiscIcons = Lib.IconMap.new("rbxassetid://6511490623",256,256,16,16)
Main.LargeIcons = Lib.IconMap.new("rbxassetid://6579106223",256,256,32,32)
Main.MiscIcons:SetDict({
	Reference=0, Cut=1, Cut_Disabled=2, Copy=3, Copy_Disabled=4, Paste=5, Paste_Disabled=6,
	Delete=7, Delete_Disabled=8, Group=9, Group_Disabled=10, Ungroup=11, Ungroup_Disabled=12,
	TeleportTo=13, Rename=14, JumpToParent=15, ExploreData=16, Save=17, CallFunction=18,
	CallRemote=19, Undo=20, Undo_Disabled=21, Redo=22, Redo_Disabled=23,
	Expand_Over=24, Expand=25, Collapse_Over=26, Collapse=27,
	SelectChildren=28, SelectChildren_Disabled=29, InsertObject=30, ViewScript=31,
	AddStar=32, RemoveStar=33, Script_Disabled=34, LocalScript_Disabled=35,
	Play=36, Pause=37, Rename_Disabled=38,
})
Main.LargeIcons:SetDict({Explorer=0, Properties=1, Script_Viewer=2})
Main.ShowGui = function(gui) gui.Parent = GuiHolder end

log("Loader", "Icon maps ready")

-- ============================================================
-- 7. API DUMP
-- ============================================================

log("API", "Resolving Roblox version...")
local rawEnv = (type(getfenv) == "function" and getfenv()) or _G
local getVersion = rawEnv.Version or rawEnv.version or _G.Version or _G.version
if type(getVersion) ~= "function" then
	error("[Dex][API] Could not find Version() function in executor env")
end
local okVer, versionId = pcall(getVersion)
if not okVer or type(versionId) ~= "string" or #versionId == 0 then
	error("[Dex][API] Version() failed: " .. tostring(versionId))
end
log("API", "Roblox version: " .. versionId)

local apiUrls = {
	"https://setup.roblox.com/"..versionId.."-API-Dump.json",
	"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json",
}

local rawAPI, usedApiUrl
for i, url in ipairs(apiUrls) do
	log("API", "Trying URL " .. i .. ": " .. url)
	local ok, data = pcall(game.HttpGet, game, url)
	if ok and type(data) == "string" and #data > 100 then
		rawAPI = data
		usedApiUrl = url
		log("API", "Fetched from URL " .. i .. " (" .. #data .. " bytes)")
		break
	else
		warn_tag("API", "URL " .. i .. " failed: " .. tostring(data))
	end
end
if not rawAPI then
	error("[Dex][API] All API dump URLs failed")
end

log("API", "Decoding JSON...")
local okDec, apiData = pcall(service.HttpService.JSONDecode, service.HttpService, rawAPI)
if not okDec then
	error("[Dex][API] JSON decode failed: " .. tostring(apiData))
end
log("API", "JSON decoded. Classes: " .. tostring(#(apiData.Classes or {})))

local API = {Classes={}, Enums={}, CategoryOrder={}, GetMember=function() return {} end}
local seenCats = {}

for _, class in pairs(apiData.Classes) do
	local nc = {Name=class.Name, Superclass=class.Superclass, Properties={}, Functions={}, Events={}, Callbacks={}, Tags={}}
	if class.Tags then for _,t in pairs(class.Tags) do nc.Tags[t]=true end end
	for _, member in pairs(class.Members) do
		local nm = {Name=member.Name, Class=class.Name, Security=member.Security, Tags={}}
		if member.Tags then for _,t in pairs(member.Tags) do nm.Tags[t]=true end end
		if member.MemberType == "Property" then
			local cat = (member.Category or "Other"):match("^%s*(.-)%s*$")
			if not seenCats[cat] then API.CategoryOrder[cat]=#API.CategoryOrder+1 seenCats[cat]=true end
			nm.ValueType = member.ValueType nm.Category = cat nm.Serialization = member.Serialization
			table.insert(nc.Properties, nm)
		elseif member.MemberType == "Function" then
			nm.Parameters={} nm.ReturnType = member.ReturnType.Name
			for _,p in pairs(member.Parameters) do table.insert(nm.Parameters,{Name=p.Name,Type=p.Type.Name}) end
			table.insert(nc.Functions, nm)
		elseif member.MemberType == "Event" then
			nm.Parameters={}
			for _,p in pairs(member.Parameters) do table.insert(nm.Parameters,{Name=p.Name,Type=p.Type.Name}) end
			table.insert(nc.Events, nm)
		end
	end
	API.Classes[class.Name] = nc
end
for _, class in pairs(API.Classes) do
	class.Superclass = API.Classes[class.Superclass]
end
for _, enum in pairs(apiData.Enums) do
	local ne = {Name=enum.Name, Items={}, Tags={}}
	if enum.Tags then for _,t in pairs(enum.Tags) do ne.Tags[t]=true end end
	for _,item in pairs(enum.Items) do table.insert(ne.Items,{Name=item.Name,Value=item.Value}) end
	API.Enums[enum.Name] = ne
end
log("API", "API built OK")

-- ============================================================
-- 8. RMD
-- ============================================================

local RMD = {Classes={}, Enums={}, PropertyOrders={}}
log("RMD", "Fetching ReflectionMetadata...")
local okRMD, rmdErr = pcall(function()
	local rawXML = game:HttpGet("https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/ReflectionMetadata.xml")
	log("RMD", "Fetched (" .. #rawXML .. " bytes), parsing...")
	local parsed = Lib.ParseXML(rawXML)
	local classList = parsed.children[1].children[1].children
	local classCount = 0
	for _, class in pairs(classList) do
		local className = ""
		for _, child in pairs(class.children) do
			if child.tag == "Properties" then
				local data = {Properties={}, Functions={}}
				for _, prop in pairs(child.children) do
					local name = prop.attrs.name
					name = name:sub(1,1):upper()..name:sub(2)
					data[name] = prop.children[1].text
				end
				className = data.Name
				RMD.Classes[className] = data
				classCount = classCount + 1
			elseif child.attrs and child.attrs.class == "ReflectionMetadataProperties" then
				for _, member in pairs(child.children) do
					if member.attrs and member.attrs.class == "ReflectionMetadataMember" then
						local data = {}
						if member.children[1] and member.children[1].tag == "Properties" then
							for _, prop in pairs(member.children[1].children) do
								if prop.attrs then
									local name = prop.attrs.name
									name = name:sub(1,1):upper()..name:sub(2)
									data[name] = prop.children[1].text
								end
							end
							if data.PropertyOrder then
								RMD.PropertyOrders[className] = RMD.PropertyOrders[className] or {}
								RMD.PropertyOrders[className][data.Name] = tonumber(data.PropertyOrder)
							end
							if RMD.Classes[className] then
								RMD.Classes[className].Properties[data.Name] = data
							end
						end
					end
				end
			end
		end
	end
	log("RMD", "Parsed " .. classCount .. " classes")
end)
if not okRMD then
	warn_tag("RMD", "Failed (non-fatal): " .. tostring(rmdErr))
else
	log("RMD", "Ready")
end

-- ============================================================
-- 9. CLIENT <-> SERVER BRIDGE


-- Bridge state flags (declared early so onClientEvent can reference them)
local serverBridgeAlive = false
local serverBridgeInjected = false
-- Self-creates all remotes, keeps them alive, never depends on
-- a server script existing first.
-- ============================================================

local rs = service.ReplicatedStorage
log("Bridge", "=== Setting up client<->server bridge ===")

--[[
	REMOTE CREATION STRATEGY
	========================
	Executors with elevated access can parent Instances to
	ReplicatedStorage directly from the client. We create each
	remote if missing, then monitor it with a heartbeat loop
	so it gets re-created if something destroys it.

	Three remotes:
	  DexBridge      RemoteEvent    fire-and-forget both directions
	  DexBridgeList  RemoteFunction client requests server script list
	  DexBridgeFn    RemoteFunction client invokes server actions
]]

local BRIDGE_NAME      = "DexBridge"
local BRIDGE_LIST_NAME = "DexBridgeList"
local BRIDGE_FN_NAME   = "DexBridgeFn"

local bridge, bridgeListFn, bridgeFn

local function createRemote(class, name)
	local existing = rs:FindFirstChild(name)
	if existing and existing:IsA(class) then
		log("Bridge", name .. " already exists — reusing")
		return existing
	end
	if existing then
		-- Wrong class — destroy and recreate
		warn_tag("Bridge", name .. " exists but wrong class (" .. existing.ClassName .. "), replacing...")
		pcall(existing.Destroy, existing)
	end

	local ok, inst = pcall(function()
		local r = Instance.new(class)
		r.Name = name
		r.Parent = rs
		return r
	end)

	if ok and inst then
		log("Bridge", "Created " .. class .. " '" .. name .. "' in ReplicatedStorage ✓")
		return inst
	else
		warn_tag("Bridge", "Failed to create " .. name .. ": " .. tostring(inst))
		return nil
	end
end

local function ensureRemotes()
	bridge       = createRemote("RemoteEvent",    BRIDGE_NAME)
	bridgeListFn = createRemote("RemoteFunction", BRIDGE_LIST_NAME)
	bridgeFn     = createRemote("RemoteFunction", BRIDGE_FN_NAME)
end

-- Initial creation
ensureRemotes()

-- Keepalive loop — re-creates any remote that gets destroyed
-- Runs every 2 seconds in a detached coroutine
local keepaliveActive = true
coroutine.wrap(function()
	while keepaliveActive do
		task.wait(2)
		local changed = false

		if not rs:FindFirstChild(BRIDGE_NAME) or not rs:FindFirstChild(BRIDGE_NAME):IsA("RemoteEvent") then
			warn_tag("Bridge", BRIDGE_NAME .. " was destroyed — recreating...")
			bridge = createRemote("RemoteEvent", BRIDGE_NAME)
			-- Re-attach OnClientEvent after recreation
			if bridge then
				bridge.OnClientEvent:Connect(onClientEvent)
				log("Bridge", "OnClientEvent re-attached after recreate")
			end
			changed = true
		end

		if not rs:FindFirstChild(BRIDGE_LIST_NAME) or not rs:FindFirstChild(BRIDGE_LIST_NAME):IsA("RemoteFunction") then
			warn_tag("Bridge", BRIDGE_LIST_NAME .. " was destroyed — recreating...")
			bridgeListFn = createRemote("RemoteFunction", BRIDGE_LIST_NAME)
			changed = true
		end

		if not rs:FindFirstChild(BRIDGE_FN_NAME) or not rs:FindFirstChild(BRIDGE_FN_NAME):IsA("RemoteFunction") then
			warn_tag("Bridge", BRIDGE_FN_NAME .. " was destroyed — recreating...")
			bridgeFn = createRemote("RemoteFunction", BRIDGE_FN_NAME)
			changed = true
		end

		if changed then
			log("Bridge", "Keepalive cycle: remotes restored")
		end
	end
end)()

log("Bridge", "Keepalive loop started (2s interval)")

-- ---- Client event handler (defined before keepalive so it can be re-attached) ----
function onClientEvent(payload)
	if type(payload) ~= "table" then
		warn_tag("Bridge", "Non-table payload from server: " .. type(payload))
		return
	end

	local pType = tostring(payload.Type)
	log("Bridge", "<- Server: type=" .. pType)

	if pType == "ServerLog" then
		print(("[DexBridge][Server] %s"):format(tostring(payload.Message)))

	elseif pType == "ScriptSourcePush" then
		log("Bridge", "Script source push from server: " .. tostring(payload.Path))

	elseif pType == "Ping" then
		log("Bridge", "<- Ping from server, sending Pong...")
		if bridge then
			pcall(bridge.FireServer, bridge, {Type = "Pong", Time = tick()})
		end

	elseif pType == "Pong" then
		local latency = payload.Time and (tick() - payload.Time) or -1
		log("Bridge", "<- Pong received! Server bridge is ALIVE ✓ latency~=" .. string.format("%.3f", latency) .. "s")
		serverBridgeAlive = true  -- used by injection check

	else
		log("Bridge", "Unknown server payload type: " .. pType)
	end
end

-- Attach initial OnClientEvent listener
if bridge then
	bridge.OnClientEvent:Connect(onClientEvent)
	log("Bridge", "OnClientEvent listener registered ✓")
end

-- ---- Helpers ----

local function bridgeSend(payload)
	local b = rs:FindFirstChild(BRIDGE_NAME)
	if not b or not b:IsA("RemoteEvent") then
		warn_tag("Bridge", "bridgeSend: remote not available")
		return false
	end
	log("Bridge", "-> Server: type=" .. tostring(payload.Type))
	local ok, err = pcall(b.FireServer, b, payload)
	if not ok then
		warn_tag("Bridge", "FireServer failed: " .. tostring(err))
		return false
	end
	return true
end

local function bridgeInvoke(payload)
	local fn = rs:FindFirstChild(BRIDGE_FN_NAME)
	if not fn or not fn:IsA("RemoteFunction") then
		warn_tag("Bridge", "bridgeInvoke: " .. BRIDGE_FN_NAME .. " not available")
		return nil
	end
	log("Bridge", "-> Invoke server: type=" .. tostring(payload.Type))
	local ok, result = pcall(fn.InvokeServer, fn, payload)
	if not ok then
		warn_tag("Bridge", "InvokeServer failed: " .. tostring(result))
		return nil
	end
	log("Bridge", "<- Invoke response received")
	return result
end

local function getServerScripts()
	local fn = rs:FindFirstChild(BRIDGE_LIST_NAME)
	if not fn or not fn:IsA("RemoteFunction") then
		warn_tag("Bridge", "getServerScripts: " .. BRIDGE_LIST_NAME .. " not available")
		return {}
	end
	log("Bridge", "-> Requesting server script list...")
	local ok, result = pcall(fn.InvokeServer, fn)
	if not ok then
		warn_tag("Bridge", "getServerScripts failed: " .. tostring(result))
		return {}
	end
	local count = type(result) == "table" and #result or 0
	log("Bridge", "<- Server returned " .. count .. " scripts")
	return result or {}
end

-- ============================================================
-- SERVER BRIDGE AUTO-INJECTION
-- Exploit context: we can inject a Script into ServerScriptService
-- using executor APIs (synapse/krnl support this via setscriptable
-- or by using the server-side loadstring if available).
-- We try multiple methods in order of reliability.
-- ============================================================

local SERVER_BRIDGE_URL = "https://raw.githubusercontent.com/FxckingAngel/Explore/refs/heads/main/SERVER_BRIDGE.lua"

-- Track pong so we know if server is already listening
-- Flags used by injection logic (declared here so onClientEvent can set them)
-- NOTE: onClientEvent() below handles Pong and ServerLog.

local function injectServerBridge()
	if serverBridgeInjected then return end
	serverBridgeInjected = true

	log("Bridge", "Fetching server bridge script...")
	local ok, src = pcall(game.HttpGet, game, SERVER_BRIDGE_URL)
	if not ok or type(src) ~= "string" or #src < 100 then
		warn_tag("Bridge", "Failed to fetch SERVER_BRIDGE.lua: " .. tostring(src))
		return
	end
	log("Bridge", "Server bridge fetched (" .. #src .. " bytes) - trying injection methods...")

	local injected = false
	local sss = game:GetService("ServerScriptService")

	-- ── Method 1: setscriptable + Source overwrite + Disabled toggle ──────────
	-- CONFIRMED WORKING on Solara:
	--   setscriptable(script, "Source", true) -> true true
	--   script.Source = src                   -> true nil
	-- We find any running server Script, save its original source,
	-- overwrite with bridge code, toggle Disabled to re-run it,
	-- then restore original source so the game keeps working.
	if not injected then
		-- Priority targets: simple top-level workspace scripts that are unlikely
		-- to break the game if briefly interrupted
		local priorityNames = {
			"StudioForce", "StudioXPGive", "StudioEventForce",
			"Script", "DiscordJoinRewardHandler", "LikeRewardHandler"
		}
		local targets = {}

		-- Try priority names first
		for _, name in pairs(priorityNames) do
			local s = workspace:FindFirstChild(name)
			if s and s:IsA("Script") and not s.Disabled then
				table.insert(targets, 1, s)
			end
		end

		-- Then any other workspace/SSS scripts as fallback
		for _, child in pairs(game:GetDescendants()) do
			if child:IsA("Script") and not child.Disabled
			and not child:IsDescendantOf(game:GetService("Players"))
			and not table.find(targets, child) then
				targets[#targets+1] = child
			end
		end

		for _, target in pairs(targets) do
			local targetPath = target:GetFullName()
			local ok, err = pcall(function()
				-- Make Source writable on original
				setscriptable(target, "Source", true)
				local originalSource = target.Source
				local originalParent = target.Parent

				-- Clone the script — clone starts fresh, inherits class
				local clone = target:Clone()
				setscriptable(clone, "Source", true)
				setscriptable(clone, "Disabled", true)

				-- Write bridge source to clone
				clone.Source = src
				clone.Name = target.Name .. "_DexBridge"
				clone.Disabled = true

				-- Parent clone to same location — Roblox executes it fresh on parent
				clone.Parent = originalParent
				clone.Disabled = false  -- trigger execution

				log("Bridge", "Clone parented and enabled at " .. originalParent:GetFullName())

				-- Restore original source of clone after bridge initialises
				task.delay(2, function()
					pcall(function()
						setscriptable(clone, "Source", true)
						clone.Source = originalSource
						clone.Name = target.Name
					end)
					log("Bridge", "Bridge clone source restored")
				end)
			end)

			if ok then
				log("Bridge", "Method 1 (clone+parent) ✓ via " .. targetPath)
				injected = true
				break
			else
				warn_tag("Bridge", "Method 1 failed on " .. targetPath .. ": " .. tostring(err))
			end
		end
	end

	-- ── Method 2: run_on_server variants (syn/execute_on_server/fluxus etc) ───
	if not injected then
		local serverRunFuncs = {
			rawget(_G, "run_on_server"),
			rawget(_G, "execute_on_server"),
			rawget(_G, "RunOnServer"),
			type(rawget(_G,"syn"))=="table"    and rawget(rawget(_G,"syn"),    "run_on_server") or nil,
			type(rawget(_G,"solara"))=="table"  and rawget(rawget(_G,"solara"), "run_on_server") or nil,
			type(rawget(_G,"fluxus"))=="table"  and rawget(rawget(_G,"fluxus"), "run_on_server") or nil,
			type(rawget(_G,"wave"))=="table"    and rawget(rawget(_G,"wave"),   "run_on_server") or nil,
			type(rawget(_G,"celery"))=="table"  and rawget(rawget(_G,"celery"), "run_on_server") or nil,
		}
		for i, fn in pairs(serverRunFuncs) do
			if not injected and type(fn) == "function" then
				local ok2, err = pcall(fn, src)
				if ok2 then
					log("Bridge", "Method 2 (run_on_server #"..i..") ✓")
					injected = true
				end
			end
		end
	end

	-- ── Method 3: getsenv ─────────────────────────────────────────────────────
	if not injected then
		local getsenv = rawget(_G,"getsenv") or rawget(_G,"getscriptenv")
		if type(getsenv) == "function" then
			for _, child in pairs(game:GetDescendants()) do
				if child:IsA("Script") and not child.Disabled
				and not child:IsDescendantOf(game:GetService("Players")) then
					local ok2, senv = pcall(getsenv, child)
					if ok2 and type(senv) == "table" then
						local ok3 = pcall(function()
							local fn = assert(loadstring(src, "DexBridge"))
							setfenv(fn, setmetatable({}, {__index=senv}))
							coroutine.wrap(fn)()
						end)
						if ok3 then
							log("Bridge", "Method 3 (getsenv) ✓ via " .. child:GetFullName())
							injected = true
							break
						end
					end
				end
			end
		end
	end

	if not injected then
		warn_tag("Bridge", "══════════════════════════════════════════════════")
		warn_tag("Bridge", "SERVER BRIDGE NOT INJECTED — edits are local only")
		warn_tag("Bridge", "══════════════════════════════════════════════════")
	end
end

-- Ping server first - if it responds within 3s it's already running
log("Bridge", "Pinging server to check if bridge is already running...")
bridgeSend({Type = "Ping", Client = plr.Name, Time = tick()})

coroutine.wrap(function()
	task.wait(3)
	if serverBridgeAlive then
		log("Bridge", "Server bridge already running - skipping injection ✓")
	else
		log("Bridge", "No pong received - server bridge not running, attempting injection...")
		injectServerBridge()

		-- Wait another 3s and ping again
		task.wait(3)
		bridgeSend({Type = "Ping", Client = plr.Name, Time = tick()})
		task.wait(2)
		if serverBridgeAlive then
			log("Bridge", "Server bridge injection successful - pong received ✓")
		else
			warn_tag("Bridge", "Server bridge still not responding after injection.")
			warn_tag("Bridge", "Your executor may not support server-side execution.")
			warn_tag("Bridge", "Edits will NOT sync to other players until server bridge is running.")
		end
	end
end)()

-- Store on Main for module access
Main.Bridge = {
	Send            = bridgeSend,
	Invoke          = bridgeInvoke,
	GetServerScripts = getServerScripts,
	StopKeepalive   = function() keepaliveActive = false log("Bridge","Keepalive stopped") end,
}

log("Bridge", "Bridge setup complete. Remotes: " ..
	BRIDGE_NAME .. "=" .. tostring(rs:FindFirstChild(BRIDGE_NAME) ~= nil) .. "  " ..
	BRIDGE_LIST_NAME .. "=" .. tostring(rs:FindFirstChild(BRIDGE_LIST_NAME) ~= nil) .. "  " ..
	BRIDGE_FN_NAME .. "=" .. tostring(rs:FindFirstChild(BRIDGE_FN_NAME) ~= nil)
)

-- ============================================================
-- 10. INIT ALL MODULES WITH FULL DEPS
-- ============================================================

deps.API = API
deps.RMD = RMD

log("Loader", "Running InitDeps for all modules...")
LibControl.InitDeps(deps)
ExplorerControl.InitDeps(deps)
PropertiesControl.InitDeps(deps)
SVControl.InitDeps(deps)
log("Loader", "InitDeps done")

log("Loader", "Running Main() for Explorer, Properties, ScriptViewer...")
local Explorer     = ExplorerControl.Main()
local Properties   = PropertiesControl.Main()
local ScriptViewer = SVControl.Main()

Apps.Explorer     = Explorer
Apps.Properties   = Properties
Apps.ScriptViewer = ScriptViewer

local appTable = {Explorer=Explorer, Properties=Properties, ScriptViewer=ScriptViewer}

log("Loader", "Running InitAfterMain for all modules...")
LibControl.InitAfterMain(appTable)
ExplorerControl.InitAfterMain(appTable)
PropertiesControl.InitAfterMain(appTable)
SVControl.InitAfterMain(appTable)
log("Loader", "InitAfterMain done")

-- ============================================================
-- 11. BUILD UI
-- ============================================================

log("UI", "Initializing window system...")
Lib.Window.Init()
log("UI", "Window system ready")

log("UI", "Initializing Explorer...")
Explorer.Init()
log("UI", "Explorer ready")

log("UI", "Initializing Properties...")
Properties.Init()
log("UI", "Properties ready")

log("UI", "Initializing ScriptViewer...")
local okSV, svErr = pcall(ScriptViewer.Init)
if not okSV then
	warn_tag("UI", "ScriptViewer.Init failed (non-fatal): " .. tostring(svErr))
else
	log("UI", "ScriptViewer ready")
end

-- Show Explorer + Properties docked right by default
log("UI", "Showing windows...")
Explorer.Window:Show({Align="right", Pos=1, Size=0.5, Silent=true})
Properties.Window:Show({Align="right", Pos=2, Size=0.5, Silent=true})

task.defer(function()
	Lib.Window.ToggleSide("right")
end)

-- ============================================================
-- 12. DONE
-- ============================================================

log("Loader", "=== Dex Ready === Player: " .. plr.Name)
log("Bridge", "Bridge status: Event=" .. tostring(bridge ~= nil) .. "  ListFn=" .. tostring(bridgeListFn ~= nil) .. "  Fn=" .. tostring(bridgeFn ~= nil))
log("Bridge", "DexBridge remote is alive — if edits aren't syncing, check SERVER_BRIDGE.lua is in ServerScriptService")
