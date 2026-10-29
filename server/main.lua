local utils = require 'shared.utils'
local config = require 'config'
local routing = require 'bridge.routing.server'

---@type table<number, table<string, table<number, true>>>
local subscribers = {}

---@type table<number, table<string, table<number, true>>>
local occupants = {}

---@type table<number, table<string, true>>
local playerSubscriptions = {}

---@type table<number, number>
local playerBucket = {}

---@type table<number, { bucket: number, cellId: string }>
local playerOccupancy = {}

---@type table<number, true>
local trackedPlayers = {}

---@type table<number, number>
local lastReconcile = {}

---@type table<number, boolean>
local fastBuffer = {}

---@type table<number, number>
local playerEpoch = {}

---@type table<number, true>
local inflight = {}

---@type table<number, true>
local dirty = {}

local esxObject

local function resourceStarted(name)
	local state = GetResourceState(name)
	return state == 'started' or state == 'starting'
end

local function isCharacterLoggedIn(playerId)
	if resourceStarted('qbx_core') then
		local ok, player = pcall(function()
			return exports.qbx_core:GetPlayer(playerId)
		end)
		if ok then return player ~= nil end
	end

	if resourceStarted('qb-core') then
		local ok, player = pcall(function()
			local core = exports['qb-core']:GetCoreObject()
			return core.Functions.GetPlayer(playerId)
		end)
		if ok then return player ~= nil end
	end

	if resourceStarted('es_extended') then
		local ok, player = pcall(function()
			if not esxObject then
				esxObject = exports.es_extended:getSharedObject()
			end
			return esxObject.GetPlayerFromId(playerId)
		end)
		if ok then return player ~= nil end
	end

	if resourceStarted('ox_core') then
		local ok, player = pcall(function()
			return exports.ox_core:GetPlayer(playerId)
		end)
		if ok then return player ~= nil end
	end

	return GetPlayerName(playerId) ~= nil
end

local function liveBucket(playerId)
	if not GetPlayerName(playerId) then return nil end

	local ok, bucket = pcall(GetPlayerRoutingBucket, playerId)
	if not ok or type(bucket) ~= 'number' then return nil end
	return math.floor(bucket)
end

local function epochCurrent(playerId, epoch, bucket)
	return (playerEpoch[playerId] or 0) == epoch
		and liveBucket(playerId) == bucket
		and isCharacterLoggedIn(playerId)
end

---@type table<string, fun(playerId: number, cellId: string, bucket: number)[]>
local cellLoadHandlers = {}
---@type table<string, fun(playerId: number, cellId: string, bucket: number)[]>
local cellUnloadHandlers = {}

---@param eventName string
---@param targetIds number | ArrayLike<number>
---@param bps number
local function triggerLatentClientEvent(eventName, targetIds, bps, ...)
	local payload = msgpack.pack_args(...)
	local payloadLen = #payload

	if lib.array.isArray(targetIds) then
		for i = 1, #targetIds do
			TriggerLatentClientEventInternal(eventName, targetIds[i] --[[@as string]], payload, payloadLen, bps)
		end

		return
	end

	TriggerLatentClientEventInternal(eventName, targetIds --[[@as string]], payload, payloadLen, bps)
end

local function updateInterval()
	local interval = math.floor(tonumber(config.checkInterval) or 500)
	if interval < 250 then
		interval = 250
	end
	return interval
end

local function normalizePlayerId(playerId)
	playerId = tonumber(playerId)
	if not playerId or playerId <= 0 then return nil end
	return math.floor(playerId)
end

local function namedBucket(bucket)
	if type(bucket) ~= 'string' or bucket == '' then return nil end
	return routing.resolveName(bucket)
end

local function resolveQueryBucket(bucket)
	if bucket == nil then return 0 end
	if type(bucket) == 'number' then return math.floor(bucket) end
	return namedBucket(bucket)
end

local function canonicalCellId(cellId)
	if type(cellId) == 'vector3' then
		local x, y = utils.getCellFromCoords(cellId)
		return utils.makeCellId(x, y)
	end

	if type(cellId) ~= 'string' then return nil end
	local x, y = utils.parseCellId(cellId)
	if not x or not y then return nil end
	return cellId
end

---@param groups table<string, function[]>
---@param kind 'load' | 'unload'
---@param playerId number
---@param cellId string
---@param bucket number
local function dispatchHandlers(groups, kind, playerId, cellId, bucket)
	for resource, handlers in pairs(groups) do
		for i = 1, #handlers do
			local ok, err = pcall(handlers[i], playerId, cellId, bucket)
			if not ok then
				lib.print.error(('[sleepless_grid] Handler error in %s (%s): %s'):format(resource, kind, err))
			end
		end
	end
end

local function stillSubscribed(playerId, bucket, cellId)
	local subs = playerSubscriptions[playerId]
	return subs ~= nil and subs[cellId] == true and playerBucket[playerId] == bucket
end

---@param playerId number
---@param bucket number
---@param cellId string
---@param epoch? number
---@return boolean | 'abort'
local function removeSubscription(playerId, bucket, cellId, epoch)
	local byCell = subscribers[bucket]
	local members = byCell and byCell[cellId]
	if not members or not members[playerId] then return false end

	members[playerId] = nil
	if not next(members) then
		byCell[cellId] = nil
		if not next(byCell) then
			subscribers[bucket] = nil
		end
	end

	local subs = playerSubscriptions[playerId]
	if subs then
		subs[cellId] = nil
		if not next(subs) then
			playerSubscriptions[playerId] = nil
			playerBucket[playerId] = nil
		end
	end

	dispatchHandlers(cellUnloadHandlers, 'unload', playerId, cellId, bucket)

	if epoch and (playerEpoch[playerId] or 0) ~= epoch then
		return 'abort'
	end
	return true
end

---@param playerId number
---@param bucket number
---@param cellId string
---@param epoch number
---@return boolean | 'abort'
local function addSubscription(playerId, bucket, cellId, epoch)
	if (playerEpoch[playerId] or 0) ~= epoch then return 'abort' end
	if stillSubscribed(playerId, bucket, cellId) then return false end

	dispatchHandlers(cellLoadHandlers, 'load', playerId, cellId, bucket)

	local current = epochCurrent(playerId, epoch, bucket)

	if not current then
		if not stillSubscribed(playerId, bucket, cellId) then
			dispatchHandlers(cellUnloadHandlers, 'unload', playerId, cellId, bucket)
		end
		return 'abort'
	end

	subscribers[bucket] = subscribers[bucket] or {}
	subscribers[bucket][cellId] = subscribers[bucket][cellId] or {}
	subscribers[bucket][cellId][playerId] = true

	playerSubscriptions[playerId] = playerSubscriptions[playerId] or {}
	playerSubscriptions[playerId][cellId] = true
	playerBucket[playerId] = bucket
	return true
end

local function clearSubscriptions(playerId)
	local bucket = playerBucket[playerId]
	local subs = playerSubscriptions[playerId]
	if not subs or bucket == nil then
		playerSubscriptions[playerId] = nil
		playerBucket[playerId] = nil
		return 0
	end

	local cellIds = {}
	for cellId in pairs(subs) do
		cellIds[#cellIds + 1] = cellId
	end

	local removed = 0
	for i = 1, #cellIds do
		if removeSubscription(playerId, bucket, cellIds[i]) == true then
			removed = removed + 1
		end
	end
	return removed
end

local function clearOccupant(playerId)
	local current = playerOccupancy[playerId]
	if not current then return end

	local byCell = occupants[current.bucket]
	local members = byCell and byCell[current.cellId]
	if members then
		members[playerId] = nil
		if not next(members) then
			byCell[current.cellId] = nil
			if not next(byCell) then
				occupants[current.bucket] = nil
			end
		end
	end

	playerOccupancy[playerId] = nil
end

local function setOccupant(playerId, bucket, cellId)
	local current = playerOccupancy[playerId]
	if current and current.bucket == bucket and current.cellId == cellId then
		return false
	end

	clearOccupant(playerId)

	occupants[bucket] = occupants[bucket] or {}
	occupants[bucket][cellId] = occupants[bucket][cellId] or {}
	occupants[bucket][cellId][playerId] = true
	playerOccupancy[playerId] = { bucket = bucket, cellId = cellId }
	return true
end

local function releasePlayer(playerId)
	playerId = normalizePlayerId(playerId)
	if not playerId then return end

	playerEpoch[playerId] = (playerEpoch[playerId] or 0) + 1
	clearSubscriptions(playerId)
	clearOccupant(playerId)
	trackedPlayers[playerId] = nil
	fastBuffer[playerId] = nil
	dirty[playerId] = nil
end

local function reconcilePlayer(playerId, depth)
	depth = depth or 0
	playerId = normalizePlayerId(playerId)
	if not playerId then return end

	if not GetPlayerName(playerId) or not isCharacterLoggedIn(playerId) then
		releasePlayer(playerId)
		return
	end

	local bucket = liveBucket(playerId)
	if bucket == nil then
		releasePlayer(playerId)
		return
	end

	if inflight[playerId] then return end

	local now = GetGameTimer()
	local last = lastReconcile[playerId]
	local bucketStale = playerBucket[playerId] ~= nil and playerBucket[playerId] ~= bucket
	local throttled = last and (now - last) < updateInterval()
	if throttled and not bucketStale and not dirty[playerId] then
		return
	end

	local ped = GetPlayerPed(playerId)
	if not ped or ped == 0 then
		lastReconcile[playerId] = now
		return
	end

	local coords = GetEntityCoords(ped)
	if not coords then
		lastReconcile[playerId] = now
		return
	end

	lastReconcile[playerId] = now
	dirty[playerId] = nil

	local epoch = playerEpoch[playerId] or 0
	inflight[playerId] = true

	local cellX, cellY = utils.getCellFromCoords(coords)
	local cellId = utils.makeCellId(cellX, cellY)
	local wasFast = fastBuffer[playerId] == true
	local bufferSize, isFast = utils.resolveBufferSize(wasFast, GetEntitySpeed(ped))
	local aborted = false

	if playerBucket[playerId] ~= nil and playerBucket[playerId] ~= bucket then
		clearSubscriptions(playerId)
		if not epochCurrent(playerId, epoch, bucket) then
			aborted = true
		end
	end

	if not aborted and not epochCurrent(playerId, epoch, bucket) then
		aborted = true
	end

	if not aborted then
		setOccupant(playerId, bucket, cellId)
	end

	local added, removed = 0, 0
	if not aborted then
		local expected = {}
		local nearby = utils.getNearbyCells(cellX, cellY, bufferSize)
		for i = 1, #nearby do
			expected[nearby[i]] = true
		end

		local current = playerSubscriptions[playerId]
		if current then
			local stale = {}
			for subscribedCell in pairs(current) do
				if not expected[subscribedCell] then
					stale[#stale + 1] = subscribedCell
				end
			end
			for i = 1, #stale do
				local result = removeSubscription(playerId, bucket, stale[i], epoch)
				if result == 'abort' then
					aborted = true
					break
				elseif result == true then
					removed = removed + 1
				end
			end
		end

		if not aborted then
			for i = 1, #nearby do
				local result = addSubscription(playerId, bucket, nearby[i], epoch)
				if result == 'abort' then
					aborted = true
					break
				elseif result == true then
					added = added + 1
				end
			end
		end
	end

	inflight[playerId] = nil

	local epochNow = playerEpoch[playerId] or 0

	if not aborted and epochNow == epoch then
		fastBuffer[playerId] = isFast
		if config.debug and (added > 0 or removed > 0 or wasFast ~= isFast) then
			lib.print.info(('[sleepless_grid] %s bucket %s cell %s subs +%s -%s buffer %s'):format(
				playerId, bucket, cellId, added, removed, bufferSize
			))
		end
	elseif trackedPlayers[playerId] and epochNow == epoch then
		dirty[playerId] = true
	end

	if dirty[playerId] and trackedPlayers[playerId] and epochNow == epoch and depth < 1 then
		reconcilePlayer(playerId, depth + 1)
	end
end

RegisterNetEvent('Grid:Server:UpdatePlayer', function()
	local playerId = normalizePlayerId(source)
	if not playerId then return end

	if not GetPlayerName(playerId) or not isCharacterLoggedIn(playerId) then
		releasePlayer(playerId)
		return
	end

	trackedPlayers[playerId] = true
	if inflight[playerId] then
		dirty[playerId] = true
		return
	end

	reconcilePlayer(playerId)
end)

RegisterNetEvent('Grid:Server:ClearPlayer', function()
	local playerId = normalizePlayerId(source)
	if not playerId then return end

	if GetPlayerName(playerId) and isCharacterLoggedIn(playerId) then
		return
	end

	releasePlayer(playerId)
end)

AddEventHandler('playerDropped', function()
	releasePlayer(source)
end)

AddEventHandler('onPlayerBucketChange', function(playerId)
	playerId = normalizePlayerId(playerId)
	if not playerId then return end
	if not trackedPlayers[playerId] and not playerOccupancy[playerId] and not playerSubscriptions[playerId] then
		return
	end

	reconcilePlayer(playerId)
end)

CreateThread(function()
	while true do
		Wait(updateInterval())

		for playerId in pairs(trackedPlayers) do
			reconcilePlayer(playerId)
		end
	end
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

---@param onLoad? fun(playerId: number, cellId: string, bucket: number)
---@param onUnload? fun(playerId: number, cellId: string, bucket: number)
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

---@param resource string
---@param playerId number
local function replayPlayerCellsForResource(resource, playerId)
	local handlers = cellLoadHandlers[resource]
	local subs = playerSubscriptions[playerId]
	local bucket = playerBucket[playerId]
	if not handlers or not subs or bucket == nil then return end

	for cellId in pairs(subs) do
		for i = 1, #handlers do
			local ok, err = pcall(handlers[i], playerId, cellId, bucket)
			if not ok then
				lib.print.error(('[sleepless_grid] Handler error in %s (replay): %s'):format(resource, err))
			end
		end
	end
end

---@param resource? string
---@param playerId? number
local function replayActiveCells(resource, playerId)
	resource = resource or GetInvokingResource() or cache.resource

	if playerId then
		playerId = normalizePlayerId(playerId)
		if not playerId then return end
		replayPlayerCellsForResource(resource, playerId)
		return
	end

	local players = GetPlayers()

	for i = 1, #players do
		local replayPlayerId = tonumber(players[i])

		if replayPlayerId then
			replayPlayerCellsForResource(resource, replayPlayerId)
		end
	end
end
exports('ReplayActiveCells', replayActiveCells)

local function removeResourceHandlers(resource)
	if cellLoadHandlers[resource] then
		cellLoadHandlers[resource] = nil
	end
	if cellUnloadHandlers[resource] then
		cellUnloadHandlers[resource] = nil
	end
end

AddEventHandler('onResourceStop', function(resource)
	removeResourceHandlers(resource)
end)

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

local function playersInCells(cellIds, bucket, index)
	local playerSet = {}
	local byBucket = index[bucket]

	for i = 1, #cellIds do
		local members = byBucket and byBucket[cellIds[i]]
		if members then
			for playerId in pairs(members) do
				if liveBucket(playerId) == bucket then
					playerSet[playerId] = true
				end
			end
		end
	end

	return utils.getTableKeys(playerSet)
end

local function cellsForQuery(cellId, includeBuffer)
	cellId = canonicalCellId(cellId)
	if not cellId then return nil end

	if not includeBuffer then
		return { cellId }
	end

	local x, y = utils.parseCellId(cellId)
	if not x or not y then return nil end

	local buffer = math.floor(tonumber(config.bufferSize) or 0)
	if buffer < 0 then buffer = 0 end
	return utils.getNearbyCells(x, y, buffer)
end

---@param cellId CellId | vector3
---@param includeBuffer? boolean | string
---@param bucket? number | string
---@return number[]
function grid.getPlayersFromCell(cellId, includeBuffer, bucket)
	if type(includeBuffer) == 'string' then
		bucket = includeBuffer
		includeBuffer = false
	end

	local resolved = resolveQueryBucket(bucket)
	if resolved == nil then return {} end

	local cellIds = cellsForQuery(cellId, includeBuffer)
	if not cellIds then return {} end
	return playersInCells(cellIds, resolved, occupants)
end

---@param cellId CellId | vector3
---@param bucket? number | string
---@return number[]
function grid.getSubscribersFromCell(cellId, bucket)
	local resolved = resolveQueryBucket(bucket)
	if resolved == nil then return {} end

	local cellIds = cellsForQuery(cellId, false)
	if not cellIds then return {} end
	return playersInCells(cellIds, resolved, subscribers)
end

---@param bucket number | string
---@return string | nil
function grid.getBucketName(bucket)
	local bucketId = bucket
	if type(bucket) == 'string' then
		bucketId = routing.resolveName(bucket)
	end

	if type(bucketId) ~= 'number' then
		return nil
	end

	return routing.getName(bucketId)
end

---@param coords vector3
---@return CellId
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

---@return number? bucket
---@return string? event
---@return integer skip
local function splitBroadcast(eventOrBucket, ...)
	if type(eventOrBucket) == 'number' then
		local event = select(1, ...)
		if type(event) ~= 'string' or event == '' then return nil end
		return math.floor(eventOrBucket), event, 2
	end

	if type(eventOrBucket) ~= 'string' or eventOrBucket == '' then return nil end

	local nextArg = select(1, ...)
	if type(nextArg) == 'string' and nextArg ~= '' then
		local named = namedBucket(eventOrBucket)
		if named ~= nil then
			return named, nextArg, 2
		end
	end

	return 0, eventOrBucket, 1
end

---@return number? bucket
---@return string? event
---@return number? bps
---@return integer? skip
local function splitLatent(eventOrBucket, ...)
	if type(eventOrBucket) == 'number' and type(select(1, ...)) == 'string' then
		return math.floor(eventOrBucket), select(1, ...), select(2, ...), 3
	end

	if type(eventOrBucket) ~= 'string' or eventOrBucket == '' then return nil end

	local maybeEvent = select(1, ...)
	local maybeBps = select(2, ...)
	if type(maybeEvent) == 'string' and maybeEvent ~= '' and type(maybeBps) == 'number' then
		local named = namedBucket(eventOrBucket)
		if named ~= nil then
			return named, maybeEvent, maybeBps, 3
		end
	end

	return 0, eventOrBucket, select(1, ...), 2
end

---@param cellId CellId | vector3
---@param eventOrBucket string | number
function grid.triggerClientEventForCell(cellId, eventOrBucket, ...)
	local bucket, event, skip = splitBroadcast(eventOrBucket, ...)
	if not event then return end

	local players = grid.getPlayersFromCell(cellId, false, bucket)
	if #players == 0 then return end

	if skip == 1 then
		lib.triggerClientEvent(event, players, ...)
		return
	end

	lib.triggerClientEvent(event, players, select(2, ...))
end

---@param cellId CellId | vector3
---@param eventOrBucket string | number
function grid.triggerLatentClientEventForCell(cellId, eventOrBucket, ...)
	local bucket, event, bps, payloadSkip = splitLatent(eventOrBucket, ...)
	if not event or type(bps) ~= 'number' then return end

	local players = grid.getPlayersFromCell(cellId, false, bucket)
	if #players == 0 then return end

	if payloadSkip == 2 then
		triggerLatentClientEvent(event, players, bps, select(2, ...))
		return
	end

	triggerLatentClientEvent(event, players, bps, select(3, ...))
end

---@param cellId CellId | vector3
---@param eventOrBucket string | number
function grid.triggerClientEventForCellAndBuffer(cellId, eventOrBucket, ...)
	local bucket, event, skip = splitBroadcast(eventOrBucket, ...)
	if not event then return end

	local players = grid.getPlayersFromCell(cellId, true, bucket)
	if #players == 0 then return end

	if skip == 1 then
		lib.triggerClientEvent(event, players, ...)
		return
	end

	lib.triggerClientEvent(event, players, select(2, ...))
end

---@param cellId CellId | vector3
---@param eventOrBucket string | number
function grid.triggerLatentClientEventForCellAndBuffer(cellId, eventOrBucket, ...)
	local bucket, event, bps, payloadSkip = splitLatent(eventOrBucket, ...)
	if not event or type(bps) ~= 'number' then return end

	local players = grid.getPlayersFromCell(cellId, true, bucket)
	if #players == 0 then return end

	if payloadSkip == 2 then
		triggerLatentClientEvent(event, players, bps, select(2, ...))
		return
	end

	triggerLatentClientEvent(event, players, bps, select(3, ...))
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
