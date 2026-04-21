local hg = require("harfang")

local HAND_SIDES = {
	left = {
		label = "Left",
		sign = 1,
		shoulder = "mixamorig:LeftShoulder",
		arm = "mixamorig:LeftArm",
		forearm = "mixamorig:LeftForeArm",
		hand = "mixamorig:LeftHand"
	},
	right = {
		label = "Right",
		sign = -1,
		shoulder = "mixamorig:RightShoulder",
		arm = "mixamorig:RightArm",
		forearm = "mixamorig:RightForeArm",
		hand = "mixamorig:RightHand"
	}
}

local LEG_SIDES = {
	left = {
		upper = "mixamorig:LeftUpLeg",
		lower = "mixamorig:LeftLeg",
		foot = "mixamorig:LeftFoot",
		phase_offset = 0.0
	},
	right = {
		upper = "mixamorig:RightUpLeg",
		lower = "mixamorig:RightLeg",
		foot = "mixamorig:RightFoot",
		phase_offset = math.pi
	}
}

local CONTROLLED_NODE_NAMES = {
	"mixamorig:Hips",
	"mixamorig:LeftShoulder",
	"mixamorig:LeftArm",
	"mixamorig:LeftForeArm",
	"mixamorig:LeftHand",
	"mixamorig:RightShoulder",
	"mixamorig:RightArm",
	"mixamorig:RightForeArm",
	"mixamorig:RightHand",
	"mixamorig:LeftUpLeg",
	"mixamorig:LeftLeg",
	"mixamorig:LeftFoot",
	"mixamorig:RightUpLeg",
	"mixamorig:RightLeg",
	"mixamorig:RightFoot"
}

local Controller = {}
Controller.__index = Controller

local function copy_vec3(value)
	return hg.Vec3(value.x, value.y, value.z)
end

local function clamp(value, min_value, max_value)
	return math.max(min_value, math.min(max_value, value))
end

local function atan2(y, x)
	if x > 0.0 then
		return math.atan(y / x)
	elseif x < 0.0 then
		if y >= 0.0 then
			return math.atan(y / x) + math.pi
		end

		return math.atan(y / x) - math.pi
	elseif y > 0.0 then
		return math.pi * 0.5
	elseif y < 0.0 then
		return -math.pi * 0.5
	end

	return 0.0
end

local function move_toward(value, target, max_delta)
	if value < target then
		return math.min(value + max_delta, target)
	end

	return math.max(value - max_delta, target)
end

local function shortest_angle_rad(current, target)
	local delta = math.fmod(target - current + math.pi, math.pi * 2.0)
	if delta < 0.0 then
		delta = delta + math.pi * 2.0
	end
	return delta - math.pi
end

local function flatten_xz(value)
	return hg.Vec3(value.x, 0.0, value.z)
end

local function safe_normalize(value, fallback)
	local length = hg.Len(value)
	if length <= 0.00001 then
		return fallback
	end

	return value * (1.0 / length)
end

local function capture_local_pose(node)
	local transform = node:GetTransform()
	return {
		pos = copy_vec3(transform:GetPos()),
		rot = copy_vec3(transform:GetRot()),
		scale = copy_vec3(transform:GetScale())
	}
end

local function get_world_position(node)
	return hg.GetT(node:GetTransform():GetWorld())
end

local function get_world_rotation(node)
	return hg.GetRotation(node:GetTransform():GetWorld())
end

local function ensure_valid_node(node, name)
	if not node:IsValid() then
		error(('AutomatonController: node "%s" is missing or invalid'):format(name))
	end

	return node
end

local function forward_from_yaw(yaw)
	return hg.Vec3(math.sin(yaw), 0.0, -math.cos(yaw))
end

local function lerp_vec3(a, b, t)
	return hg.Lerp(a, b, t)
end

local function resolve_chain_length(rest_pose)
	return hg.Len(rest_pose.pos)
end

function Controller:_get_view_node(name)
	local node = self.scene_view:GetNode(self.scene, name)
	return ensure_valid_node(node, name)
end

function Controller:_get_host_node(name)
	local cached = self.host_nodes[name]
	if cached ~= nil then
		return cached
	end

	local node = ensure_valid_node(self.scene:GetNode(name), name)
	self.host_nodes[name] = node
	return node
end

function Controller:_resolve_hand_target(name)
	local cached = self.hand_targets[name]
	if cached ~= nil then
		return cached
	end

	local node = self.scene_view:GetNode(self.scene, name)
	if node:IsValid() then
		self.hand_targets[name] = node
		return node
	end

	node = self.scene:GetNode(name)
	if node:IsValid() then
		self.hand_targets[name] = node
		return node
	end

	error(('AutomatonController: hand target "%s" not found in instance view or host scene'):format(name))
end

function Controller:_restore_controlled_pose()
	for _, name in ipairs(CONTROLLED_NODE_NAMES) do
		local node = self.view_nodes[name]
		local rest_pose = self.rest_pose[name]
		node:GetTransform():SetPosRot(rest_pose.pos, rest_pose.rot)
	end
end

function Controller:_update_hand_lock_blends(dt)
	for _, side in ipairs({"left", "right"}) do
		local lock_state = self.hand_locks[side]
		local blend_target = lock_state.active and 1.0 or 0.0
		lock_state.blend = move_toward(lock_state.blend, blend_target, dt * self.params.hand_lock_blend_speed)
	end
end

function Controller:_set_move_target(target_name)
	local target_node = self:_get_host_node(target_name)
	local target_position = get_world_position(target_node)

	self.target_node_name = target_name
	self.target_world = hg.Vec3(target_position.x, self.ground_y, target_position.z)
	self.arrived = false
end

function Controller:MoveToNode(target_name)
	self:_set_move_target(target_name)
end

function Controller:MoveFromNodeToNode(start_name, target_name)
	local start_node = self:_get_host_node(start_name)
	local start_position = get_world_position(start_node)
	local instance_transform = self.instance_node:GetTransform()
	local instance_rotation = instance_transform:GetRot()

	instance_transform:SetPosRot(hg.Vec3(start_position.x, self.ground_y, start_position.z), instance_rotation)
	self.walk_phase = 0.0
	self:_set_move_target(target_name)
end

function Controller:PlaceLeftHandOnNode(target_name)
	self:_set_hand_lock("left", target_name)
end

function Controller:PlaceRightHandOnNode(target_name)
	self:_set_hand_lock("right", target_name)
end

function Controller:UnlockLeftHand()
	self:_clear_hand_lock("left")
end

function Controller:UnlockRightHand()
	self:_clear_hand_lock("right")
end

function Controller:_set_hand_lock(side, target_name)
	local lock_state = self.hand_locks[side]
	lock_state.target_name = target_name
	lock_state.target_node = self:_resolve_hand_target(target_name)
	lock_state.active = true
end

function Controller:_clear_hand_lock(side)
	local lock_state = self.hand_locks[side]
	lock_state.active = false
	lock_state.target_name = nil
	lock_state.target_node = nil
end

function Controller:_update_root_motion(dt)
	local instance_transform = self.instance_node:GetTransform()
	local position = instance_transform:GetPos()
	local rotation = instance_transform:GetRot()
	local move_step = 0.0

	self.state = "Idle"
	self.current_speed = 0.0
	self.distance_to_target = 0.0
	self.yaw_error = 0.0

	if self.target_world == nil then
		return move_step
	end

	local to_target = flatten_xz(self.target_world - position)
	local distance = hg.Len(to_target)
	self.distance_to_target = distance

	if distance <= self.params.arrive_distance then
		self.state = "Arrived"
		self.arrived = true
		self.target_world = nil
		self.target_node_name = nil
		return move_step
	end

	local desired_direction = safe_normalize(to_target, forward_from_yaw(rotation.y))
	local desired_yaw = atan2(desired_direction.x, -desired_direction.z)
	local yaw_error = shortest_angle_rad(rotation.y, desired_yaw)
	local yaw_step = clamp(yaw_error, -self.params.turn_speed * dt, self.params.turn_speed * dt)

	rotation.y = rotation.y + yaw_step
	instance_transform:SetRot(rotation)

	self.yaw_error = yaw_error

	local forward = forward_from_yaw(rotation.y)
	local facing = clamp(hg.Dot(forward, desired_direction), 0.0, 1.0)

	if math.abs(yaw_error) > self.params.turn_in_place_angle then
		self.state = "TurnInPlace"
		return move_step
	end

	self.current_speed = self.params.walk_speed * facing
	move_step = math.min(distance, self.current_speed * dt)
	position = position + forward * move_step
	position.y = self.ground_y
	instance_transform:SetPos(position)
	self.distance_to_target = math.max(0.0, distance - move_step)
	self.state = move_step > 0.0 and "Walk" or "TurnInPlace"
	return move_step
end

function Controller:_update_walk_phase(move_step)
	if move_step > 0.00001 then
		self.walk_phase = self.walk_phase + move_step / self.params.step_cycle_distance * math.pi * 2.0
	end
end

function Controller:_apply_walk_pose()
	local locomotion_weight = clamp(self.current_speed / self.params.walk_speed, 0.0, 1.0)
	local hips_transform = self.view_nodes["mixamorig:Hips"]:GetTransform()
	local hips_rest = self.rest_pose["mixamorig:Hips"]
	local sway = math.sin(self.walk_phase) * self.params.hips_sway * locomotion_weight
	local bob = math.abs(math.sin(self.walk_phase * 2.0)) * self.params.hips_bob * locomotion_weight

	hips_transform:SetPosRot(
		hg.Vec3(hips_rest.pos.x + sway, hips_rest.pos.y - bob, hips_rest.pos.z),
		hips_rest.rot
	)

	for _, side_name in ipairs({"left", "right"}) do
		local side = LEG_SIDES[side_name]
		local phase = self.walk_phase + side.phase_offset
		local swing = math.sin(phase) * locomotion_weight
		local support = math.max(-swing, 0.0)
		local upper_node = self.view_nodes[side.upper]
		local lower_node = self.view_nodes[side.lower]
		local foot_node = self.view_nodes[side.foot]
		local upper_rest = self.rest_pose[side.upper]
		local lower_rest = self.rest_pose[side.lower]
		local foot_rest = self.rest_pose[side.foot]

		upper_node:GetTransform():SetPosRot(
			upper_rest.pos,
			upper_rest.rot + hg.Vec3(self.params.leg_swing * swing, 0.0, 0.0)
		)
		lower_node:GetTransform():SetPosRot(
			lower_rest.pos,
			lower_rest.rot + hg.Vec3(self.params.knee_bend * support, 0.0, 0.0)
		)
		foot_node:GetTransform():SetPosRot(
			foot_rest.pos,
			foot_rest.rot + hg.Vec3(-self.params.foot_compensation * swing - self.params.knee_bend * support * 0.35, 0.0, 0.0)
		)
	end
end

function Controller:_compute_free_arm_pose(side_name)
	local side = HAND_SIDES[side_name]
	local locomotion_weight = clamp(self.current_speed / self.params.walk_speed, 0.0, 1.0)
	local phase = self.walk_phase + (side_name == "left" and math.pi or 0.0)
	local swing = math.sin(phase) * locomotion_weight
	local shoulder_rest = self.rest_pose[side.shoulder]
	local arm_rest = self.rest_pose[side.arm]
	local forearm_rest = self.rest_pose[side.forearm]
	local hand_rest = self.rest_pose[side.hand]

	return {
		shoulder = shoulder_rest.rot + hg.Vec3(0.0, 0.0, self.params.shoulder_swing * swing * side.sign),
		arm = arm_rest.rot + hg.Vec3(-self.params.arm_swing * swing, 0.0, 0.0),
		forearm = forearm_rest.rot + hg.Vec3(math.max(0.0, -swing) * self.params.forearm_swing, 0.0, 0.0),
		hand = hand_rest.rot
	}
end

function Controller:_compute_locked_arm_pose(side_name, target_node)
	local side = HAND_SIDES[side_name]
	local shoulder_node = self.view_nodes[side.shoulder]
	local arm_node = self.view_nodes[side.arm]
	local forearm_node = self.view_nodes[side.forearm]
	local hand_node = self.view_nodes[side.hand]
	local shoulder_world = shoulder_node:GetTransform():GetWorld()
	local target_world = target_node:GetTransform():GetWorld()
	local target_local = hg.InverseFast(shoulder_world) * hg.GetT(target_world)
	local arm_rest = self.rest_pose[side.arm]
	local forearm_rest = self.rest_pose[side.forearm]
	local shoulder_rest = self.rest_pose[side.shoulder]
	local hand_rest_world = hand_node:GetTransform():GetWorld()
	local rel = target_local - arm_rest.pos
	local distance = math.max(hg.Len(rel), 0.0001)
	local reach_ratio = clamp(distance / (self.arm_lengths[side_name].upper + self.arm_lengths[side_name].lower), 0.0, 1.0)
	local rel_planar = math.max(math.sqrt(rel.x * rel.x + rel.y * rel.y), 0.0001)
	local aim_x = clamp(atan2(rel.z, rel_planar), -self.params.arm_lock_pitch_limit, self.params.arm_lock_pitch_limit)
	local aim_z = clamp(
		-atan2(rel.x * side.sign, math.max(rel.y, 0.0001)) * side.sign,
		-self.params.arm_lock_roll_limit,
		self.params.arm_lock_roll_limit
	)
	local elbow = self.params.arm_lock_elbow_bend * (1.0 - reach_ratio)
	local current_hand_world = hand_rest_world
	local current_hand_pos = hg.GetT(current_hand_world)
	local current_hand_rot = hg.GetRotation(current_hand_world)
	local target_hand_pos = hg.GetT(target_world)
	local target_hand_rot = hg.GetRotation(target_world)

	return {
		shoulder = shoulder_rest.rot + hg.Vec3(aim_x * 0.2, 0.0, aim_z * 0.45),
		arm = arm_rest.rot + hg.Vec3(aim_x - elbow * 0.35, 0.0, aim_z * 0.7),
		forearm = forearm_rest.rot + hg.Vec3(elbow, 0.0, 0.0),
		hand_world_pos = target_hand_pos,
		hand_world_rot = target_hand_rot,
		current_hand_world_pos = current_hand_pos,
		current_hand_world_rot = current_hand_rot
	}
end

function Controller:_apply_arm_pose(side_name)
	local side = HAND_SIDES[side_name]
	local lock_state = self.hand_locks[side_name]
	local free_pose = self:_compute_free_arm_pose(side_name)
	local shoulder_node = self.view_nodes[side.shoulder]
	local arm_node = self.view_nodes[side.arm]
	local forearm_node = self.view_nodes[side.forearm]
	local hand_node = self.view_nodes[side.hand]
	local shoulder_rest = self.rest_pose[side.shoulder]
	local arm_rest = self.rest_pose[side.arm]
	local forearm_rest = self.rest_pose[side.forearm]
	local hand_rest = self.rest_pose[side.hand]

	shoulder_node:GetTransform():SetPosRot(shoulder_rest.pos, free_pose.shoulder)
	arm_node:GetTransform():SetPosRot(arm_rest.pos, free_pose.arm)
	forearm_node:GetTransform():SetPosRot(forearm_rest.pos, free_pose.forearm)
	hand_node:GetTransform():SetPosRot(hand_rest.pos, free_pose.hand)

	if lock_state.blend <= 0.0 or lock_state.target_node == nil then
		return
	end

	local locked_pose = self:_compute_locked_arm_pose(side_name, lock_state.target_node)
	local blend = lock_state.blend
	local shoulder_rot = lerp_vec3(free_pose.shoulder, locked_pose.shoulder, blend)
	local arm_rot = lerp_vec3(free_pose.arm, locked_pose.arm, blend)
	local forearm_rot = lerp_vec3(free_pose.forearm, locked_pose.forearm, blend)
	local hand_pos = lerp_vec3(locked_pose.current_hand_world_pos, locked_pose.hand_world_pos, blend)
	local hand_rot = lerp_vec3(locked_pose.current_hand_world_rot, locked_pose.hand_world_rot, blend)

	shoulder_node:GetTransform():SetPosRot(shoulder_rest.pos, shoulder_rot)
	arm_node:GetTransform():SetPosRot(arm_rest.pos, arm_rot)
	forearm_node:GetTransform():SetPosRot(forearm_rest.pos, forearm_rot)
	hand_node:GetTransform():SetWorld(hg.TransformationMat4(hand_pos, hand_rot, hand_rest.scale))
end

function Controller:Update(dt)
	self:_restore_controlled_pose()
	local move_step = self:_update_root_motion(dt)
	self:_update_walk_phase(move_step)
	self:_update_hand_lock_blends(dt)
	self:_apply_walk_pose()
	self:_apply_arm_pose("left")
	self:_apply_arm_pose("right")
end

function Controller:IsMoving()
	return self.target_world ~= nil
end

function Controller:IsAtTarget()
	return self.arrived
end

function Controller:GetCurrentTargetNodeName()
	return self.target_node_name
end

function Controller:GetDebugState()
	return {
		state = self.state,
		target = self.target_node_name or "-",
		distance_to_target = self.distance_to_target,
		yaw_error_deg = math.deg(self.yaw_error),
		current_speed = self.current_speed,
		left_hand = self.hand_locks.left.target_name or "free",
		right_hand = self.hand_locks.right.target_name or "free"
	}
end

local function create_controller(scene, instance_node_name)
	local instance_node = ensure_valid_node(scene:GetNode(instance_node_name), instance_node_name)
	local controller = {
		scene = scene,
		instance_node = instance_node,
		scene_view = instance_node:GetInstanceSceneView(),
		host_nodes = {},
		view_nodes = {},
		rest_pose = {},
		hand_targets = {},
		target_world = nil,
		target_node_name = nil,
		arrived = false,
		state = "Idle",
		current_speed = 0.0,
		distance_to_target = 0.0,
		yaw_error = 0.0,
		walk_phase = 0.0,
		ground_y = instance_node:GetTransform():GetPos().y,
		params = {
			walk_speed = 2.1,
			turn_speed = hg.Deg(240.0),
			turn_in_place_angle = hg.Deg(42.0),
			arrive_distance = 0.08,
			step_cycle_distance = 1.15,
			hips_bob = 0.035,
			hips_sway = 0.018,
			leg_swing = hg.Deg(20.0),
			knee_bend = hg.Deg(34.0),
			foot_compensation = hg.Deg(15.0),
			shoulder_swing = hg.Deg(6.0),
			arm_swing = hg.Deg(18.0),
			forearm_swing = hg.Deg(10.0),
			hand_lock_blend_speed = 6.0,
			arm_lock_elbow_bend = hg.Deg(72.0),
			arm_lock_pitch_limit = hg.Deg(70.0),
			arm_lock_roll_limit = hg.Deg(70.0)
		},
		hand_locks = {
			left = {active = false, blend = 0.0, target_name = nil, target_node = nil},
			right = {active = false, blend = 0.0, target_name = nil, target_node = nil}
		},
		arm_lengths = {
			left = {upper = 0.0, lower = 0.0},
			right = {upper = 0.0, lower = 0.0}
		}
	}

	setmetatable(controller, Controller)

	for _, name in ipairs(CONTROLLED_NODE_NAMES) do
		controller.view_nodes[name] = controller:_get_view_node(name)
		controller.rest_pose[name] = capture_local_pose(controller.view_nodes[name])
	end

	controller.arm_lengths.left.upper = resolve_chain_length(controller.rest_pose["mixamorig:LeftForeArm"])
	controller.arm_lengths.left.lower = resolve_chain_length(controller.rest_pose["mixamorig:LeftHand"])
	controller.arm_lengths.right.upper = resolve_chain_length(controller.rest_pose["mixamorig:RightForeArm"])
	controller.arm_lengths.right.lower = resolve_chain_length(controller.rest_pose["mixamorig:RightHand"])

	return controller
end

return {
	CreateAutomatonController = create_controller
}
