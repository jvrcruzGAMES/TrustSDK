--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TrustSDK = require(ReplicatedStorage.TrustSDK)
local Robots = TrustSDK("Robots")

local expectedMethods = {
	"Initialize",
	"SummonCaptcha",
	"DismissCaptcha",
	"GetActiveCaptcha",
}

return function()
	describe("Robots package", function()
		it("exposes the expected public methods", function()
			for _, methodName in expectedMethods do
				expect(type((Robots :: any)[methodName])).to.equal("function")
			end
		end)
	end)
end
