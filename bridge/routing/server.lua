local routing = {}

local function routingStarted()
    local state = GetResourceState('sleepless_routing')
    return state == 'started' or state == 'starting'
end

---@param name string
---@return number | nil
function routing.resolveName(name)
    if type(name) ~= 'string' or name == '' or not routingStarted() then
        return nil
    end

    local ok, bucketId = pcall(function()
        return exports.sleepless_routing:getBucketId(name)
    end)

    if not ok or type(bucketId) ~= 'number' then
        return nil
    end

    return math.floor(bucketId)
end

---@param bucketId number
---@return string | nil
function routing.getName(bucketId)
    if type(bucketId) ~= 'number' or not routingStarted() then
        return nil
    end

    local ok, name = pcall(function()
        return exports.sleepless_routing:getBucketName(math.floor(bucketId))
    end)

    if not ok or type(name) ~= 'string' or name == '' then
        return nil
    end

    return name
end

return routing
