local config = require 'config'

local utils = {}

local MPH_PER_MS = 2.236936

---@param x number
---@param y number
---@return string
function utils.makeCellId(x, y)
    return ('cell_%d_%d'):format(x, y)
end

---@param cellId string
---@return integer? x
---@return integer? y
function utils.parseCellId(cellId)
    local xStr, yStr = cellId:match('^cell_(%-?%d+)_(%-?%d+)$')

    if not xStr or not yStr then
        return nil, nil
    end

    local x = tonumber(xStr)
    local y = tonumber(yStr)

    return x, y
end

---@param coords vector3
---@return integer cellX, integer cellY
function utils.getCellFromCoords(coords)
    return math.floor(coords.x / config.cellSize), math.floor(coords.y / config.cellSize)
end

---@param fast boolean
---@param speed number Speed in meters per second
---@return number bufferSize
---@return boolean fast
function utils.resolveBufferSize(fast, speed)
    local fullBuffer = math.floor(tonumber(config.bufferSize) or 0)
    if fullBuffer < 0 then
        fullBuffer = 0
    end

    local dynamic = config.dynamicBuffer
    if type(dynamic) ~= 'table' or not dynamic.enabled then
        return fullBuffer, false
    end

    local shrinkAt = tonumber(dynamic.speedThreshold) or 60
    local restoreAt = tonumber(dynamic.restoreThreshold)
    if not restoreAt or restoreAt >= shrinkAt then
        restoreAt = math.max(0, shrinkAt - 15)
    end

    local speedMph = (tonumber(speed) or 0) * MPH_PER_MS

    if fast then
        if speedMph <= restoreAt then
            fast = false
        end
    elseif speedMph >= shrinkAt then
        fast = true
    end

    if fast then
        return 0, true
    end

    return fullBuffer, false
end

---@param cellX integer
---@param cellY integer
---@param buffer integer
---@return CellIds
function utils.getNearbyCells(cellX, cellY, buffer)
    local result = {}
    for x = (cellX - buffer), (cellX + buffer) do
        for y = (cellY - buffer), (cellY + buffer) do
            result[#result + 1] = utils.makeCellId(x, y)
        end
    end
    return result
end

---@param cellId string
---@param list {x:number, y:number}[]
---@return boolean
function utils.inCellList(cellId, list)
    return lib.table.contains(list, cellId)
end

---@param entries table<number, boolean>
---@return number[]
function utils.getTableKeys(entries)
    local keys = {}
    for key in pairs(entries) do
        keys[#keys + 1] = key
    end
    return keys
end

return utils
