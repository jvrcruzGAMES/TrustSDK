--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Identity = TrustSDK("Identity")

local expectedMethods = {
	"Initialize",
	"GetPlayerIdentity",
	"GetLocalIdentity",
	"GetPlayerPublicKey",
	"GetLocalPublicKey",
	"GetPlayerSessionToken",
	"GetLocalSessionToken",
	"RefreshPlayerSession",
	"AddClientIdentityListener",
	"RemoveClientIdentityListener",
}

return function()
	describe("Identity package", function()
		it("exposes the expected public methods", function()
			for _, methodName in expectedMethods do
				expect(type((Identity :: any)[methodName])).to.equal("function")
			end
		end)
	end)
end
