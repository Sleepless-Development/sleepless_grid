local config = require 'config'
local utils = require 'shared.utils'
local bridge = require 'bridge.init'

local activeCells = {}

local currentCellX, currentCellY
local gridThreadRunning = false
local currentBufferSize = config.bufferSize
local fastBuffer = false
local replayPending = false
local serverTracked = false
local session = 0
local revision = 0
local syncing = false
local reloadPending = false

---@type table<string, number>
local cellBucket = {}
---@type table<string, number>
local cellRevision = {}

local gridTick
local syncCells

local function stateBucket(value)
	if type(value) ~= 'number' then return nil end
	return math.floor(value)
end

local function readRoutingBucket()
	local state = LocalPlayer.state
	local current = stateBucket(state.currentBucket)
	if current ~= nil then return current end
	local instance = stateBucket(state.instance)
	if instance ~= nil then return instance end
	return 0
end

local routingBucket = readRoutingBucket()

---@type table<string, fun(cellId: string, bucket: number)[]>
local cellLoadHandlers = {}
---@type table<string, fun(cellId: string, bucket: number)[]>
local cellUnloadHandlers = {}

local function dispatchHandlers(groups, cellId, kind, bucket)
	for _, handlers in pairs(groups) do
		for i = 1, #handlers do
			local ok, err = pcall(handlers[i], cellId, bucket)
			if not ok then
				lib.print.error(('[sleepless_grid] Handler error (%s): %s'):format(kind, err))
			end
		end
	end
end

local function dispatchCellLoad(cellId, bucket)
	dispatchHandlers(cellLoadHandlers, cellId, 'load', bucket)
end

local function dispatchCellUnload(cellId, bucket)
	dispatchHandlers(cellUnloadHandlers, cellId, 'unload', bucket)
end

local function hintServer()
	serverTracked = true
	TriggerServerEvent('Grid:Server:UpdatePlayer')
end

local function dropLocalSubscriptions()
	session = session + 1
	revision = revision + 1
	replayPending = false
	reloadPending = false
	fastBuffer = false

	local cellIds = {}
	for cellId in pairs(activeCells) do
		cellIds[#cellIds + 1] = cellId
	end

	for i = 1, #cellIds do
		local cellId = cellIds[i]
		dispatchCellUnload(cellId, cellBucket[cellId] or routingBucket)
		activeCells[cellId] = nil
		cellBucket[cellId] = nil
		cellRevision[cellId] = nil
	end

	currentCellX, currentCellY = nil, nil
	currentBufferSize = config.bufferSize

	if serverTracked or #cellIds > 0 then
		serverTracked = false
		TriggerServerEvent('Grid:Server:ClearPlayer')
	end
end

local function unloadActiveCells(previousBucket)
	local cellIds = {}
	for cellId in pairs(activeCells) do
		cellIds[#cellIds + 1] = cellId
	end

	local myRevision = revision
	for i = 1, #cellIds do
		if revision ~= myRevision then return end
		local cellId = cellIds[i]
		dispatchCellUnload(cellId, cellBucket[cellId] or previousBucket)
		if revision ~= myRevision then return end
		activeCells[cellId] = nil
		cellBucket[cellId] = nil
		cellRevision[cellId] = nil
	end

	if revision ~= myRevision then return end
	currentCellX, currentCellY = nil, nil
	currentBufferSize = config.bufferSize
	replayPending = false
end

local function abortSync()
	syncing = false
	if reloadPending and bridge.playerLoaded then
		reloadPending = false
		gridTick()
	end
	return false
end

---@param newCellX integer
---@param newCellY integer
---@param newBufferSize number
---@param replay boolean
---@return boolean
function syncCells(newCellX, newCellY, newBufferSize, replay)
	local syncRevision = revision
	local syncBucket = routingBucket
	syncing = true

	local newNearby = utils.getNearbyCells(newCellX, newCellY, newBufferSize)
	local newNearbySet = {}
	for i = 1, #newNearby do
		newNearbySet[newNearby[i]] = true
	end

	local leaving = {}
	for cellId in pairs(activeCells) do
		if not newNearbySet[cellId] then
			leaving[#leaving + 1] = cellId
		end
	end

	local left = 0
	for i = 1, #leaving do
		if revision ~= syncRevision then
			return abortSync()
		end

		local cellId = leaving[i]
		local loadedBucket = cellBucket[cellId] or syncBucket
		local owned = cellRevision[cellId]
		dispatchCellUnload(cellId, loadedBucket)
		if revision ~= syncRevision or cellRevision[cellId] ~= owned then
			return abortSync()
		end

		activeCells[cellId] = nil
		cellBucket[cellId] = nil
		cellRevision[cellId] = nil
		left = left + 1
	end

	local entered = 0
	for i = 1, #newNearby do
		if revision ~= syncRevision then
			return abortSync()
		end

		local cellId = newNearby[i]
		if not activeCells[cellId] then
			dispatchCellLoad(cellId, syncBucket)
			if revision ~= syncRevision then
				if cellRevision[cellId] ~= revision then
					dispatchCellUnload(cellId, syncBucket)
				end
				return abortSync()
			end

			activeCells[cellId] = true
			cellBucket[cellId] = syncBucket
			cellRevision[cellId] = syncRevision
			entered = entered + 1
		elseif replay then
			local loadedBucket = cellBucket[cellId] or syncBucket
			dispatchCellLoad(cellId, loadedBucket)
			if revision ~= syncRevision then
				if cellRevision[cellId] ~= revision then
					dispatchCellUnload(cellId, loadedBucket)
				end
				return abortSync()
			end
		end
	end

	if revision ~= syncRevision then
		return abortSync()
	end

	local bufferChanged = newBufferSize ~= currentBufferSize
	currentCellX, currentCellY = newCellX, newCellY
	currentBufferSize = newBufferSize
	syncing = false

	if entered > 0 or left > 0 then
		hintServer()
	end

	if config.debug and (entered > 0 or left > 0 or bufferChanged) then
		lib.print.info(('[sleepless_grid] cells +%s -%s buffer %s'):format(entered, left, newBufferSize))
	end

	return true
end

function gridTick()
	if not bridge.playerLoaded then return end

	local ped = cache.ped
	if not ped or ped == 0 then return end

	local coords = GetEntityCoords(ped)
	if not coords then return end

	local newBufferSize, nextFast = utils.resolveBufferSize(fastBuffer, GetEntitySpeed(ped))

	local newCellX, newCellY = utils.getCellFromCoords(coords)
	local cellChanged = newCellX ~= currentCellX or newCellY ~= currentCellY
	local bufferChanged = newBufferSize ~= currentBufferSize
	local replay = replayPending

	if not cellChanged and not bufferChanged and not replay then return end

	replayPending = false
	if syncCells(newCellX, newCellY, newBufferSize, replay) then
		fastBuffer = nextFast
	end
end

local function applyRoutingBucket(value)
	if type(value) ~= 'number' then return end
	local newBucket = math.floor(value)
	if newBucket == routingBucket then return end

	local previous = routingBucket
	revision = revision + 1
	local myRevision = revision
	routingBucket = newBucket

	if bridge.playerLoaded then
		unloadActiveCells(previous)
	end

	if revision ~= myRevision then return end

	if serverTracked then
		hintServer()
	end

	if not bridge.playerLoaded then return end

	if syncing then
		reloadPending = true
		return
	end

	gridTick()
end

local function startGridThread()
	if gridThreadRunning or not bridge.playerLoaded then return end

	gridThreadRunning = true
	local mySession = session

	CreateThread(function()
		while bridge.playerLoaded and mySession == session do
			Wait(config.checkInterval)

			if not bridge.playerLoaded or mySession ~= session then break end
			gridTick()
		end

		if mySession == session and not bridge.playerLoaded then
			dropLocalSubscriptions()
		end

		gridThreadRunning = false

		if bridge.playerLoaded then
			startGridThread()
		end
	end)
end

CreateThread(startGridThread)

AddEventHandler('sleepless_grid:playerLoaded', function()
	startGridThread()
end)

AddEventHandler('sleepless_grid:playerUnloaded', function()
	dropLocalSubscriptions()
end)

local routingBag = ('player:%s'):format(cache.serverId)

local function onRoutingState(_, _, value)
	if type(value) ~= 'number' then return end
	applyRoutingBucket(value)
end

AddStateBagChangeHandler('currentBucket', routingBag, onRoutingState)
AddStateBagChangeHandler('instance', routingBag, onRoutingState)

local function registerCellHandler(onLoad, onUnload)
	local resource = GetInvokingResource() or cache.resource
	if onLoad then
		cellLoadHandlers[resource] = cellLoadHandlers[resource] or {}
		cellLoadHandlers[resource][#cellLoadHandlers[resource] + 1] = onLoad
	end
	if onUnload then
		cellUnloadHandlers[resource] = cellUnloadHandlers[resource] or {}
		cellUnloadHandlers[resource][#cellUnloadHandlers[resource] + 1] = onUnload
	end
end
exports('RegisterCellHandler', registerCellHandler)

AddEventHandler('onResourceStop', function(resource)
	cellLoadHandlers[resource] = nil
	cellUnloadHandlers[resource] = nil
end)

local export = exports.sleepless_grid

local function call(self, index, ...)
	local function method(...)
		return export[index](nil, ...)
	end

	if not ... then
		self[index] = method
	end

	return method
end

local grid = setmetatable({
	name = 'sleepless_grid',
}, {
	__index = call,
	__newindex = function(self, key, fn)
		rawset(self, key, fn)

		if debug.getinfo(2, 'S').short_src:find('@sleepless_grid') then
			exports(key, fn)
		end
	end
})

---@return table<CellId, true>
function grid.getActiveCells()
	return activeCells
end

---@return number
function grid.getCurrentBufferSize()
	return currentBufferSize
end

---@param coords vector3
---@return string
function grid.getCellIdFromCoords(coords)
	local x, y = utils.getCellFromCoords(coords)
	return utils.makeCellId(x, y)
end

---@param cellId CellId | vector3
---@return vector3?
function grid.getCellCenter(cellId)
	if type(cellId) == 'vector3' then
		cellId = grid.getCellIdFromCoords(cellId)
	end

	if type(cellId) ~= 'string' then return nil end

	local x, y = utils.parseCellId(cellId)
	if not x or not y then return nil end

	return vector3((x + 0.5) * config.cellSize, (y + 0.5) * config.cellSize, 0.0)
end

---@param cellId CellId
---@return integer? x
---@return integer? y
function grid.parseCellId(cellId)
	if type(cellId) ~= 'string' then return nil end
	return utils.parseCellId(cellId)
end

---@param cellX integer
---@param cellY integer
---@param buffer? integer
---@return CellIds
function grid.getNearbyCells(cellX, cellY, buffer)
	return utils.getNearbyCells(cellX, cellY, buffer or config.bufferSize)
end

---@return integer
function grid.getBufferSize()
	return config.bufferSize
end

---@return number bucket
---@return string | nil bucketName
function grid.getRoutingBucket()
	local name = LocalPlayer.state.currentBucketName
	if type(name) ~= 'string' or name == '' then
		name = nil
	end

	return routingBucket, name
end

function grid.refreshCells()
	replayPending = true
end
