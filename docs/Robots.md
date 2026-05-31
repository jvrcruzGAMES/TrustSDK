# Robots

## Overview

`Robots` is the anti-bot / captcha package in TrustSDK.

It provides:

- server-triggered captcha challenges
- secure delivery over the `Transport` package
- React-based client UI
- timeout handling with `OnTimeout`
- tamper reporting for removed, hidden, disabled, or obscured UI
- optional movement lock with server-side movement detection

## Requirements

`Robots` depends on `Transport`.

Initialize `Transport` first, then initialize `Robots` with the transport package instance:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local Transport = TrustSDK("Transport")
local Robots = TrustSDK("Robots")

Transport:Initialize()
Robots:Initialize({
    Transport = Transport,
})
```

## Public API

## `Initialize(config)`

Server and client.

Config fields:

- `Transport: Transport?`

If omitted, `Robots` requires and uses the local `Transport` package automatically.

## `SummonCaptcha(player, options)`

Server-only.

Creates and displays a captcha for a player.

Returns:

- `challengeId: string`

## `DismissCaptcha(player, reason?)`

Server-only.

Dismisses the player’s active captcha, if one exists.

## `GetActiveCaptcha(player)`

Server-only.

Returns the active challenge id for that player, or `nil`.

## Captcha Options

- `Title: string?`
- `Prompt: string?`
- `CodeLength: number?`
- `MaxAttempts: number?`
- `TimeoutSeconds: number?`
- `LockMovement: boolean?`
- `FailOnMovement: boolean?`
- `AllowClose: boolean?`
- `Theme: CaptchaTheme?`
- `OnShown: ((Player, string) -> ())?`
- `OnSolved: ((Player, string, string) -> ())?`
- `OnFailed: ((Player, string, string?) -> ())?`
- `OnTampered: ((Player, string, string) -> ())?`
- `OnClosed: ((Player, string) -> ())?`
- `OnTimeout: ((Player, string) -> ())?`
- `OnMoveWhileLocked: ((Player, string) -> ())?`

## Theme Options

- `OverlayColor: string?`
- `CardColor: string?`
- `AccentColor: string?`
- `TextColor: string?`
- `MutedTextColor: string?`
- `ErrorColor: string?`

Theme colors are hex strings such as `"#0F172A"` or `"10B981"`.

## Behavior Notes

## Cryptographic Security

- Captcha codes are generated with the cryptography package RNG.
- Captcha traffic is sent through `Transport`, so delivery is encrypted and authenticated in transit.

## Tamper Detection

The client reports tampering when the captcha UI appears to be:

- removed from `PlayerGui`
- disabled
- hidden
- reduced to an unusably small size

The server treats reported tampering as a challenge failure and triggers `OnTampered`.

## Timeout Handling

Timeouts are optional.

If `TimeoutSeconds` is provided, the captcha will expire after that many seconds.
If `TimeoutSeconds` is omitted, the captcha remains active until it is solved, dismissed, tampered with, or otherwise failed.

When the timeout expires:

- the challenge is failed
- the UI is dismissed
- `OnTimeout` is called
- `OnFailed` is also called with `"timeout"`

## Movement Lock

If `LockMovement` is enabled:

- the client humanoid movement is locally frozen while the captcha is active
- the server also monitors movement for tamper / bypass attempts

If `FailOnMovement` is enabled and movement is detected:

- the challenge fails
- `OnMoveWhileLocked` is called
- `OnFailed` is also called with `"move_while_locked"`

## Example

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)

local Transport = TrustSDK("Transport")
local Robots = TrustSDK("Robots")

Transport:Initialize()
Robots:Initialize({
    Transport = Transport,
})

Robots:SummonCaptcha(player, {
    Title = "Human Check",
    Prompt = "Enter the code below to continue.",
    TimeoutSeconds = 60,
    MaxAttempts = 3,
    LockMovement = true,
    FailOnMovement = true,
    AllowClose = false,
    Theme = {
        OverlayColor = "#0F172A",
        CardColor = "#FFFFFF",
        AccentColor = "#10B981",
        TextColor = "#0F172A",
        MutedTextColor = "#64748B",
        ErrorColor = "#DC2626",
    },
    OnShown = function(targetPlayer, challengeId)
        print("Captcha shown", targetPlayer, challengeId)
    end,
    OnSolved = function(targetPlayer, challengeId, response)
        print("Solved", targetPlayer, challengeId, response)
    end,
    OnTimeout = function(targetPlayer, challengeId)
        warn("Captcha timed out", targetPlayer, challengeId)
    end,
    OnTampered = function(targetPlayer, challengeId, reason)
        warn("Captcha tampered", targetPlayer, challengeId, reason)
    end,
    OnFailed = function(targetPlayer, challengeId, reason)
        warn("Captcha failed", targetPlayer, challengeId, reason)
    end,
})
```

## Current Limitations

- The current captcha is text-code based, not image-distortion based.
- Tamper detection is heuristic, not perfect.
- A determined exploiter can still interact with the live client.
- `Robots` currently relies on `Transport` being initialized before secure captcha traffic can work.
