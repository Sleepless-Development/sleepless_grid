local function isResourceStarted(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

local function loadFramework()
    if isResourceStarted('qbx_core') then
        return require 'bridge.framework.qbx.client'
    elseif isResourceStarted('qb-core') then
        return require 'bridge.framework.qb.client'
    elseif isResourceStarted('ox_core') then
        return require 'bridge.framework.ox.client'
    elseif isResourceStarted('es_extended') then
        return require 'bridge.framework.esx.client'
    end
end

return loadFramework() or {
    playerLoaded = false,
}
