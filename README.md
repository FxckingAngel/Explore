# Dex Explorer — FxckingAngel/Explore

## Quick Start

**Client (executor):**
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/refs/heads/main/loader.lua"))()
```

**Server (for live edits to apply in-game):**
1. Get `SERVER_BRIDGE.lua` from this repo
2. Paste it into a **Script** in **ServerScriptService**
3. Run the game

---

## How Live Edits Work

| Action | What fires to server |
|--------|---------------------|
| Change any property | `PropertiesLiveEdit` with serialized value |
| Delete instance | `ExplorerLiveEdit Delete` |
| Rename instance | `ExplorerLiveEdit Rename` with NewName |
| Drag to reparent | `ExplorerLiveEdit Reparent` with NewParentPath |
| Cut instance | `ExplorerLiveEdit Delete` |

All changes print `[DexBridge] ->` on the client and `[DexServer]` on the server.
Server sends `[OK]` or `[Error]` back and it prints on your client console.

## Remotes (auto-created by client in ReplicatedStorage)

| Name | Type | Purpose |
|------|------|---------|
| `DexBridge` | RemoteEvent | All live edit events |
| `DexBridgeList` | RemoteFunction | Get server script list |
| `DexBridgeFn` | RemoteFunction | GetSource / SetProperty / CallMethod |
