# TrustSDK Docs

## Modules

- [Transport](C:/Users/jvrcruz/Documents/Projects/Roblox/NetworkSDK/docs/Transport.md)
- [Robots](C:/Users/jvrcruz/Documents/Projects/Roblox/NetworkSDK/docs/Robots.md)

## Package Selection

The root package is a selector for TrustSDK modules.

Available packages:

- `Transport`
- `Robots`

Get all packages:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local packages = TrustSDK()
local Transport = packages.Transport
local Robots = packages.Robots
```

Get one package directly:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local Transport = TrustSDK("Transport")
local Robots = TrustSDK("Robots")
```

Helper methods:

```luau
local Transport = TrustSDK.GetPackage("Transport")
local packages = TrustSDK.GetPackages()
```

## Project Layout

- Root package: [lib/init.luau](C:/Users/jvrcruz/Documents/Projects/Roblox/NetworkSDK/lib/init.luau)
- Transport package: [lib/Transport.luau](C:/Users/jvrcruz/Documents/Projects/Roblox/NetworkSDK/lib/Transport.luau)
- Robots package: [lib/Robots.luau](C:/Users/jvrcruz/Documents/Projects/Roblox/NetworkSDK/lib/Robots.luau)
- Cryptography entry: [Packages/cryptography.lua](C:/Users/jvrcruz/Documents/Projects/Roblox/NetworkSDK/Packages/cryptography.lua)
