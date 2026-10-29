---@meta

---@alias CellId string
---@alias CellIds CellId[]

--- Exports

exports.sleepless_grid = {}

---`server`
---Gets players physically standing in a cell.
---This is occupancy for one routing bucket, not the players streaming that cell.
---Players whose live routing bucket no longer matches are omitted.
---@param cellId CellId | vector3
---@param includeBuffer? boolean When true, include players standing in the surrounding buffer once
---@param bucket? number | string Routing bucket id, or a sleepless_routing bucket name. Defaults to 0. An unknown name matches nobody
---@return number[] playerIds
function exports.sleepless_grid:getPlayersFromCell(cellId, includeBuffer, bucket) end

---`server`
---Gets players streaming a cell.
---Subscriptions already cover the player's neighborhood, so the result is not expanded again.
---Players whose live routing bucket no longer matches are omitted.
---@param cellId CellId | vector3
---@param bucket? number | string Routing bucket id, or a sleepless_routing bucket name. Defaults to 0. An unknown name matches nobody
---@return number[] playerIds
function exports.sleepless_grid:getSubscribersFromCell(cellId, bucket) end

---`client|server`
---Gets the cell id that contains the provided coordinates
---@param coords vector3
---@return CellId
function exports.sleepless_grid:getCellIdFromCoords(coords) end

---`client|server`
---Gets the coordinates at the center of the provided grid cell
---@param cellId CellId | vector3
---@return vector3
function exports.sleepless_grid:getCellCenter(cellId) end

---`server`
---Triggers an event for players physically standing in the grid cell.
---For another routing bucket, pass it before the event name:
---`triggerClientEventForCell(cellId, bucket, event, ...)`.
---The bucket defaults to 0, the global world. A sleepless_routing bucket name
---is accepted in that slot when the name is registered.
---@param cellId CellId | vector3
---@param event string
---@param ... any
---@overload fun(cellId: CellId | vector3, bucket: number | string, event: string, ...: any)
function exports.sleepless_grid:triggerClientEventForCell(cellId, event, ...) end

---`server`
---Triggers an event for players physically standing in the grid cell and one surrounding buffer ring.
---For another routing bucket, pass it before the event name:
---`triggerClientEventForCellAndBuffer(cellId, bucket, event, ...)`.
---A sleepless_routing bucket name is accepted in the bucket slot when the name is registered.
---@param cellId CellId | vector3
---@param event string
---@param ... any
---@overload fun(cellId: CellId | vector3, bucket: number | string, event: string, ...: any)
function exports.sleepless_grid:triggerClientEventForCellAndBuffer(cellId, event, ...) end

---`client`
---Gets all the grid cells that the client is currently listening for
---@return table<CellId, true>
function exports.sleepless_grid:getActiveCells() end

---`server`
---Register handlers for streaming membership changes.
---`bucket` is the routing bucket the cell was entered or left in.
---@param onLoad? fun(playerId: number, cellId: string, bucket: number) Called when a player starts streaming a cell
---@param onUnload? fun(playerId: number, cellId: string, bucket: number) Called when a player stops streaming a cell
function exports.sleepless_grid:RegisterCellHandler(onLoad, onUnload) end

---`client`
---Register handlers for cell load/unload events
---@param onLoad? fun(cellId: string, bucket: number) Called when the client starts streaming a cell
---@param onUnload? fun(cellId: string, bucket: number) Called when the client stops streaming a cell
function exports.sleepless_grid:RegisterCellHandler(onLoad, onUnload) end

---`client|server`
---Parses a cell ID string into x and y coordinates
---@param cellId CellId
---@return integer? x
---@return integer? y
function exports.sleepless_grid:parseCellId(cellId) end

---`client|server`
---Gets all cell IDs within a buffer distance from the given cell coordinates
---@param cellX integer
---@param cellY integer
---@param buffer? integer Defaults to config.bufferSize
---@return CellIds
function exports.sleepless_grid:getNearbyCells(cellX, cellY, buffer) end

---`client|server`
---Gets the configured buffer size for grid cells
---@return integer
function exports.sleepless_grid:getBufferSize() end

---`server`
---Returns the sleepless_routing name for a bucket id or a registered name.
---Nil when routing is not running, or the bucket has no name.
---@param bucket number | string
---@return string | nil
function exports.sleepless_grid:getBucketName(bucket) end

---`client`
---The routing bucket this client is streaming, and its sleepless_routing name when one is set.
---@return number bucket
---@return string | nil bucketName
function exports.sleepless_grid:getRoutingBucket() end

---`client`
---On the next tick, replay load callbacks for cells the player is still streaming.
---Current membership is kept until that pass reconciles it, so cells left behind still unload.
function exports.sleepless_grid:refreshCells() end
