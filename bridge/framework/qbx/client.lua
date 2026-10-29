local bridge = {
    framework = 'qbx',
    playerLoaded = false,
}

AddStateBagChangeHandler('isLoggedIn', ('player:%s'):format(cache.serverId), function(_, _, value)
    bridge.playerLoaded = value

    if value then
        TriggerEvent('sleepless_grid:playerLoaded')
    else
        TriggerEvent('sleepless_grid:playerUnloaded')
    end
end)

CreateThread(function()
    bridge.playerLoaded = LocalPlayer.state.isLoggedIn

    if bridge.playerLoaded then
        TriggerEvent('sleepless_grid:playerLoaded')
    end
end)

return bridge
