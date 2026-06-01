# Robots Reference

`Robots` provides secure captcha / anti-bot flows on top of `Transport`.

## Initialize

## `Robots:Initialize(config?)`

Server and client.

Config fields:

- `Transport: Transport?`

If omitted, `Robots` requires and uses the local `Transport` package automatically.

## Captcha Control

## `Robots:SummonCaptcha(player, options)`

Server-only.

Arguments:

- `player: Player`
- `options: CaptchaOptions?`

Returns:

- `challengeId: string`

## `Robots:DismissCaptcha(player, reason?)`

Server-only.

Arguments:

- `player: Player`
- `reason: string?`

## `Robots:GetActiveCaptcha(player)`

Server-only.

Arguments:

- `player: Player`

Returns:

- `string?`

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
