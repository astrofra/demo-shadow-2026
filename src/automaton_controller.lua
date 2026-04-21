local hg = require("harfang")

local WORLD_UP = hg.Vec3(0.0, 1.0, 0.0)
local WORLD_RIGHT = hg.Vec3(1.0, 0.0, 0.0)
local WORLD_FRONT = hg.Vec3(0.0, 0.0, -1.0)

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
		sign = 1,
		upper = "mixamorig:LeftUpLeg",
		lower = "mixamorig:LeftLeg",
		foot = "mixamorig:LeftFoot",
		phase_offset = 0.0
	},
	right = {
		sign = -1,
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

local function right_from_yaw(yaw)
	return hg.Vec3(math.cos(yaw), 0.0, math.sin(yaw))
end

local function lerp_vec3(a, b, t)
	return hg.Lerp(a, b, t)
end

local function resolve_chain_length(rest_pose)
	return hg.Len(rest_pose.pos)
end

local function average_abs_scale(scale)
	return (math.abs(scale.x) + math.abs(scale.y) + math.abs(scale.z)) / 3.0
end

local function project_on_plane(value, normal)
	return value - normal * hg.Dot(value, normal)
end

local function make_basis_from_y(y_axis, z_hint)
	local y = safe_normalize(y_axis, WORLD_UP)
	local z = project_on_plane(z_hint, y)

	if hg.Len(z) <= 0.00001 then
		z = project_on_plane(WORLD_FRONT, y)
	end

	if hg.Len(z) <= 0.00001 then
		z = project_on_plane(WORLD_RIGHT, y)
	end

	z = safe_normalize(z, WORLD_FRONT)
	local x = safe_normalize(hg.Cross(y, z), WORLD_RIGHT)
	z = safe_normalize(hg.Cross(x, y), WORLD_FRONT)
	return hg.Normalize(hg.Mat3(x, y, z))
end

local function solve_two_bone_knee(root_pos, target_pos, pole_hint, upper_len, lower_len)
	local to_target = target_pos - root_pos
	local min_reach = math.abs(upper_len - lower_len) + 0.0001
	local max_reach = math.max(upper_len + lower_len - 0.0001, min_reach)
	local distance = clamp(hg.Len(to_target), min_reach, max_reach)
	local direction = safe_normalize(to_target, hg.Vec3(0.0, -1.0, 0.0))
	local pole = project_on_plane(pole_hint, direction)

	if hg.Len(pole) <= 0.00001 then
		pole = project_on_plane(WORLD_FRONT, direction)
	end

	pole = safe_normalize(pole, WORLD_UP)

	local along = (upper_len * upper_len - lower_len * lower_len + distance * distance) / (2.0 * distance)
	local height_sq = math.max(upper_len * upper_len - along * along, 0.0)
	return root_pos + direction * along + pole * math.sqrt(height_sq)
end

local function compute_step_drive(step_progress)
	if step_progress < 0.12 then
		return 0.0
	elseif step_progress < 0.22 then
		return (step_progress - 0.12) / 0.10 * 0.8
	elseif step_progress < 0.62 then
		return 1.0
	elseif step_progress < 0.78 then
		return 0.35
	end

	return 0.0
end

local function compute_swing_alpha(step_progress)
	if step_progress < 0.08 then
		return 0.0
	elseif step_progress < 0.82 then
		return (step_progress - 0.08) / 0.74
	end

	return 1.0
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
	self:_reset_gait_state()
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

function Controller:_get_foot_world(side_name)
	return get_world_position(self.view_nodes[LEG_SIDES[side_name].foot])
end

function Controller:_refresh_instance_scale()
	local scale = self.instance_node:GetTransform():GetScale()
	self.instance_scale = copy_vec3(scale)
	self.uniform_scale = math.max(average_abs_scale(scale), 0.0001)
end

function Controller:_scaled_distance(value)
	return value * self.uniform_scale
end

function Controller:_get_world_node_scale(local_scale)
	return hg.Vec3(
		local_scale.x * self.instance_scale.x,
		local_scale.y * self.instance_scale.y,
		local_scale.z * self.instance_scale.z
	)
end

function Controller:_reset_gait_state()
	self:_refresh_instance_scale()

	local root_position = self.instance_node:GetTransform():GetPos()
	local root_rotation = self.instance_node:GetTransform():GetRot()
	local facing = forward_from_yaw(root_rotation.y)
	local left_pos = self:_get_foot_world("left")
	local right_pos = self:_get_foot_world("right")

	self.foot_ground_y = math.min(left_pos.y, right_pos.y)
	left_pos.y = self.foot_ground_y
	right_pos.y = self.foot_ground_y

	self.feet.left.planted_world = copy_vec3(left_pos)
	self.feet.left.swing_from = copy_vec3(left_pos)
	self.feet.left.swing_to = copy_vec3(left_pos)
	self.feet.left.current_world = copy_vec3(left_pos)

	self.feet.right.planted_world = copy_vec3(right_pos)
	self.feet.right.swing_from = copy_vec3(right_pos)
	self.feet.right.swing_to = copy_vec3(right_pos)
	self.feet.right.current_world = copy_vec3(right_pos)

	local left_forward = hg.Dot(left_pos - root_position, facing)
	local right_forward = hg.Dot(right_pos - root_position, facing)

	self.support_side = left_forward <= right_forward and "left" or "right"
	self.swing_side = self.support_side == "left" and "right" or "left"
	self.step_active = false
	self.step_progress = 0.0
	self.walk_phase = self.support_side == "left" and 0.0 or math.pi
	self.current_forward = facing
	self.current_right = right_from_yaw(root_rotation.y)
	self.desired_direction = facing
end

function Controller:_compute_step_target(side_name)
	local side = LEG_SIDES[side_name]
	local hips_position = get_world_position(self.view_nodes["mixamorig:Hips"])
	local step_length_min = self:_scaled_distance(self.params.step_length_min)
	local step_length_max = self:_scaled_distance(self.params.step_length_max)
	local step_length = self:_scaled_distance(self.params.step_length_base + self.locomotion_speed * self.params.step_length_speed_scale)

	step_length = clamp(step_length, step_length_min, step_length_max)
	step_length = math.min(step_length, math.max(self.distance_to_target, 0.0))

	if self.distance_to_target < step_length_max then
		step_length = math.max(step_length * self.params.arrival_step_scale, step_length_min * 0.35)
	end

	hips_position.y = self.foot_ground_y

	local forward_offset = step_length * self.params.step_target_lead + self:_scaled_distance(self.params.step_forward_bias)
	local target = hips_position + self.desired_direction * forward_offset + self.current_right * (self:_scaled_distance(self.params.foot_spacing) * side.sign)
	target.y = self.foot_ground_y
	return target
end

function Controller:_begin_step()
	if self.step_active then
		return
	end

	local swing = self.feet[self.swing_side]
	swing.swing_from = copy_vec3(swing.planted_world)
	swing.swing_to = self:_compute_step_target(self.swing_side)
	swing.current_world = copy_vec3(swing.swing_from)
	self.step_progress = 0.0
	self.step_active = true
end

function Controller:_complete_step()
	local swing = self.feet[self.swing_side]
	swing.planted_world = copy_vec3(swing.swing_to)
	swing.current_world = copy_vec3(swing.swing_to)
	self.support_side = self.swing_side
	self.swing_side = self.support_side == "left" and "right" or "left"
	self.step_progress = 0.0
	self.step_active = false
end

function Controller:_update_footstep_state(dt)
	self.feet.left.current_world = copy_vec3(self.feet.left.planted_world)
	self.feet.right.current_world = copy_vec3(self.feet.right.planted_world)

	if not self.step_active then
		self.walk_phase = self.support_side == "left" and 0.0 or math.pi
		return
	end

	local step_speed = math.max(self.motion_weight, self.params.step_settle_weight)
	local swing = self.feet[self.swing_side]
	self.step_progress = clamp(self.step_progress + dt / self.params.step_duration * step_speed, 0.0, 1.0)

	local swing_alpha = compute_swing_alpha(self.step_progress)
	local foot_pos = lerp_vec3(swing.swing_from, swing.swing_to, swing_alpha)
	foot_pos.y = self.foot_ground_y + math.sin(swing_alpha * math.pi) * self:_scaled_distance(self.params.foot_lift_height)
	swing.current_world = foot_pos
	self.walk_phase = (self.support_side == "left" and 0.0 or math.pi) + self.step_progress * math.pi

	if self.step_progress >= 1.0 then
		self:_complete_step()
	end
end

function Controller:_update_root_motion(dt)
	self:_refresh_instance_scale()

	local instance_transform = self.instance_node:GetTransform()
	local position = instance_transform:GetPos()
	local rotation = instance_transform:GetRot()
	local move_step = 0.0

	self.state = "Idle"
	self.current_speed = 0.0
	self.desired_speed = 0.0
	self.distance_to_target = 0.0
	self.gait_drive = 0.0
	self.motion_weight = clamp(self.locomotion_speed / self.params.walk_speed, 0.0, 1.0)
	self.yaw_error = 0.0
	self.current_forward = forward_from_yaw(rotation.y)
	self.current_right = right_from_yaw(rotation.y)
	self.desired_direction = self.current_forward

	if self.target_world == nil then
		self.locomotion_speed = move_toward(self.locomotion_speed, 0.0, self.params.speed_deceleration * dt)
		self.motion_weight = clamp(self.locomotion_speed / self.params.walk_speed, 0.0, 1.0)
		self:_update_footstep_state(dt)
		return move_step
	end

	local to_target = flatten_xz(self.target_world - position)
	local distance = hg.Len(to_target)
	local arrive_distance = self:_scaled_distance(self.params.arrive_distance)
	self.distance_to_target = distance

	if distance <= arrive_distance then
		self.state = "Arrived"
		self.arrived = true
		self.target_world = nil
		self.target_node_name = nil
		self:_update_footstep_state(dt)
		return move_step
	end

	local desired_direction = safe_normalize(to_target, forward_from_yaw(rotation.y))
	local desired_yaw = atan2(desired_direction.x, -desired_direction.z)
	local yaw_error = shortest_angle_rad(rotation.y, desired_yaw)
	local yaw_step = clamp(yaw_error, -self.params.turn_speed * dt, self.params.turn_speed * dt)

	rotation.y = rotation.y + yaw_step
	instance_transform:SetRot(rotation)

	self.yaw_error = yaw_error
	self.current_forward = forward_from_yaw(rotation.y)
	self.current_right = right_from_yaw(rotation.y)
	self.desired_direction = desired_direction

	local facing = clamp(hg.Dot(self.current_forward, desired_direction), 0.0, 1.0)
	self.desired_speed = self.params.walk_speed * facing
	self.locomotion_speed = move_toward(
		self.locomotion_speed,
		self.desired_speed,
		(self.desired_speed > self.locomotion_speed and self.params.speed_acceleration or self.params.speed_deceleration) * dt
	)
	self.motion_weight = clamp(self.locomotion_speed / self.params.walk_speed, 0.0, 1.0)

	if math.abs(yaw_error) > self.params.turn_in_place_angle and not self.step_active then
		self.locomotion_speed = move_toward(self.locomotion_speed, 0.0, self.params.speed_deceleration * dt)
		self.motion_weight = clamp(self.locomotion_speed / self.params.walk_speed, 0.0, 1.0)
		self.state = "TurnInPlace"
		self:_update_footstep_state(dt)
		return move_step
	end

	if not self.step_active and self.motion_weight > self.params.step_start_weight then
		self:_begin_step()
	end

	self:_update_footstep_state(dt)
	self.gait_drive = self.step_active and compute_step_drive(self.step_progress) or 0.0
	self.current_speed = self.locomotion_speed * self.gait_drive

	move_step = math.min(distance, self.current_speed * dt)
	position = position + self.current_forward * move_step
	position.y = self.ground_y
	instance_transform:SetPos(position)
	self.distance_to_target = math.max(0.0, distance - move_step)
	self.state = move_step > 0.0 and "Walk" or "TurnInPlace"

	if self.distance_to_target <= arrive_distance and not self.step_active then
		self.state = "Arrived"
		self.arrived = true
		self.target_world = nil
		self.target_node_name = nil
	end

	return move_step
end

function Controller:_apply_hips_pose()
	local hips_transform = self.view_nodes["mixamorig:Hips"]:GetTransform()
	local hips_rest = self.rest_pose["mixamorig:Hips"]
	local support_sign = LEG_SIDES[self.support_side].sign
	local sway = self.params.hips_sway * support_sign * self.motion_weight
	local bob = math.sin(self.step_progress * math.pi) * self.params.hips_bob * self.motion_weight

	hips_transform:SetPosRot(
		hg.Vec3(hips_rest.pos.x + sway, hips_rest.pos.y - bob, hips_rest.pos.z),
		hips_rest.rot
	)
end

function Controller:_apply_leg_pose(side_name)
	local side = LEG_SIDES[side_name]
	local upper_node = self.view_nodes[side.upper]
	local lower_node = self.view_nodes[side.lower]
	local foot_node = self.view_nodes[side.foot]
	local upper_rest = self.rest_pose[side.upper]
	local lower_rest = self.rest_pose[side.lower]
	local foot_rest = self.rest_pose[side.foot]
	local hip_world = get_world_position(upper_node)
	local foot_target = copy_vec3(self.feet[side_name].current_world)
	local leg = self.leg_lengths[side_name]
	local upper_len = leg.upper * self.uniform_scale
	local lower_len = leg.lower * self.uniform_scale
	local pole_hint = self.current_forward * self.params.knee_forward_bias + self.current_right * (side.sign * self.params.knee_outward_bias)
	local knee_world = solve_two_bone_knee(hip_world, foot_target, pole_hint, upper_len, lower_len)
	local plane_normal = hg.Cross(knee_world - hip_world, foot_target - knee_world)

	if hg.Len(plane_normal) <= 0.00001 then
		plane_normal = self.current_right * side.sign
	end

	plane_normal = safe_normalize(plane_normal, self.current_right * side.sign)

	local upper_rot = hg.ToEuler(make_basis_from_y(knee_world - hip_world, plane_normal))
	local lower_basis = make_basis_from_y(foot_target - knee_world, plane_normal)
	local foot_pitch = 0.0
	local foot_yaw = self.params.foot_yaw_offset

	if side_name == "left" then
		foot_yaw = foot_yaw + self.params.left_foot_yaw_compensation
	end

	if side_name == "left" then
		lower_basis = hg.Normalize(lower_basis * hg.RotationMat3(hg.Vec3(0.0, self.params.left_calf_yaw_offset, 0.0)))
	end

	if self.step_active and self.swing_side == side_name then
		foot_pitch = self.params.swing_foot_pitch * math.sin(compute_swing_alpha(self.step_progress) * math.pi)
	end

	upper_node:GetTransform():SetWorld(hg.TransformationMat4(hip_world, upper_rot, self:_get_world_node_scale(upper_rest.scale)))
	lower_node:GetTransform():SetWorld(hg.TransformationMat4(knee_world, lower_basis, self:_get_world_node_scale(lower_rest.scale)))
	foot_node:GetTransform():SetPosRot(foot_rest.pos, foot_rest.rot + hg.Vec3(foot_pitch, foot_yaw, 0.0))
end

function Controller:_apply_walk_pose()
	self:_apply_hips_pose()
	self:_apply_leg_pose("left")
	self:_apply_leg_pose("right")
end

function Controller:_compute_free_arm_pose(side_name)
	local side = HAND_SIDES[side_name]
	local locomotion_weight = self.motion_weight
	local phase = self.walk_phase + (side_name == "left" and math.pi or 0.0)
	local swing = math.sin(phase) * locomotion_weight
	local shoulder_rest = self.rest_pose[side.shoulder]
	local arm_rest = self.rest_pose[side.arm]
	local forearm_rest = self.rest_pose[side.forearm]
	local hand_rest = self.rest_pose[side.hand]

	return {
		shoulder = shoulder_rest.rot + hg.Vec3(
			0.0,
			0.0,
			-side.sign * self.params.free_shoulder_drop + side.sign * self.params.free_shoulder_swing * swing
		),
		arm = arm_rest.rot + hg.Vec3(
			self.params.free_arm_pitch - self.params.free_arm_swing * swing,
			0.0,
			-side.sign * self.params.free_arm_drop
		),
		forearm = forearm_rest.rot + hg.Vec3(
			self.params.free_forearm_bend + math.max(0.0, -swing) * self.params.free_forearm_swing,
			0.0,
			0.0
		),
		hand = hand_rest.rot + hg.Vec3(self.params.free_hand_local_pitch, 0.0, 0.0)
	}
end

function Controller:_compute_arm_pose_to_world_target(side_name, target_hand_pos, target_hand_rot, options)
	local side = HAND_SIDES[side_name]
	local shoulder_node = self.view_nodes[side.shoulder]
	local hand_node = self.view_nodes[side.hand]
	local shoulder_world = shoulder_node:GetTransform():GetWorld()
	local target_local = hg.InverseFast(shoulder_world) * target_hand_pos
	local shoulder_rest = self.rest_pose[side.shoulder]
	local arm_rest = self.rest_pose[side.arm]
	local forearm_rest = self.rest_pose[side.forearm]
	local hand_rest_world = hand_node:GetTransform():GetWorld()
	local rel = target_local - arm_rest.pos
	local distance = math.max(hg.Len(rel), 0.0001)
	local reach_ratio = clamp(distance / (self.arm_lengths[side_name].upper + self.arm_lengths[side_name].lower), 0.0, 1.0)
	local rel_planar = math.max(math.sqrt(rel.x * rel.x + rel.y * rel.y), 0.0001)
	local aim_x = clamp(atan2(rel.z, rel_planar), -self.params.arm_lock_pitch_limit, self.params.arm_lock_pitch_limit)
	local aim_z = clamp(
		-atan2(rel.x * side.sign, math.max(math.abs(rel.y), 0.0001)) * side.sign,
		-self.params.arm_lock_roll_limit,
		self.params.arm_lock_roll_limit
	)
	local elbow = self.params.arm_lock_elbow_bend * (1.0 - reach_ratio)
	local current_hand_pos = hg.GetT(hand_rest_world)
	local current_hand_rot = hg.GetRotation(hand_rest_world)

	return {
		shoulder = shoulder_rest.rot + hg.Vec3(aim_x * 0.18, 0.0, aim_z * 0.55),
		arm = arm_rest.rot + hg.Vec3(aim_x - elbow * 0.32, 0.0, aim_z * 0.88),
		forearm = forearm_rest.rot + hg.Vec3(elbow, 0.0, 0.0),
		hand_world_pos = target_hand_pos,
		hand_world_rot = target_hand_rot,
		current_hand_world_pos = current_hand_pos,
		current_hand_world_rot = current_hand_rot
	}
end

function Controller:_compute_locked_arm_pose(side_name, target_node)
	local target_world = target_node:GetTransform():GetWorld()
	return self:_compute_arm_pose_to_world_target(side_name, hg.GetT(target_world), hg.GetRotation(target_world))
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
	local free_arm_rot = free_pose.arm

	if side_name == "left" then
		-- free_arm_rot = free_arm_rot + hg.Vec3(self.params.left_arm_pitch_offset, 0.0, 0.0)
	end

	shoulder_node:GetTransform():SetPosRot(shoulder_rest.pos, free_pose.shoulder)
	arm_node:GetTransform():SetPosRot(arm_rest.pos, free_arm_rot)
	forearm_node:GetTransform():SetPosRot(forearm_rest.pos, free_pose.forearm)
	hand_node:GetTransform():SetPosRot(hand_rest.pos, free_pose.hand)

	if lock_state.blend <= 0.0 or lock_state.target_node == nil then
		return
	end

	local locked_pose = self:_compute_locked_arm_pose(side_name, lock_state.target_node)
	local free_hand_world = hand_node:GetTransform():GetWorld()
	local blend = lock_state.blend
	local shoulder_rot = lerp_vec3(free_pose.shoulder, locked_pose.shoulder, blend)
	local arm_rot = lerp_vec3(free_pose.arm, locked_pose.arm, blend)
	local forearm_rot = lerp_vec3(free_pose.forearm, locked_pose.forearm, blend)
	local hand_pos = lerp_vec3(hg.GetT(free_hand_world), locked_pose.hand_world_pos, blend)
	local hand_rot = lerp_vec3(hg.GetRotation(free_hand_world), locked_pose.hand_world_rot, blend)

	if side_name == "left" then
		-- arm_rot = arm_rot + hg.Vec3(self.params.left_arm_pitch_offset, 0.0, 0.0)
	end

	shoulder_node:GetTransform():SetPosRot(shoulder_rest.pos, shoulder_rot)
	arm_node:GetTransform():SetPosRot(arm_rest.pos, arm_rot)
	forearm_node:GetTransform():SetPosRot(forearm_rest.pos, forearm_rot)
	hand_node:GetTransform():SetWorld(hg.TransformationMat4(hand_pos, hand_rot, self:_get_world_node_scale(hand_rest.scale)))
end

function Controller:Update(dt)
	self:_refresh_instance_scale()
	self:_restore_controlled_pose()
	self:_update_root_motion(dt)
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
		gait_drive = self.gait_drive,
		support_side = self.support_side,
		step_progress = self.step_progress,
		locomotion_speed = self.locomotion_speed,
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
		desired_speed = 0.0,
		locomotion_speed = 0.0,
		gait_drive = 0.0,
		motion_weight = 0.0,
		distance_to_target = 0.0,
		yaw_error = 0.0,
		walk_phase = 0.0,
		support_side = "left",
		swing_side = "right",
		step_active = false,
		step_progress = 0.0,
		instance_scale = copy_vec3(instance_node:GetTransform():GetScale()),
		uniform_scale = math.max(average_abs_scale(instance_node:GetTransform():GetScale()), 0.0001),
		foot_ground_y = instance_node:GetTransform():GetPos().y,
		current_forward = forward_from_yaw(instance_node:GetTransform():GetRot().y),
		current_right = right_from_yaw(instance_node:GetTransform():GetRot().y),
		desired_direction = forward_from_yaw(instance_node:GetTransform():GetRot().y),
		ground_y = instance_node:GetTransform():GetPos().y,
		params = {
			walk_speed = 1.8,
			turn_speed = hg.Deg(240.0),
			turn_in_place_angle = hg.Deg(42.0),
			arrive_distance = 0.08,
			step_duration = 0.48,
			step_length_min = 0.18,
			step_length_max = 0.46,
			step_length_base = 0.18,
			step_length_speed_scale = 0.08,
			step_target_lead = 0.72,
			step_forward_bias = 0.09,
			arrival_step_scale = 0.7,
			foot_spacing = 0.12,
			foot_lift_height = 0.11,
			step_settle_weight = 0.2,
			step_start_weight = 0.08,
			speed_acceleration = 1.8,
			speed_deceleration = 2.9,
			knee_forward_bias = 1.1,
			knee_outward_bias = 0.35,
			hips_bob = 0.012,
			hips_sway = 0.016,
			swing_foot_pitch = hg.Deg(8.0),
			left_calf_yaw_offset = -hg.Deg(90.0),
			foot_yaw_offset = -hg.Deg(90.0),
			left_foot_yaw_compensation = hg.Deg(90.0),
			free_shoulder_drop = hg.Deg(16.0),
			free_shoulder_swing = hg.Deg(5.0),
			free_arm_drop = hg.Deg(84.0),
			free_arm_pitch = hg.Deg(-10.0),
			free_arm_swing = hg.Deg(12.0),
			free_forearm_bend = hg.Deg(10.0),
			free_forearm_swing = hg.Deg(8.0),
			free_hand_local_pitch = hg.Deg(-6.0),
			left_arm_pitch_offset = -hg.Deg(90.0),
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
		},
		leg_lengths = {
			left = {upper = 0.0, lower = 0.0},
			right = {upper = 0.0, lower = 0.0}
		},
		feet = {
			left = {planted_world = hg.Vec3(), swing_from = hg.Vec3(), swing_to = hg.Vec3(), current_world = hg.Vec3()},
			right = {planted_world = hg.Vec3(), swing_from = hg.Vec3(), swing_to = hg.Vec3(), current_world = hg.Vec3()}
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
	controller.leg_lengths.left.upper = resolve_chain_length(controller.rest_pose["mixamorig:LeftLeg"])
	controller.leg_lengths.left.lower = resolve_chain_length(controller.rest_pose["mixamorig:LeftFoot"])
	controller.leg_lengths.right.upper = resolve_chain_length(controller.rest_pose["mixamorig:RightLeg"])
	controller.leg_lengths.right.lower = resolve_chain_length(controller.rest_pose["mixamorig:RightFoot"])
	controller:_reset_gait_state()

	return controller
end

return {
	CreateAutomatonController = create_controller
}
