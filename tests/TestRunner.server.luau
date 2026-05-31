--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage.DevPackages.TestEZ)

return TestEZ.TestBootstrap:run({
	script.Parent.Specs,
}, TestEZ.Reporters.TextReporter)
