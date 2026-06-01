# TrustSDK Root Reference

The root package is a selector for TrustSDK modules.

Available packages:

- `Identity`
- `Transport`
- `Robots`

## `TrustSDK()`

Returns a table containing all packages.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local packages = TrustSDK()
local Identity = packages.Identity
local Transport = packages.Transport
local Robots = packages.Robots
```

## `TrustSDK(packageName)`

Returns one package by name.

Arguments:

- `packageName: "Identity" | "Transport" | "Robots"`

```luau
local Identity = TrustSDK("Identity")
local Transport = TrustSDK("Transport")
local Robots = TrustSDK("Robots")
```

## `TrustSDK(packageNames)`

Returns a table containing only the requested packages.

Arguments:

- `packageNames: {"Identity" | "Transport" | "Robots"}`

```luau
local selected = TrustSDK({ "Identity", "Transport" })
```

## `TrustSDK.GetPackage(packageName)`

Returns one package by name and raises if the name is unknown.

## `TrustSDK.GetPackages()`

Returns a cloned table of all packages.
