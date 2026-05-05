--[[
	FindDeflectRemote — hooks ALL outgoing network calls
	Run this, then manually deflect the ball successfully
	Share what prints right when you deflect
]]

local oldFireServer = RemoteEvent.FireServer
local oldInvoke = RemoteFunction.InvokeServer

local log = {}
local lastPrint = 0

-- Hook RemoteEvent:FireServer
hookfunction(oldFireServer, newcclosure(function(self, ...)
	local args = {...}
	local now = tick()
	local line = "[EVENT] "..self:GetFullName()
	for i,v in pairs(args) do
		line = line.." |"..tostring(v):sub(1,30)
	end
	table.insert(log, {t=now, s=line})
	if now - lastPrint > 0.01 then
		lastPrint = now
	end
	print(line)
	return oldFireServer(self, ...)
end))

-- Hook RemoteFunction:InvokeServer
hookfunction(oldInvoke, newcclosure(function(self, ...)
	local args = {...}
	local line = "[FUNC] "..self:GetFullName()
	for i,v in pairs(args) do
		line = line.." |"..tostring(v):sub(1,30)
	end
	print(line)
	return oldInvoke(self, ...)
end))

print("Monitoring ALL remotes - manually deflect the ball and share what prints")
print("Look for anything that fires ONLY when you successfully deflect")
