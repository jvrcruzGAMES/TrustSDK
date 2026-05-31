--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Transport = TrustSDK("Transport")
local Robots = TrustSDK("Robots")

local readyPlayers: {[Player]: boolean} = {}

Transport:Initialize({
	OnServerMessage = function(player, plaintext)
		local message = buffer.tostring(plaintext)
		print("[TrustSDK Server] Secure message from", player.Name, message)

		if message == "client_ready_for_captcha" and not readyPlayers[player] then
			readyPlayers[player] = true

			Robots:SummonCaptcha(player, {
				Title = "Human Check",
				Prompt = "Enter the code below to continue.",
				TimeoutSeconds = 20,
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
					print("[TrustSDK Server] Captcha shown", targetPlayer.Name, challengeId)
				end,
				OnSolved = function(targetPlayer, challengeId, response)
					print("[TrustSDK Server] Captcha solved", targetPlayer.Name, challengeId, response)
				end,
				OnTimeout = function(targetPlayer, challengeId)
					warn("[TrustSDK Server] Captcha timed out", targetPlayer.Name, challengeId)
					targetPlayer:Kick("Captcha timeout.")
				end,
				OnTampered = function(targetPlayer, challengeId, reason)
					warn("[TrustSDK Server] Captcha tampered", targetPlayer.Name, challengeId, reason)
					targetPlayer:Kick("Captcha tampering detected.")
				end,
				OnFailed = function(targetPlayer, challengeId, reason)
					warn("[TrustSDK Server] Captcha failed", targetPlayer.Name, challengeId, reason)
					targetPlayer:Kick("Captcha failed.")
				end,
			})
		end
	end,
	Debug = true
})

Robots:Initialize({
	Transport = Transport,
})
