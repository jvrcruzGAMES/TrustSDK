--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Transport = TrustSDK("Transport")
local Robots = TrustSDK("Robots")

local localPlayer = Players.LocalPlayer
assert(localPlayer, "TransportClientTest requires LocalPlayer")

Transport:Initialize({
	OnClientMessage = function(plaintext)
		print("[TrustSDK Client] Secure message:", buffer.tostring(plaintext))
	end,
})

Robots:Initialize({
	Transport = Transport,
})

local ok, errorMessage = pcall(function()
		Transport:BeginClientHandshake()
	end)

if ok then
	print("[TrustSDK Client] Handshake complete")
else
	warn("[TrustSDK Client] Handshake failed:", errorMessage)
end

localPlayer.Chatted:Connect(function(message)
	if string.lower(message) == "!robots" then
		print("[TrustSDK Client] Chat trigger received: !robots")
		Transport:SendToServer("client_ready_for_captcha")
	end
end)
