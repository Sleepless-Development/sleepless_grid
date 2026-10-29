# sleepless_grid

A spatial grid for FiveM. Other resources load and unload world content as players move between cells.

![](https://img.shields.io/github/downloads/Sleepless-Development/sleepless_grid/total?logo=github)
![](https://img.shields.io/github/downloads/Sleepless-Development/sleepless_grid/latest/total?logo=github)
![](https://img.shields.io/github/contributors/Sleepless-Development/sleepless_grid?logo=github)
![](https://img.shields.io/github/v/release/Sleepless-Development/sleepless_grid?logo=github)\
[![](https://badges.5metrics.dev/sleepless_grid/serverRank.svg?style=for-the-badge)](https://5metrics.dev/resource/sleepless_grid)
[![](https://badges.5metrics.dev/sleepless_grid/servers.svg?style=for-the-badge)](https://5metrics.dev/resource/sleepless_grid)
[![](https://badges.5metrics.dev/sleepless_grid/players.svg?style=for-the-badge)](https://5metrics.dev/resource/sleepless_grid)

## Features

- Cells from world coordinates, default 100 meters
- Each player streams their cell plus a configurable buffer
- Above the speed threshold, streaming shrinks to the current cell
- Occupancy and streaming are tracked per routing bucket
- Optional sleepless_routing bucket names on the server exports
- Framework bridges for Qbox, QBCore, ESX, and ox_core

## Dependencies

- [ox_lib](https://github.com/communityox/ox_lib)

[sleepless_routing](https://github.com/Sleepless-Development/sleepless_routing) is optional. Without it, pass numeric bucket ids.

## Installation

1. Download the resource.
2. Place the `sleepless_grid` folder in your resources directory. Keep the folder name.
3. Add it to `server.cfg` after `ox_lib`, and before resources that call it:

```cfg
ensure ox_lib
ensure sleepless_grid
```

## Documentation

https://sleeplessdevelopment.dev/docs/grid

## Download

[sleepless_grid.zip](https://github.com/Sleepless-Development/sleepless_grid/releases/latest/download/sleepless_grid.zip)

## Usage

Register for the cells this client is streaming:

```lua
local function onEnter(cellId, bucket)
    lib.print.info(cellId, bucket)
end

local function onLeave(cellId, bucket)
    lib.print.info(cellId, bucket)
end

exports.sleepless_grid:RegisterCellHandler(onEnter, onLeave)
```

On the server, the handlers also receive the player id:

```lua
exports.sleepless_grid:RegisterCellHandler(function(playerId, cellId, bucket)
end, function(playerId, cellId, bucket)
end)
```

Send an event to players standing in a cell. The bucket argument is optional and defaults to `0`.

```lua
exports.sleepless_grid:triggerClientEventForCell(coords, 'myresource:client:cellUpdated', payload)
exports.sleepless_grid:triggerClientEventForCell(coords, bucketId, 'myresource:client:cellUpdated', payload)
```

`getPlayersFromCell` is who is standing in the cell. `getSubscribersFromCell` is who is streaming it. Streaming already includes the buffer, so that export does not expand again.

## Configuration

`config.lua` is shared. `debug` defaults to `false`. Debug lines print only while it is `true`.

`dynamicBuffer.speedThreshold` is miles per hour. At or above that speed, the streamed buffer becomes the current cell. The full buffer returns after speed falls to `restoreThreshold`.

## License

[GPL-3.0](LICENSE)
