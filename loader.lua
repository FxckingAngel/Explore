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
local BRIDGE_NAME      = "DexBridge"
local BRIDGE_LIST_NAME = "DexBridgeList"
local BRIDGE_FN_NAME   = "DexBridgeFn"

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
-- ============================================================

local rs = service.ReplicatedStorage
log("Bridge", "Setting up client<->server bridge...")

-- RemoteEvent: fire-and-forget messages to/from server
local bridge = rs:FindFirstChild(BRIDGE_NAME)
if bridge then
	log("Bridge", "RemoteEvent '" .. BRIDGE_NAME .. "' already exists")
else
	-- Client can't create RemoteEvents on server — wait briefly for server script to create it
	log("Bridge", "Waiting for server to create '" .. BRIDGE_NAME .. "' (up to 5s)...")
	local waited = 0
	while not bridge and waited < 5 do
		bridge = rs:FindFirstChild(BRIDGE_NAME)
		if not bridge then
			task.wait(0.5)
			waited = waited + 0.5
		end
	end
	if bridge then
		log("Bridge", "Server created '" .. BRIDGE_NAME .. "' after " .. waited .. "s ✓")
	else
		warn_tag("Bridge", "'" .. BRIDGE_NAME .. "' not found after 5s — server bridge script may not be running. Some features disabled.")
	end
end

-- RemoteFunction: request/response (e.g. listing server scripts)
local bridgeListFn = rs:FindFirstChild(BRIDGE_LIST_NAME)
if bridgeListFn then
	log("Bridge", "RemoteFunction '" .. BRIDGE_LIST_NAME .. "' found ✓")
else
	warn_tag("Bridge", "'" .. BRIDGE_LIST_NAME .. "' not found — server-side script listing disabled")
end

-- RemoteFunction: generic invoke (property set, script source push etc)
local bridgeFn = rs:FindFirstChild(BRIDGE_FN_NAME)
if bridgeFn then
	log("Bridge", "RemoteFunction '" .. BRIDGE_FN_NAME .. "' found ✓")
else
	warn_tag("Bridge", "'" .. BRIDGE_FN_NAME .. "' not found — server invoke disabled")
end

-- Listen for server → client messages
if bridge and bridge:IsA("RemoteEvent") then
	bridge.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			warn_tag("Bridge", "Received non-table payload from server: " .. type(payload))
			return
		end
		log("Bridge", "← Server event received: type=" .. tostring(payload.Type))

		if payload.Type == "ServerLog" then
			-- Server pushed a log message to show in console
			print(("[DexBridge][Server] %s"):format(tostring(payload.Message)))

		elseif payload.Type == "ScriptSourcePush" then
			-- Server pushed updated source for a script (e.g. after another admin edited it)
			log("Bridge", "Script source push from server: " .. tostring(payload.Path))
			-- ScriptViewer can pick this up if open

		elseif payload.Type == "Ping" then
			log("Bridge", "← Ping from server, sending pong...")
			bridge:FireServer({Type="Pong", Time=tick()})
		else
			log("Bridge", "Unknown server payload type: " .. tostring(payload.Type))
		end
	end)
	log("Bridge", "OnClientEvent listener registered ✓")
end

-- Helper: send payload to server
local function bridgeSend(payload)
	if not bridge or not bridge:IsA("RemoteEvent") then
		warn_tag("Bridge", "bridgeSend called but bridge not available")
		return false
	end
	log("Bridge", "→ Sending to server: type=" .. tostring(payload.Type))
	local ok, err = pcall(bridge.FireServer, bridge, payload)
	if not ok then
		warn_tag("Bridge", "FireServer failed: " .. tostring(err))
		return false
	end
	return true
end

-- Helper: invoke server and get response
local function bridgeInvoke(payload)
	if not bridgeFn or not bridgeFn:IsA("RemoteFunction") then
		warn_tag("Bridge", "bridgeInvoke called but '" .. BRIDGE_FN_NAME .. "' not available")
		return nil
	end
	log("Bridge", "→ Invoking server: type=" .. tostring(payload.Type))
	local ok, result = pcall(bridgeFn.InvokeServer, bridgeFn, payload)
	if not ok then
		warn_tag("Bridge", "InvokeServer failed: " .. tostring(result))
		return nil
	end
	log("Bridge", "← Server invoke response received")
	return result
end

-- Helper: get server script list
local function getServerScripts()
	if not bridgeListFn or not bridgeListFn:IsA("RemoteFunction") then
		warn_tag("Bridge", "getServerScripts: '" .. BRIDGE_LIST_NAME .. "' not available")
		return {}
	end
	log("Bridge", "→ Requesting server script list...")
	local ok, result = pcall(bridgeListFn.InvokeServer, bridgeListFn)
	if not ok then
		warn_tag("Bridge", "getServerScripts failed: " .. tostring(result))
		return {}
	end
	local count = type(result) == "table" and #result or 0
	log("Bridge", "← Server returned " .. count .. " scripts")
	return result or {}
end

-- Send initial ping to confirm bridge is alive
if bridge and bridge:IsA("RemoteEvent") then
	log("Bridge", "→ Sending initial ping to server...")
	bridgeSend({Type = "Ping", Client = plr.Name, Time = tick()})
end

-- Store bridge helpers on Main so modules can access them
Main.Bridge = {
	Send = bridgeSend,
	Invoke = bridgeInvoke,
	GetServerScripts = getServerScripts,
	Event = bridge,
	ListFn = bridgeListFn,
	Fn = bridgeFn,
}
log("Bridge", "Bridge setup complete")

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
