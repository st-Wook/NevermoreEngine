--[=[
	@class AnimationTrackPlayer
]=]

local require = require(script.Parent.loader).load(script)

local BaseObject = require("BaseObject")
local ValueObject = require("ValueObject")
local Rx = require("Rx")
local AnimationUtils = require("AnimationUtils")
local Signal = require("Signal")

local AnimationTrackPlayer = setmetatable({}, BaseObject)
AnimationTrackPlayer.ClassName = "AnimationTrackPlayer"
AnimationTrackPlayer.__index = AnimationTrackPlayer

function AnimationTrackPlayer.new(animationTarget, animationId)
	local self = setmetatable(BaseObject.new(), AnimationTrackPlayer)

	self._animationTarget = ValueObject.new(nil)
	self._maid:GiveTask(self._animationTarget)

	self._trackId = ValueObject.new(nil)
	self._maid:GiveTask(self._trackId)

	self._currentTrack = ValueObject.new(nil)
	self._maid:GiveTask(self._currentTrack)

	self.KeyframeReached = Signal.new()
	self._maid:GiveTask(self.KeyframeReached)

	self._animationPriority = ValueObject.new(nil)
	self._maid:GiveTask(self._animationPriority)

	if animationTarget then
		self:SetAnimationTarget(animationTarget)
	end

	if animationId then
		self:SetAnimationId(animationId)
	end

	self:_setupState()

	return self
end

function AnimationTrackPlayer:_setupState()
	self._maid:GiveTask(Rx.combineLatest({
		animationTarget = self._animationTarget:Observe();
		trackId = self._trackId:Observe();
		animationPriority = self._animationPriority:Observe();
	}):Pipe({
		Rx.throttleDefer();
	}):Subscribe(function(state)
		if state.animationTarget and state.trackId then
			self._currentTrack.Value = AnimationUtils.getOrCreateAnimationTrack(state.animationTarget, state.trackId, state.animationPriority)
		else
			self._currentTrack.Value = nil
		end
	end))

	self._maid:GiveTask(self._currentTrack:ObserveBrio(function(track)
		return track ~= nil
	end):Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		local maid = brio:ToMaid()
		local track = brio:GetValue()

		maid:GiveTask(track.KeyframeReached:Connect(function(...)
			self.KeyframeReached:Fire(...)
		end))
	end))
end

function AnimationTrackPlayer:SetAnimationId(animationId)
	return self._trackId:Mount(animationId)
end

function AnimationTrackPlayer:GetAnimationId()
	return self._trackId.Value
end

function AnimationTrackPlayer:SetAnimationTarget(animationTarget)
	return self._animationTarget:Mount(animationTarget)
end

function AnimationTrackPlayer:SetWeightTargetIfNotSet(weight, fadeTime)
	self._maid._adjustWeight = self:_onEachTrack(function(_maid, track)
		if track.WeightTarget ~= weight then
			track:AdjustWeight(weight, fadeTime)
		end
	end)
end

function AnimationTrackPlayer:Play(fadeTime, weight, speed)
	if weight then
		self._maid._adjustWeight = nil
	end

	if speed then
		self._maid._adjustSpeed = nil
	end

	self._maid._stop = nil
	self._maid._play = self:_onEachTrack(function(_maid, track)
		track:Play(fadeTime, weight, speed)
	end)
end

function AnimationTrackPlayer:Stop(fadeTime)
	self._maid._play = nil
	self._maid._stop = self:_onEachTrack(function(_maid, track)
		track:Stop(fadeTime)
	end)
end

function AnimationTrackPlayer:AdjustWeight(weight, fadeTime)
	self._maid._adjustWeight = self:_onEachTrack(function(_maid, track)
		track:AdjustWeight(weight, fadeTime)
	end)
end

function AnimationTrackPlayer:AdjustSpeed(speed, fadeTime)
	self._maid._adjustSpeed = self:_onEachTrack(function(_maid, track)
		track:AdjustSpeed(speed, fadeTime)
	end)
end

function AnimationTrackPlayer:IsPlaying()
	local track = self._currentTrack.Value
	if track then
		return track.IsPlaying
	else
		return false
	end
end

function AnimationTrackPlayer:_onEachTrack(callback)
	return self._currentTrack:ObserveBrio(function(track)
		return track ~= nil
	end):Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		local track = brio:GetValue()
		callback(brio:ToMaid(), track)
	end)
end

return AnimationTrackPlayer