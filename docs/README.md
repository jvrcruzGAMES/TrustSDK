# TrustSDK Docs

## Modules

- [Identity](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/Identity.md)
- [Transport](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/Transport.md)
- [Robots](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/Robots.md)

## Reference

- [API Reference Index](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/reference/README.md)
- [TrustSDK Root Reference](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/reference/Root.md)
- [Identity Reference](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/reference/Identity.md)
- [Transport Reference](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/reference/Transport.md)
- [Robots Reference](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/reference/Robots.md)
- [Type Reference](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/reference/Types.md)
- [Cloud Reference Index](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/reference/cloud/README.md)
- [IdentityServer Reference](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/docs/reference/cloud/IdentityServer.md)

## Package Selection

The root package is a selector for TrustSDK modules.

Available packages:

- `Identity`
- `Transport`
- `Robots`

Get all packages:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local packages = TrustSDK()
local Identity = packages.Identity
local Transport = packages.Transport
local Robots = packages.Robots
```

Get one package directly:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local Identity = TrustSDK("Identity")
local Transport = TrustSDK("Transport")
local Robots = TrustSDK("Robots")
```

Helper methods:

```luau
local Identity = TrustSDK.GetPackage("Identity")
local Transport = TrustSDK.GetPackage("Transport")
local packages = TrustSDK.GetPackages()
```

## Project Layout

- Root package: [lib/init.luau](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/lib/init.luau)
- Identity package: [lib/Identity.luau](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/lib/Identity.luau)
- Transport package: [lib/Transport.luau](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/lib/Transport.luau)
- Robots package: [lib/Robots.luau](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/lib/Robots.luau)
- Cryptography entry: [Packages/cryptography.lua](C:/Users/jvrcruz/Documents/Projects/Roblox/TrustSDK/Packages/cryptography.lua)
