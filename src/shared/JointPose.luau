--!strict
-- Poses a body joint (e.g. "RightShoulder", "Waist") on an R15 rig, whichever
-- joint system the rig uses:
--  * classic Motor6D joints: the pose is the joint's C0
--  * Roblox's Avatar Joint Upgrade (AnimationConstraint joints): the pose is the
--    CFrame of the constraint's Attachment0 (the rig attachment on the parent part)
-- Both are set, so it works on either; only the active system has a visible effect.
-- A pose is an offset applied on top of the joint's resting value.

local TweenService = game:GetService("TweenService")

local JointPose = {}

export type Joint = {
	-- Every (instance, property, resting value) that holds this joint's pose.
	slots: { { instance: Instance, property: string, rest: CFrame } },
	system: string, -- "Motor6D", "AnimationConstraint" or "Both", for diagnostics
}

-- Finds a joint by name anywhere in the model. The resting values are read now,
-- so call it before posing (each caller keeps its own Joint).
function JointPose.find(model: Model, name: string): Joint?
	local slots = {}
	local seen: { [Instance]: boolean } = {}
	local function add(instance: Instance, property: string, rest: CFrame)
		if not seen[instance] then
			seen[instance] = true
			table.insert(slots, { instance = instance, property = property, rest = rest })
		end
	end
	local hasMotor, hasConstraint = false, false
	for _, item in model:GetDescendants() do
		if item.Name == name then
			if item:IsA("Motor6D") then
				add(item, "C0", item.C0)
				hasMotor = true
				-- Also the matching rig attachment: if the joint is upgraded to an
				-- AnimationConstraint later (e.g. when the model enters the world),
				-- the new joint is built from it and keeps the pose.
				local part0 = item.Part0
				local rigAttachment = part0 and part0:FindFirstChild(name .. "RigAttachment")
				if rigAttachment and rigAttachment:IsA("Attachment") then
					add(rigAttachment, "CFrame", rigAttachment.CFrame)
				end
			elseif item:IsA("AnimationConstraint") and item.Attachment0 then
				local attachment = item.Attachment0 :: Attachment
				add(attachment, "CFrame", attachment.CFrame)
				hasConstraint = true
			end
		end
	end
	if #slots == 0 then
		return nil
	end
	local system = if hasMotor and hasConstraint then "Both" elseif hasMotor then "Motor6D" else "AnimationConstraint"
	return { slots = slots, system = system }
end

-- Sets the joint to rest * offset immediately.
function JointPose.set(joint: Joint, offset: CFrame)
	for _, slot in joint.slots do
		(slot.instance :: any)[slot.property] = slot.rest * offset
	end
end

-- Tweens the joint to rest * offset. Returns the tweens so callers can cancel them.
function JointPose.tween(joint: Joint, offset: CFrame, info: TweenInfo): { Tween }
	local tweens = {}
	for _, slot in joint.slots do
		local tween = TweenService:Create(slot.instance, info, { [slot.property] = slot.rest * offset })
		tween:Play()
		table.insert(tweens, tween)
	end
	return tweens
end

-- Animation layer (owner 2026-10-22, the swing pattern from the owner's other
-- project). Resting-pose offsets (set/tween above) are hidden on joints the
-- walk/idle animations move strongly, such as the shoulders. Instead, every
-- frame after the animations have run (RunService.PreSimulation), add a
-- rotation on top of the joint's animated Transform.

-- The animated joints named `name` in the model: Motor6Ds and/or
-- AnimationConstraints, whichever the rig uses (both have a Transform).
function JointPose.animated(model: Model, name: string): { Instance }
	local joints: { Instance } = {}
	for _, item in model:GetDescendants() do
		if item.Name == name and (item:IsA("Motor6D") or item:IsA("AnimationConstraint")) then
			table.insert(joints, item)
		end
	end
	return joints
end

-- Adds `rotation` on top of this frame's animation, around the parent part's
-- axes (e.g. CFrame.Angles(a, 0, 0) on a shoulder turns the arm about the
-- torso's left-right axis; positive raises it forward). Call every frame from
-- PreSimulation while the motion lasts.
function JointPose.addRotation(joint: Instance, rotation: CFrame)
	local frame = CFrame.identity
	if joint:IsA("Motor6D") then
		frame = joint.C0.Rotation
	elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
		frame = joint.Attachment0.CFrame.Rotation
	end
	local animated = joint :: any
	animated.Transform = frame:Inverse() * rotation * frame * animated.Transform
end

return table.freeze(JointPose)
