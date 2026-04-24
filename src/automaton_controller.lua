local hg = require("harfang")

local WORLD_UP = hg.Vec3(0.0, 1.0, 0.0)
local WORLD_RIGHT = hg.Vec3(1.0, 0.0, 0.0)
local WORLD_FRONT = hg.Vec3(0.0, 0.0, -1.0)
-- Mixamo rig front is already consistent with the controller's logical -Z forward.
-- Keep the offset hook for future assets, but leave it disabled here.
local MODEL_FACING_YAW_OFFSET = 0.0

local HAND_SIDES = {
	left = {
		label = "Left",
		sign = 1,
		shoulder = "mixamorig_LeftShoulder",
		arm = "mixamorig_LeftArm",
		forearm = "mixamorig_LeftForeArm",
		hand = "mixamorig_LeftHand",
		grab_node = "GrabNodeLeft"
	},
	right = {
		label = "Right",
		sign = -1,
		shoulder = "mixamorig_RightShoulder",
		arm = "mixamorig_RightArm",
		forearm = "mixamorig_RightForeArm",
		hand = "mixamorig_RightHand",
		grab_node = "GrabNodeRight"
	}
}

local LEG_SIDES = {
	left = {
		sign = 1,
		upper = "mixamorig_LeftUpLeg",
		lower = "mixamorig_LeftLeg",
		foot = "mixamorig_LeftFoot",
		phase_offset = 0.0
	},
	right = {
		sign = -1,
		upper = "mixamorig_RightUpLeg",
		lower = "mixamorig_RightLeg",
		foot = "mixamorig_RightFoot",
		phase_offset = math.pi
	}
}

local LOOK_NODES = {
	neck = {
		node = "mixamorig_Neck",
		weight = 0.4
	},
	head = {
		node = "mixamorig_Head",
		weight = 0.6
	}
}

-- Offsets captured from walking-arms-along-the-body.scn to keep the
-- procedural pose aligned with the imported rig axes.
local FREE_ARM_NEUTRAL_OFFSETS = {
	left = {
		shoulder = hg.Vec3(0.0, 0.0, 0.0),
		arm = hg.Vec3(hg.Deg(-72.958258), hg.Deg(-10.400532), hg.Deg(-6.530455)),
		forearm = hg.Vec3(0.0, 0.0, 0.0),
		hand = hg.Vec3(0.0, 0.0, 0.0)
	},
	right = {
		shoulder = hg.Vec3(0.0, 0.0, 0.0),
		arm = hg.Vec3(hg.Deg(-75.792245), hg.Deg(1.559689), hg.Deg(9.952714)),
		forearm = hg.Vec3(0.0, 0.0, 0.0),
		hand = hg.Vec3(0.0, 0.0, 0.0)
	}
}

-- Deltas captured from walking-arms-and-legs.scn against
-- walking-arms-along-the-body.scn. The real swing is mostly on the
-- upper-arm local Z axis, and mirrored bones generate opposite world motion.
local FREE_ARM_WALK_SWING_OFFSETS = {
	left = {
		shoulder = hg.Vec3(0.0, 0.0, 0.0),
		arm = hg.Vec3(0.0, 0.0, hg.Deg(-40.254095)),
		forearm = hg.Vec3(0.0, 0.0, 0.0),
		hand = hg.Vec3(0.0, 0.0, 0.0)
	},
	right = {
		shoulder = hg.Vec3(0.0, 0.0, 0.0),
		arm = hg.Vec3(0.0, 0.0, hg.Deg(-46.066854)),
		forearm = hg.Vec3(0.0, 0.0, 0.0),
		hand = hg.Vec3(0.0, 0.0, 0.0)
	}
}

local ARM_IK_YAW_OFFSETS = {
	left = {
		upper = -hg.Deg(10.515554),
		lower = -hg.Deg(10.360635)
	},
	right = {
		upper = hg.Deg(11.743473),
		lower = hg.Deg(11.567876)
	}
}

local LEG_IK_YAW_OFFSETS = {
	left = {
		upper = -hg.Deg(90.292977),
		lower = -hg.Deg(91.566486)
	},
	right = {
		upper = -hg.Deg(89.092503),
		lower = -hg.Deg(88.215035)
	}
}

local CONTROLLED_NODE_NAMES = {
	"mixamorig_Hips",
	"mixamorig_Spine",
	"mixamorig_Spine1",
	"mixamorig_Spine2",
	"mixamorig_Neck",
	"mixamorig_Head",
	"mixamorig_LeftShoulder",
	"mixamorig_LeftArm",
	"mixamorig_LeftForeArm",
	"mixamorig_LeftHand",
	"mixamorig_RightShoulder",
	"mixamorig_RightArm",
	"mixamorig_RightForeArm",
	"mixamorig_RightHand",
	"mixamorig_LeftUpLeg",
	"mixamorig_LeftLeg",
	"mixamorig_LeftFoot",
	"mixamorig_RightUpLeg",
	"mixamorig_RightLeg",
	"mixamorig_RightFoot"
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

local function normalize_action_type(action_type)
	if type(action_type) ~= "string" then
		return ""
	end

	local normalized = string.lower(action_type)
	normalized = normalized:gsub("%-", "_")
	normalized = normalized:gsub("%s+", "_")
	return normalized
end

local function normalize_side(side_name)
	if type(side_name) ~= "string" then
		return nil
	end

	local normalized = string.lower(side_name)
	if normalized == "left" or normalized == "right" then
		return normalized
	end

	return nil
end

local function read_number_field(tbl, keys, label)
	if type(tbl) ~= "table" then
		return nil
	end

	for _, key in ipairs(keys) do
		local value = tbl[key]
		if value ~= nil then
			if type(value) ~= "number" then
				error(('AutomatonController: %s must be a number'):format(label))
			end

			return value
		end
	end

	return nil
end

local function read_vec3(value, label)
	if value == nil then
		return nil
	end

	local value_type = type(value)
	local x
	local y
	local z

	if value_type == "table" then
		x = value.x
		y = value.y
		z = value.z

		if x == nil then
			x = value[1]
		end
		if y == nil then
			y = value[2]
		end
		if z == nil then
			z = value[3]
		end
	else
		local ok
		ok, x, y, z = pcall(function()
			return value.x, value.y, value.z
		end)

		if not ok then
			x = nil
			y = nil
			z = nil
		end
	end

	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		error(('AutomatonController: %s must be a Vec3 or a table with x/y/z values'):format(label))
	end

	return hg.Vec3(x, y, z)
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

local function get_world_forward(node)
	return safe_normalize(hg.GetZ(node:GetTransform():GetWorld()) * -1.0, WORLD_FRONT)
end

local function get_world_forward_xz(node, fallback)
	return safe_normalize(flatten_xz(get_world_forward(node)), fallback)
end

local function compute_facing_from_landmarks(left_pos, right_pos, up_hint, fallback)
	local lateral = right_pos - left_pos
	local up = safe_normalize(up_hint, WORLD_UP)
	local forward = hg.Cross(up, lateral)
	return safe_normalize(flatten_xz(forward), fallback)
end

local function capture_world_matrix(node)
	local world = node:GetTransform():GetWorld()
	return hg.TransformationMat4(hg.GetT(world), hg.GetRotation(world), hg.GetS(world))
end

local function transform_point_to_local(world_matrix, point)
	local origin = hg.GetT(world_matrix)
	local offset = point - origin
	local x_axis = hg.GetX(world_matrix)
	local y_axis = hg.GetY(world_matrix)
	local z_axis = hg.GetZ(world_matrix)
	local x_scale = math.max(hg.Len(x_axis), 0.0001)
	local y_scale = math.max(hg.Len(y_axis), 0.0001)
	local z_scale = math.max(hg.Len(z_axis), 0.0001)

	x_axis = x_axis * (1.0 / x_scale)
	y_axis = y_axis * (1.0 / y_scale)
	z_axis = z_axis * (1.0 / z_scale)

	return hg.Vec3(
		hg.Dot(offset, x_axis) / x_scale,
		hg.Dot(offset, y_axis) / y_scale,
		hg.Dot(offset, z_axis) / z_scale
	)
end

local function ensure_valid_node(node, name)
	if not node:IsValid() then
		error(('AutomatonController: node "%s" is missing or invalid'):format(name))
	end

	return node
end

local function forward_from_yaw(yaw)
	return hg.Vec3(-math.sin(yaw), 0.0, -math.cos(yaw))
end

local function right_from_yaw(yaw)
	return hg.Vec3(math.cos(yaw), 0.0, -math.sin(yaw))
end

local function arm_phase_for_support_side(side_name)
	if side_name == "left" then
		return math.pi * 0.5
	end

	return math.pi * 1.5
end

local function lerp_vec3(a, b, t)
	return hg.Lerp(a, b, t)
end

local function smooth_step_alpha(dt, latency)
	if latency <= 0.0 then
		return 1.0
	end

	return clamp(1.0 - math.exp(-dt / latency), 0.0, 1.0)
end

local function smooth_euler(current, target, alpha)
	return hg.Vec3(
		current.x + shortest_angle_rad(current.x, target.x) * alpha,
		current.y + shortest_angle_rad(current.y, target.y) * alpha,
		current.z + shortest_angle_rad(current.z, target.z) * alpha
	)
end

local function look_rotation(from_pos, target_pos, fallback_rot)
	local to_target = target_pos - from_pos
	if hg.Len(to_target) <= 0.0001 then
		return fallback_rot
	end

	return hg.ToEuler(hg.Mat3LookAt(safe_normalize(to_target, WORLD_FRONT), WORLD_UP))
end

local function direction_to_world(world_matrix, local_direction, fallback)
	local x_axis = safe_normalize(hg.GetX(world_matrix), WORLD_RIGHT)
	local y_axis = safe_normalize(hg.GetY(world_matrix), WORLD_UP)
	local z_axis = safe_normalize(hg.GetZ(world_matrix), WORLD_FRONT)
	return safe_normalize(
		x_axis * local_direction.x + y_axis * local_direction.y + z_axis * local_direction.z,
		fallback
	)
end

local function normalized_world_basis(world_matrix)
	return hg.Normalize(hg.Mat3(
		safe_normalize(hg.GetX(world_matrix), WORLD_RIGHT),
		safe_normalize(hg.GetY(world_matrix), WORLD_UP),
		safe_normalize(hg.GetZ(world_matrix), WORLD_FRONT)
	))
end

local function set_world_pos_rot(node, position, rotation)
	local transform = node:GetTransform()
	local world = transform:GetWorld()
	transform:SetWorld(hg.TransformationMat4(position, rotation, hg.GetS(world)))
end

local function scale_vec3(value, scalar)
	return hg.Vec3(value.x * scalar, value.y * scalar, value.z * scalar)
end

local function rotate_xz(value, yaw)
	local cos_yaw = math.cos(yaw)
	local sin_yaw = math.sin(yaw)
	return hg.Vec3(
		value.x * cos_yaw - value.z * sin_yaw,
		value.y,
		value.x * sin_yaw + value.z * cos_yaw
	)
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

local function rotate_basis_y(basis, yaw)
	return hg.Normalize(basis * hg.RotationMat3(hg.Vec3(0.0, yaw, 0.0)))
end

local function solve_two_bone_joint(root_pos, target_pos, pole_hint, upper_len, lower_len)
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

function Controller:_get_model_yaw_from_root_rotation(root_yaw)
	return root_yaw + self.model_facing_yaw_offset
end

function Controller:_get_forward_from_root_rotation(root_yaw)
	return forward_from_yaw(self:_get_model_yaw_from_root_rotation(root_yaw))
end

function Controller:_get_right_from_root_rotation(root_yaw)
	return right_from_yaw(self:_get_model_yaw_from_root_rotation(root_yaw))
end

function Controller:_get_root_yaw_error(root_yaw, desired_model_yaw)
	return shortest_angle_rad(self:_get_model_yaw_from_root_rotation(root_yaw), desired_model_yaw)
end

function Controller:_get_view_node(name)
	local node = self.scene_view:GetNode(self.scene, name)
	return ensure_valid_node(node, name)
end

function Controller:_resolve_node_ref(node_ref)
	if type(node_ref) ~= "string" or node_ref == "" then
		error("AutomatonController: node reference must be a non-empty string")
	end

	local cached = self.node_refs[node_ref]
	if cached ~= nil and cached:IsValid() then
		return cached
	end

	local instance_name, internal_name = node_ref:match("^([^:]+):(.+)$")
	if instance_name ~= nil and internal_name ~= nil and internal_name ~= "" then
		local instance_node = nil
		local scene_view = nil
		if instance_name == self.instance_node_name then
			instance_node = self.instance_node
			scene_view = self.scene_view
		else
			instance_node = self.scene:GetNode(instance_name)
			if instance_node:IsValid() then
				scene_view = instance_node:GetInstanceSceneView()
			end
		end

		if instance_node ~= nil and instance_node:IsValid() and scene_view ~= nil then
			local instance_node_ref = scene_view:GetNode(self.scene, internal_name)
			if instance_node_ref:IsValid() then
				self.node_refs[node_ref] = instance_node_ref
				return instance_node_ref
			end
		end
	end

	local node = self.scene:GetNodeEx(node_ref)
	if node:IsValid() then
		self.node_refs[node_ref] = node
		return node
	end

	node = self.scene_view:GetNode(self.scene, node_ref)
	if node:IsValid() then
		self.node_refs[node_ref] = node
		return node
	end

	node = self.scene:GetNode(node_ref)
	if node:IsValid() then
		self.node_refs[node_ref] = node
		return node
	end

	error(('AutomatonController: node reference "%s" not found'):format(node_ref))
end

function Controller:_resolve_hand_target(name)
	return self:_resolve_node_ref(name)
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
		lock_state.blend = move_toward(lock_state.blend, blend_target, dt / self.params.hand_lock_blend_duration)

		if not lock_state.active and lock_state.blend <= 0.0 then
			lock_state.target_name = nil
			lock_state.target_node = nil
		end
	end
end

function Controller:_clear_move_target()
	self.target_world = nil
	self.arrived = false
	self.target_node_name = nil
end

function Controller:_clear_rotate_target()
	self.rotate_target_yaw = nil
	self.target_node_name = nil
	self.turn_step.active = false
	self.turn_step.delta_yaw = 0.0
	self.turn_step.applied_yaw = 0.0
end

function Controller:_set_move_target(target_name)
	self:_clear_rotate_target()

	local target_node = self:_resolve_node_ref(target_name)
	local target_position = get_world_position(target_node)

	self.target_node_name = target_name
	self.target_world = hg.Vec3(target_position.x, self.ground_y, target_position.z)
	self.arrived = false
end

function Controller:_compute_yaw_to_node(target_name, origin_position)
	local target_node = self:_resolve_node_ref(target_name)
	local target_position = get_world_position(target_node)
	local origin = origin_position or self.instance_node:GetTransform():GetPos()
	local to_target = flatten_xz(target_position - origin)

	if hg.Len(to_target) <= 0.0001 then
		return self:_get_model_yaw_from_root_rotation(self.instance_node:GetTransform():GetRot().y)
	end

	local desired_direction = safe_normalize(to_target, self.current_forward)
	return atan2(-desired_direction.x, -desired_direction.z)
end

function Controller:_set_rotate_target(target_name)
	self:_clear_move_target()
	self:_clear_rotate_target()

	self.target_node_name = target_name
	self.rotate_target_yaw = self:_compute_yaw_to_node(target_name)
	self.rotate_arrived = false
	self.arrived = false
	self.step_pause_timer = 0.0
end

function Controller:MoveToNode(target_name)
	self:_set_move_target(target_name)
end

function Controller:MoveFromNodeToNode(start_name, target_name)
	local start_node = self:_resolve_node_ref(start_name)
	local start_position = get_world_position(start_node)
	local instance_transform = self.instance_node:GetTransform()
	local instance_rotation = instance_transform:GetRot()

	instance_transform:SetPosRot(hg.Vec3(start_position.x, self.ground_y, start_position.z), instance_rotation)
	self:_reset_gait_state()
	self:_set_move_target(target_name)
end

function Controller:RotateToNode(target_name)
	self:_set_rotate_target(target_name)
end

function Controller:RotateFromNodeToNode(start_name, target_name)
	local start_node = self:_resolve_node_ref(start_name)
	local start_position = get_world_position(start_node)
	local instance_transform = self.instance_node:GetTransform()
	local instance_rotation = instance_transform:GetRot()

	instance_transform:SetPosRot(hg.Vec3(start_position.x, self.ground_y, start_position.z), instance_rotation)
	self:_reset_gait_state()
	self:_set_rotate_target(target_name)
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

function Controller:GrabNodeWithLeftHand(node_ref)
	self:_grab_node_with_hand("left", node_ref)
end

function Controller:GrabNodeWithRightHand(node_ref)
	self:_grab_node_with_hand("right", node_ref)
end

function Controller:ReleaseLeftHandObject()
	self:_release_hand_object("left")
end

function Controller:ReleaseRightHandObject()
	self:_release_hand_object("right")
end

function Controller:SetFreeArmAmplitude(side_name, amplitude)
	self:_set_free_arm_amplitude(side_name, amplitude)
end

function Controller:SetBendDegrees(degrees)
	self:_set_bend_target_deg(degrees)
end

function Controller:LookAtNode(node_ref)
	self:_set_look_at_target(node_ref)
end

function Controller:ClearLookAt()
	self:_clear_look_at_target()
end

function Controller:SetCurrentCamera(camera_name, options)
	self:_set_current_camera(camera_name, options or {})
end

function Controller:RunActionSequence(actions)
	if type(actions) ~= "table" then
		error("AutomatonController: RunActionSequence expects a Lua table")
	end

	self.action_runner.actions = actions
	self.action_runner.running = true
	self.action_runner.next_index = 1
	self.action_runner.current_action = nil
	self.action_runner.current_action_type = nil
	self.action_runner.current_action_index = 0
end

function Controller:StopActionSequence()
	self.action_runner.running = false
	self.action_runner.actions = nil
	self.action_runner.next_index = 1
	self.action_runner.current_action = nil
	self.action_runner.current_action_type = nil
	self.action_runner.current_action_index = 0
end

function Controller:IsActionSequenceRunning()
	return self.action_runner.running
end

function Controller:IsRotationDone()
	return self.rotate_target_yaw == nil
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
end

function Controller:_set_free_arm_amplitude(side_name, amplitude)
	local normalized_side = normalize_side(side_name)
	if normalized_side == nil then
		error(('AutomatonController: invalid side for arm amplitude: "%s"'):format(tostring(side_name)))
	end

	if type(amplitude) ~= "number" then
		error("AutomatonController: arm amplitude value must be a number")
	end

	self.free_arm_amplitude[normalized_side] = clamp(amplitude, 0.0, 1.0)
end

function Controller:_set_bend_target_deg(degrees)
	if type(degrees) ~= "number" then
		error("AutomatonController: bend value must be a number in degrees")
	end

	local bend_state = self.bend_state
	bend_state.start = bend_state.current
	bend_state.target = hg.Deg(degrees)
	bend_state.elapsed = 0.0
	bend_state.duration = self.params.bend_duration
	bend_state.active = true
end

function Controller:_set_look_at_target(target_name)
	local look_state = self.look_at_state
	look_state.target_name = target_name
	look_state.target_node = self:_resolve_node_ref(target_name)
	look_state.active = true
end

function Controller:_clear_look_at_target()
	self.look_at_state.active = false
end

function Controller:_update_look_at_blend(dt)
	local look_state = self.look_at_state
	local blend_target = look_state.active and 1.0 or 0.0

	look_state.blend = move_toward(look_state.blend, blend_target, dt / self.params.look_at_blend_duration)

	if not look_state.active and look_state.blend <= 0.0 then
		look_state.target_name = nil
		look_state.target_node = nil
		look_state.yaw = 0.0
		look_state.pitch = 0.0
	end
end

function Controller:_resolve_camera_node(camera_name)
	local node = self:_resolve_node_ref(camera_name)
	local transform = node:GetTransform()
	if not transform:IsValid() then
		error(('AutomatonController: camera node "%s" has no valid Transform component'):format(camera_name))
	end

	local camera = node:GetCamera()
	if not camera:IsValid() then
		error(('AutomatonController: node "%s" has no valid Camera component'):format(camera_name))
	end

	return node, camera
end

function Controller:_resolve_camera_target_node()
	local camera_state = self.camera_state
	if camera_state.target_name == nil then
		return nil
	end

	if camera_state.target_node ~= nil and camera_state.target_node:IsValid() and camera_state.target_node:GetTransform():IsValid() then
		return camera_state.target_node
	end

	local ok, node = pcall(function()
		return self:_resolve_node_ref(camera_state.target_name)
	end)

	if ok and node ~= nil and node:IsValid() and node:GetTransform():IsValid() then
		camera_state.target_node = node
		return node
	end

	camera_state.target_node = nil
	return nil
end

function Controller:_extract_camera_target(option, fallback_target, option_name)
	if type(option) == "string" then
		return option
	elseif type(option) == "table" then
		return option.target or option.node or option.name or option[1]
	elseif option == true then
		return fallback_target
	elseif option == nil or option == false then
		return nil
	end

	error(('AutomatonController: %s must be a node name or an option table'):format(option_name))
end

function Controller:_read_camera_option_number(option, keys, action, action_keys, default_value, label)
	local value = read_number_field(option, keys, label)
	if value == nil then
		value = read_number_field(action, action_keys, label)
	end
	if value == nil then
		return default_value
	end

	return value
end

function Controller:_read_camera_offset(option, action)
	local offset_value = nil

	if type(option) == "table" then
		offset_value = option.offset
	end

	if offset_value == nil then
		offset_value = action.offset
	end

	return read_vec3(offset_value, "camera offset") or hg.Vec3(0.0, 0.0, 0.0)
end

function Controller:_configure_camera_fov(camera, options)
	local fov_deg = read_number_field(options, {"fov", "FOV"}, "camera FOV")
	local camera_state = self.camera_state

	if fov_deg == nil then
		camera_state.fov_active = false
		return
	end

	if fov_deg <= 0.0 or fov_deg >= 179.0 then
		error("AutomatonController: camera FOV must be between 0 and 179 degrees")
	end

	camera_state.fov_active = true
	camera_state.fov_elapsed = 0.0
	camera_state.fov_duration = self.params.camera_fov_blend_duration
	camera_state.fov_start = camera:GetFov()
	camera_state.fov_target = hg.Deg(fov_deg)
end

function Controller:_set_current_camera(camera_name, options)
	if type(camera_name) ~= "string" or camera_name == "" then
		error("AutomatonController: camera command requires a non-empty camera node name")
	end

	local camera_node, camera = self:_resolve_camera_node(camera_name)
	local tracking_option = options.tracking or options.track
	local steady_option = options.steady_cam or options.steadycam or options.steady or options["steady cam"] or options["steady-cam"]
	local has_tracking = tracking_option ~= nil and tracking_option ~= false
	local has_steady = steady_option ~= nil and steady_option ~= false

	if has_tracking and has_steady then
		error("AutomatonController: camera command cannot use tracking and steady_cam at the same time")
	end

	self.scene:SetCurrentCamera(camera_node)

	local camera_state = self.camera_state
	camera_state.node_name = camera_name
	camera_state.node = camera_node
	camera_state.mode = "static"
	camera_state.target_name = nil
	camera_state.target_node = nil
	camera_state.previous_target_pos = nil
	camera_state.velocity_dir = nil
	camera_state.target_offset = hg.Vec3(0.0, 0.0, 0.0)
	camera_state.steady_height_offset = 0.0
	camera_state.tracking_latency = self.params.camera_tracking_latency
	camera_state.steady_position_latency = self.params.camera_steady_position_latency
	camera_state.steady_rotation_latency = self.params.camera_steady_rotation_latency
	camera_state.steady_distance = self.params.camera_steady_distance
	camera_state.steady_angle = self.params.camera_steady_angle

	self:_configure_camera_fov(camera, options)

	if has_tracking then
		local target_name = self:_extract_camera_target(tracking_option, options.target, "camera tracking")
		if type(target_name) ~= "string" or target_name == "" then
			error("AutomatonController: camera tracking requires a non-empty target node name")
		end

		camera_state.mode = "tracking"
		camera_state.target_name = target_name
		camera_state.target_node = self:_resolve_node_ref(target_name)
		camera_state.target_offset = self:_read_camera_offset(tracking_option, options)
		if not camera_state.target_node:GetTransform():IsValid() then
			error(('AutomatonController: camera tracking target "%s" has no valid Transform component'):format(target_name))
		end
		camera_state.tracking_latency = self:_read_camera_option_number(
			tracking_option,
			{"latency", "rotation_latency"},
			options,
			{"tracking_latency", "latency"},
			self.params.camera_tracking_latency,
			"camera tracking latency"
		)
		if camera_state.tracking_latency < 0.0 then
			error("AutomatonController: camera tracking latency must be greater than or equal to 0")
		end
	elseif has_steady then
		local target_name = self:_extract_camera_target(steady_option, options.target, "camera steady_cam")
		if type(target_name) ~= "string" or target_name == "" then
			error("AutomatonController: camera steady_cam requires a non-empty target node name")
		end

		local target_node = self:_resolve_node_ref(target_name)
		if not target_node:GetTransform():IsValid() then
			error(('AutomatonController: camera steady_cam target "%s" has no valid Transform component'):format(target_name))
		end
		camera_state.target_offset = self:_read_camera_offset(steady_option, options)
		local target_pos = get_world_position(target_node) + camera_state.target_offset
		local camera_pos = get_world_position(camera_node)

		camera_state.mode = "steady_cam"
		camera_state.target_name = target_name
		camera_state.target_node = target_node
		camera_state.previous_target_pos = copy_vec3(target_pos)
		camera_state.velocity_dir = nil
		camera_state.steady_height_offset = camera_pos.y - target_pos.y
		camera_state.steady_distance = self:_read_camera_option_number(
			steady_option,
			{"distance"},
			options,
			{"distance"},
			self.params.camera_steady_distance,
			"camera steady_cam distance"
		)
		if camera_state.steady_distance <= 0.0 then
			error("AutomatonController: camera steady_cam distance must be greater than 0")
		end
		camera_state.steady_angle = hg.Deg(self:_read_camera_option_number(
			steady_option,
			{"angle", "angle_deg"},
			options,
			{"angle", "angle_deg"},
			math.deg(self.params.camera_steady_angle),
			"camera steady_cam angle"
		))
		camera_state.steady_position_latency = self:_read_camera_option_number(
			steady_option,
			{"latency", "position_latency"},
			options,
			{"steady_latency", "position_latency", "latency"},
			self.params.camera_steady_position_latency,
			"camera steady_cam latency"
		)
		if camera_state.steady_position_latency < 0.0 then
			error("AutomatonController: camera steady_cam latency must be greater than or equal to 0")
		end
		camera_state.steady_rotation_latency = self:_read_camera_option_number(
			steady_option,
			{"rotation_latency"},
			options,
			{"rotation_latency"},
			self.params.camera_steady_rotation_latency,
			"camera steady_cam rotation latency"
		)
		if camera_state.steady_rotation_latency < 0.0 then
			error("AutomatonController: camera steady_cam rotation latency must be greater than or equal to 0")
		end
	end
end

function Controller:_run_camera_action(action)
	local camera_name = action.camera or action.camera_node or action.node or action.name
	if camera_name == nil and action.tracking == nil and action.track == nil and action.steady_cam == nil and action.steadycam == nil and action.steady == nil and action["steady cam"] == nil and action["steady-cam"] == nil then
		camera_name = action.target
	end

	self:SetCurrentCamera(camera_name, action)
end

function Controller:_update_camera_fov(dt)
	local camera_state = self.camera_state
	if not camera_state.fov_active or camera_state.node == nil or not camera_state.node:IsValid() then
		return
	end

	local camera = camera_state.node:GetCamera()
	if not camera:IsValid() then
		camera_state.fov_active = false
		return
	end

	camera_state.fov_elapsed = math.min(camera_state.fov_elapsed + dt, camera_state.fov_duration)
	local blend = camera_state.fov_duration > 0.0 and (camera_state.fov_elapsed / camera_state.fov_duration) or 1.0
	camera:SetFov(camera_state.fov_start + (camera_state.fov_target - camera_state.fov_start) * blend)

	if blend >= 1.0 then
		camera_state.fov_active = false
	end
end

function Controller:_update_camera_tracking(dt, target_node)
	local camera_state = self.camera_state
	local camera_node = camera_state.node
	if camera_node == nil or not camera_node:IsValid() then
		return
	end

	local camera_pos = get_world_position(camera_node)
	local camera_rot = get_world_rotation(camera_node)
	local target_pos = get_world_position(target_node) + camera_state.target_offset
	local desired_rot = look_rotation(camera_pos, target_pos, camera_rot)
	local alpha = smooth_step_alpha(dt, camera_state.tracking_latency)
	set_world_pos_rot(camera_node, camera_pos, smooth_euler(camera_rot, desired_rot, alpha))
end

function Controller:_update_camera_steady(dt, target_node)
	local camera_state = self.camera_state
	local camera_node = camera_state.node
	if camera_node == nil or not camera_node:IsValid() then
		return
	end

	local target_pos = get_world_position(target_node) + camera_state.target_offset
	if camera_state.previous_target_pos == nil then
		camera_state.previous_target_pos = copy_vec3(target_pos)
	end

	local displacement = flatten_xz(target_pos - camera_state.previous_target_pos)
	if hg.Len(displacement) >= self.params.camera_velocity_min_distance then
		local velocity_dir = safe_normalize(displacement, camera_state.velocity_dir or WORLD_FRONT)
		if camera_state.velocity_dir == nil then
			camera_state.velocity_dir = velocity_dir
		else
			local velocity_alpha = smooth_step_alpha(dt, self.params.camera_velocity_latency)
			camera_state.velocity_dir = safe_normalize(lerp_vec3(camera_state.velocity_dir, velocity_dir, velocity_alpha), velocity_dir)
		end

		camera_state.previous_target_pos = copy_vec3(target_pos)
	end

	local camera_pos = get_world_position(camera_node)
	local desired_pos = camera_pos

	if camera_state.velocity_dir ~= nil then
		local offset_dir = rotate_xz(camera_state.velocity_dir, camera_state.steady_angle)
		desired_pos = target_pos + offset_dir * camera_state.steady_distance
		desired_pos.y = target_pos.y + camera_state.steady_height_offset
		camera_pos = lerp_vec3(camera_pos, desired_pos, smooth_step_alpha(dt, camera_state.steady_position_latency))
	end

	local camera_rot = get_world_rotation(camera_node)
	local desired_rot = look_rotation(camera_pos, target_pos, camera_rot)
	local rotation_alpha = smooth_step_alpha(dt, camera_state.steady_rotation_latency)
	set_world_pos_rot(camera_node, camera_pos, smooth_euler(camera_rot, desired_rot, rotation_alpha))
end

function Controller:_update_camera_state(dt)
	local camera_state = self.camera_state
	if camera_state.node == nil then
		return
	end

	self:_update_camera_fov(dt)

	if camera_state.mode == "static" then
		return
	end

	local target_node = self:_resolve_camera_target_node()
	if target_node == nil then
		return
	end

	if camera_state.mode == "tracking" then
		self:_update_camera_tracking(dt, target_node)
	elseif camera_state.mode == "steady_cam" then
		self:_update_camera_steady(dt, target_node)
	end
end

function Controller:_ensure_hand_attach_proxy(side_name)
	local proxy_node = self.hand_attach_proxies[side_name]
	if proxy_node ~= nil and proxy_node:IsValid() then
		return proxy_node
	end

	proxy_node = self.scene:CreateNode(("%s_%s_hand_proxy"):format(self.instance_node_name, side_name))
	proxy_node:SetTransform(self.scene:CreateTransform(hg.Vec3(0.0, 0.0, 0.0), hg.Vec3(0.0, 0.0, 0.0), hg.Vec3(1.0, 1.0, 1.0)))
	self.hand_attach_proxies[side_name] = proxy_node
	return proxy_node
end

function Controller:_update_hand_attach_proxies()
	for _, side_name in ipairs({"left", "right"}) do
		local proxy_node = self.hand_attach_proxies[side_name]
		if proxy_node ~= nil and proxy_node:IsValid() then
			local attach_node = self:_get_grab_attach_node(side_name)
			proxy_node:GetTransform():SetWorld(attach_node:GetTransform():GetWorld())
		end
	end
end

function Controller:_clear_held_object_state(side_name)
	local held = self.held_objects[side_name]
	held.node = nil
	held.node_ref = nil
	held.original_parent = nil
	held.attached_parent = nil
	held.using_proxy = false
end

function Controller:_get_grab_attach_node(side_name)
	local side = HAND_SIDES[side_name]
	local grab_node = self.scene_view:GetNode(self.scene, side.grab_node)
	if grab_node:IsValid() then
		return grab_node
	end

	return self.view_nodes[side.hand]
end

function Controller:_attach_node_to_hand(side_name, node)
	local attach_node = self:_get_grab_attach_node(side_name)
	local transform = node:GetTransform()
	local zero = hg.Vec3(0.0, 0.0, 0.0)
	local ok = pcall(function()
		transform:SetParent(attach_node)
		transform:SetPosRot(zero, zero)
	end)

	if ok then
		local parent = transform:GetParent()
		if parent:IsValid() and parent:GetUid() == attach_node:GetUid() then
			return attach_node, false
		end
	end

	local proxy_node = self:_ensure_hand_attach_proxy(side_name)
	proxy_node:GetTransform():SetWorld(attach_node:GetTransform():GetWorld())
	transform:SetParent(proxy_node)
	transform:SetPosRot(zero, zero)
	return proxy_node, true
end

function Controller:_grab_node_with_hand(side_name, node_ref)
	local normalized_side = normalize_side(side_name)
	if normalized_side == nil then
		error(('AutomatonController: invalid hand side "%s"'):format(tostring(side_name)))
	end

	local node = self:_resolve_node_ref(node_ref)
	local transform = node:GetTransform()
	if not transform:IsValid() then
		error(('AutomatonController: node "%s" has no valid Transform component'):format(node_ref))
	end

	local other_side = normalized_side == "left" and "right" or "left"
	local held_other = self.held_objects[other_side]
	if held_other.node ~= nil and held_other.node:IsValid() and held_other.node:GetUid() == node:GetUid() then
		self:_release_hand_object(other_side)
	end

	local held = self.held_objects[normalized_side]
	if held.node ~= nil and held.node:IsValid() and held.node:GetUid() ~= node:GetUid() then
		self:_release_hand_object(normalized_side)
	elseif held.node ~= nil and held.node:IsValid() and held.node:GetUid() == node:GetUid() then
		self:_release_hand_object(normalized_side)
	end

	held.original_parent = transform:GetParent()
	held.node = node
	held.node_ref = node_ref
	held.attached_parent, held.using_proxy = self:_attach_node_to_hand(normalized_side, node)
end

function Controller:_release_hand_object(side_name)
	local normalized_side = normalize_side(side_name)
	if normalized_side == nil then
		error(('AutomatonController: invalid hand side "%s"'):format(tostring(side_name)))
	end

	local held = self.held_objects[normalized_side]
	if held.node == nil or not held.node:IsValid() then
		self:_clear_held_object_state(normalized_side)
		return
	end

	local transform = held.node:GetTransform()
	local world = capture_world_matrix(held.node)

	if held.original_parent ~= nil and held.original_parent:IsValid() then
		transform:SetParent(held.original_parent)
	else
		transform:ClearParent()
	end

	transform:SetWorld(world)
	self:_clear_held_object_state(normalized_side)
end

function Controller:_refresh_look_at_angles()
	local look_state = self.look_at_state
	if look_state.target_name == nil then
		return
	end

	if look_state.target_node == nil or not look_state.target_node:IsValid() then
		local ok, resolved_node = pcall(function()
			return self:_resolve_node_ref(look_state.target_name)
		end)

		if ok then
			look_state.target_node = resolved_node
		else
			look_state.target_node = nil
			return
		end
	end

	local head_node = self.view_nodes[LOOK_NODES.head.node]
	local head_rest_world = head_node:GetTransform():GetWorld()
	local target_position = get_world_position(look_state.target_node)
	local target_local = transform_point_to_local(head_rest_world, target_position)
	local planar_distance = math.max(math.sqrt(target_local.x * target_local.x + target_local.z * target_local.z), 0.0001)
	local yaw = atan2(-target_local.x, target_local.z)
	local pitch = atan2(target_local.y, planar_distance)

	look_state.yaw = clamp(yaw, -self.params.look_at_yaw_limit, self.params.look_at_yaw_limit)
	look_state.pitch = clamp(pitch, self.params.look_at_pitch_down_limit, self.params.look_at_pitch_up_limit)
end

function Controller:_apply_look_at_pose()
	local look_state = self.look_at_state
	if look_state.blend <= 0.0 and not look_state.active then
		return
	end

	local baseline_world = {}
	for _, look_key in ipairs({"neck", "head"}) do
		local look_def = LOOK_NODES[look_key]
		baseline_world[look_key] = capture_world_matrix(self.view_nodes[look_def.node])
	end

	for _, look_key in ipairs({"neck", "head"}) do
		local look_def = LOOK_NODES[look_key]
		local node = self.view_nodes[look_def.node]
		local weight = look_def.weight * look_state.blend
		if weight > 0.0 and look_state.target_node ~= nil and look_state.target_node:IsValid() then
			local current_world = node:GetTransform():GetWorld()
			local reference_world = baseline_world[look_key]
			local node_position = hg.GetT(current_world)
			local target_position = get_world_position(look_state.target_node)
			local target_local = transform_point_to_local(reference_world, target_position)
			local planar_distance = math.max(math.sqrt(target_local.x * target_local.x + target_local.z * target_local.z), 0.0001)
			local yaw = clamp(atan2(-target_local.x, target_local.z), -self.params.look_at_yaw_limit, self.params.look_at_yaw_limit)
			local pitch = clamp(atan2(target_local.y, planar_distance), self.params.look_at_pitch_down_limit, self.params.look_at_pitch_up_limit)
			local clamped_local_direction = hg.Vec3(
				-math.sin(yaw) * math.cos(pitch),
				math.sin(pitch),
				math.cos(yaw) * math.cos(pitch)
			)
			local target_world_direction = direction_to_world(reference_world, clamped_local_direction, safe_normalize(hg.GetZ(reference_world), WORLD_FRONT))
			local target_basis = hg.Mat3LookAt(
				safe_normalize(target_world_direction * -1.0, WORLD_FRONT),
				safe_normalize(hg.GetY(reference_world), WORLD_UP)
			)
			local current_basis = normalized_world_basis(current_world)
			local current_quat = hg.QuaternionFromMatrix3(current_basis)
			local target_quat = hg.QuaternionFromMatrix3(target_basis)
			local blended_basis = hg.ToMatrix3(hg.Normalize(hg.Slerp(current_quat, target_quat, weight)))

			node:GetTransform():SetWorld(hg.TransformationMat4(
				node_position,
				blended_basis,
				self:_get_world_node_scale(self.rest_pose[look_def.node].scale)
			))
		end
	end
end

function Controller:_apply_grabbed_objects()
	self:_update_hand_attach_proxies()
end

function Controller:_run_action(action)
	local action_type = normalize_action_type(action.type)

	if action_type == "move" then
		if action.start ~= nil then
			self:MoveFromNodeToNode(action.start, action.target)
		else
			self:MoveToNode(action.target)
		end
	elseif action_type == "rotate" then
		if action.start ~= nil then
			self:RotateFromNodeToNode(action.start, action.target)
		else
			self:RotateToNode(action.target)
		end
	elseif action_type == "lock_arm" then
		local side = normalize_side(action.side)
		if side == "left" then
			self:PlaceLeftHandOnNode(action.target)
		elseif side == "right" then
			self:PlaceRightHandOnNode(action.target)
		else
			error(('AutomatonController: invalid side for lock_arm: "%s"'):format(tostring(action.side)))
		end
	elseif action_type == "unlock_arm" then
		local side = normalize_side(action.side)
		if side == "left" then
			self:UnlockLeftHand()
		elseif side == "right" then
			self:UnlockRightHand()
		else
			error(('AutomatonController: invalid side for unlock_arm: "%s"'):format(tostring(action.side)))
		end
	elseif action_type == "grab" then
		local side = normalize_side(action.side)
		if side == "left" then
			self:GrabNodeWithLeftHand(action.target)
		elseif side == "right" then
			self:GrabNodeWithRightHand(action.target)
		else
			error(('AutomatonController: invalid side for grab: "%s"'):format(tostring(action.side)))
		end
	elseif action_type == "release" then
		local side = normalize_side(action.side)
		if side == "left" then
			self:ReleaseLeftHandObject()
		elseif side == "right" then
			self:ReleaseRightHandObject()
		else
			error(('AutomatonController: invalid side for release: "%s"'):format(tostring(action.side)))
		end
	elseif action_type == "arm_amplitude" then
		self:SetFreeArmAmplitude(action.side, read_number_field(action, {"value", "amplitude"}, "arm_amplitude value"))
	elseif action_type == "bend" then
		self:SetBendDegrees(read_number_field(action, {"value", "degrees", "angle"}, "bend value"))
	elseif action_type == "look_at" then
		self:LookAtNode(action.target)
	elseif action_type == "clear_look_at" then
		self:ClearLookAt()
	elseif action_type == "camera" or action_type == "set_camera" then
		self:_run_camera_action(action)
	else
		error(('AutomatonController: unsupported action type "%s"'):format(tostring(action.type)))
	end
end

function Controller:_is_action_complete(action)
	local action_type = normalize_action_type(action.type)

	if action_type == "move" then
		return self:IsAtTarget()
	elseif action_type == "rotate" then
		return self:IsRotationDone()
	elseif action_type == "lock_arm" then
		local side = normalize_side(action.side)
		return side ~= nil and self.hand_locks[side].blend >= 1.0
	elseif action_type == "unlock_arm" then
		local side = normalize_side(action.side)
		return side ~= nil and self.hand_locks[side].blend <= 0.0
	elseif action_type == "grab" or action_type == "release" or action_type == "camera" or action_type == "set_camera" or action_type == "arm_amplitude" then
		return true
	elseif action_type == "bend" then
		return not self.bend_state.active
	elseif action_type == "look_at" then
		return self.look_at_state.blend >= 1.0
	elseif action_type == "clear_look_at" then
		return self.look_at_state.blend <= 0.0
	end

	return true
end

function Controller:_update_action_runner()
	local runner = self.action_runner
	if not runner.running then
		return
	end

	while runner.running do
		if runner.current_action == nil then
			local next_action = runner.actions ~= nil and runner.actions[runner.next_index] or nil
			if next_action == nil then
				runner.running = false
				runner.actions = nil
				runner.current_action_type = nil
				runner.current_action_index = 0
				return
			end

			runner.current_action = next_action
			runner.current_action_type = normalize_action_type(next_action.type)
			runner.current_action_index = runner.next_index
			runner.next_index = runner.next_index + 1
			self:_run_action(next_action)
		end

		if self:_is_action_complete(runner.current_action) then
			runner.current_action = nil
			runner.current_action_type = nil
		else
			return
		end
	end
end

function Controller:_get_foot_world(side_name)
	return get_world_position(self.view_nodes[LEG_SIDES[side_name].foot])
end

function Controller:_refresh_instance_scale()
	local scale = self.instance_node:GetTransform():GetScale()
	self.instance_scale = copy_vec3(scale)
	self.uniform_scale = math.max(average_abs_scale(scale), 0.0001)
end

function Controller:_update_bend_state(dt)
	local bend_state = self.bend_state
	if not bend_state.active then
		return
	end

	if bend_state.duration <= 0.0 then
		bend_state.current = bend_state.target
		bend_state.active = false
		return
	end

	bend_state.elapsed = math.min(bend_state.elapsed + dt, bend_state.duration)
	local alpha = clamp(bend_state.elapsed / bend_state.duration, 0.0, 1.0)
	bend_state.current = bend_state.start + (bend_state.target - bend_state.start) * alpha

	if alpha >= 1.0 then
		bend_state.current = bend_state.target
		bend_state.active = false
	end
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
	local facing = self:_get_forward_from_root_rotation(root_rotation.y)
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
	self.step_pause_timer = 0.0
	self.next_step_pause_duration = self.params.step_pause_duration
	self.walk_phase = arm_phase_for_support_side(self.support_side)
	self.current_forward = facing
	self.current_right = self:_get_right_from_root_rotation(root_rotation.y)
	self.desired_direction = facing
end

function Controller:_compute_step_target(side_name)
	local side = LEG_SIDES[side_name]
	local hips_position = get_world_position(self.view_nodes["mixamorig_Hips"])
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
	if self.step_active or self.step_pause_timer > 0.0 then
		return
	end

	self.next_step_pause_duration = self.params.step_pause_duration

	local swing = self.feet[self.swing_side]
	swing.swing_from = copy_vec3(swing.planted_world)
	swing.swing_to = self:_compute_step_target(self.swing_side)
	swing.current_world = copy_vec3(swing.swing_from)
	self.step_progress = 0.0
	self.step_active = true
end

function Controller:_begin_rotate_step(yaw_error)
	if self.step_active or self.step_pause_timer > 0.0 then
		return
	end

	local step_delta = clamp(yaw_error, -self.params.rotate_step_angle, self.params.rotate_step_angle)
	if math.abs(step_delta) <= 0.0001 then
		return
	end

	local support = self.feet[self.support_side]
	local swing = self.feet[self.swing_side]
	local swing_offset = swing.planted_world - support.planted_world
	local swing_target = support.planted_world + rotate_xz(hg.Vec3(swing_offset.x, 0.0, swing_offset.z), step_delta)

	swing_target.y = self.foot_ground_y
	swing.swing_from = copy_vec3(swing.planted_world)
	swing.swing_to = swing_target
	swing.current_world = copy_vec3(swing.swing_from)
	self.step_progress = 0.0
	self.step_active = true
	self.next_step_pause_duration = self.params.rotate_step_pause_duration
	self.turn_step.active = true
	self.turn_step.delta_yaw = step_delta
	self.turn_step.applied_yaw = 0.0
	self.turn_step.pivot_world = copy_vec3(support.planted_world)
end

function Controller:_apply_turn_step_rotation(step_progress)
	if not self.turn_step.active then
		return
	end

	local desired_applied_yaw = self.turn_step.delta_yaw * step_progress
	local delta_yaw = desired_applied_yaw - self.turn_step.applied_yaw
	if math.abs(delta_yaw) <= 0.000001 then
		return
	end

	local instance_transform = self.instance_node:GetTransform()
	local position = instance_transform:GetPos()
	local rotation = instance_transform:GetRot()
	local pivot = self.turn_step.pivot_world
	local relative = position - pivot

	rotation.y = rotation.y + delta_yaw
	position = pivot + rotate_xz(relative, delta_yaw)
	position.y = self.ground_y
	instance_transform:SetPosRot(position, rotation)
	self.turn_step.applied_yaw = desired_applied_yaw
end

function Controller:_complete_step()
	local swing = self.feet[self.swing_side]
	swing.planted_world = copy_vec3(swing.swing_to)
	swing.current_world = copy_vec3(swing.swing_to)
	self.support_side = self.swing_side
	self.swing_side = self.support_side == "left" and "right" or "left"
	self.step_progress = 0.0
	self.step_active = false
	self.step_pause_timer = self.next_step_pause_duration
	self.walk_phase = arm_phase_for_support_side(self.support_side)
end

function Controller:_update_footstep_state(dt)
	self.feet.left.current_world = copy_vec3(self.feet.left.planted_world)
	self.feet.right.current_world = copy_vec3(self.feet.right.planted_world)

	if not self.step_active then
		self.step_pause_timer = math.max(0.0, self.step_pause_timer - dt)
		self.walk_phase = arm_phase_for_support_side(self.support_side)
		return
	end

	local step_speed = math.max(self.step_motion_weight, self.params.step_settle_weight)
	local swing = self.feet[self.swing_side]
	self.step_progress = clamp(self.step_progress + dt / self.params.step_duration * step_speed, 0.0, 1.0)

	local swing_alpha = compute_swing_alpha(self.step_progress)
	local foot_pos = lerp_vec3(swing.swing_from, swing.swing_to, swing_alpha)
	foot_pos.y = self.foot_ground_y + math.sin(swing_alpha * math.pi) * self:_scaled_distance(self.params.foot_lift_height)
	swing.current_world = foot_pos
	self.walk_phase = arm_phase_for_support_side(self.support_side) + self.step_progress * math.pi

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
	self.current_forward = self:_get_forward_from_root_rotation(rotation.y)
	self.current_right = self:_get_right_from_root_rotation(rotation.y)
	self.desired_direction = self.current_forward
	self.step_motion_weight = self.motion_weight

	if self.rotate_target_yaw ~= nil then
		return self:_update_rotate_motion(dt)
	end

	if self.target_world == nil then
		self.locomotion_speed = move_toward(self.locomotion_speed, 0.0, self.params.speed_deceleration * dt)
		self.motion_weight = clamp(self.locomotion_speed / self.params.walk_speed, 0.0, 1.0)
		self.step_motion_weight = self.motion_weight
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

	local desired_direction = safe_normalize(to_target, self:_get_forward_from_root_rotation(rotation.y))
	local desired_yaw = atan2(-desired_direction.x, -desired_direction.z)
	local yaw_error = self:_get_root_yaw_error(rotation.y, desired_yaw)
	local yaw_step = clamp(yaw_error, -self.params.turn_speed * dt, self.params.turn_speed * dt)

	rotation.y = rotation.y + yaw_step
	instance_transform:SetRot(rotation)

	self.yaw_error = yaw_error
	self.current_forward = self:_get_forward_from_root_rotation(rotation.y)
	self.current_right = self:_get_right_from_root_rotation(rotation.y)
	self.desired_direction = desired_direction

	local facing = clamp(hg.Dot(self.current_forward, desired_direction), 0.0, 1.0)
	self.desired_speed = self.params.walk_speed * facing
	self.locomotion_speed = move_toward(
		self.locomotion_speed,
		self.desired_speed,
		(self.desired_speed > self.locomotion_speed and self.params.speed_acceleration or self.params.speed_deceleration) * dt
	)
	self.motion_weight = clamp(self.locomotion_speed / self.params.walk_speed, 0.0, 1.0)
	self.step_motion_weight = self.motion_weight

	if math.abs(yaw_error) > self.params.turn_in_place_angle and not self.step_active then
		self.locomotion_speed = move_toward(self.locomotion_speed, 0.0, self.params.speed_deceleration * dt)
		self.motion_weight = clamp(self.locomotion_speed / self.params.walk_speed, 0.0, 1.0)
		self.step_motion_weight = self.motion_weight
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

	if not self.step_active and self.step_pause_timer > 0.0 and math.abs(yaw_error) <= self.params.turn_in_place_angle then
		self.state = "StepPause"
	end

	if self.distance_to_target <= arrive_distance and not self.step_active then
		self.state = "Arrived"
		self.arrived = true
		self.target_world = nil
		self.target_node_name = nil
	end

	return move_step
end

function Controller:_update_rotate_motion(dt)
	local instance_transform = self.instance_node:GetTransform()
	local rotation = instance_transform:GetRot()
	local desired_yaw = self.rotate_target_yaw

	self.distance_to_target = 0.0
	self.desired_speed = 0.0
	self.current_speed = 0.0
	self.gait_drive = 0.0
	self.locomotion_speed = 0.0
	self.motion_weight = 0.0
	self.step_motion_weight = 0.0
	self.desired_direction = forward_from_yaw(desired_yaw)
	self.yaw_error = self:_get_root_yaw_error(rotation.y, desired_yaw)

	if math.abs(self.yaw_error) <= self.params.rotate_arrive_angle then
		self.state = "RotateArrived"
		self:_clear_rotate_target()
		self.rotate_arrived = true
		return 0.0
	end

	local yaw_step = clamp(self.yaw_error, -self.params.turn_speed * dt, self.params.turn_speed * dt)
	rotation.y = rotation.y + yaw_step
	instance_transform:SetRot(rotation)
	rotation = instance_transform:GetRot()
	self.current_forward = self:_get_forward_from_root_rotation(rotation.y)
	self.current_right = self:_get_right_from_root_rotation(rotation.y)
	self.yaw_error = self:_get_root_yaw_error(rotation.y, desired_yaw)
	self.motion_weight = 0.0
	self.gait_drive = 0.0
	self.state = "RotateInPlace"

	if math.abs(self.yaw_error) <= self.params.rotate_arrive_angle then
		self.state = "RotateArrived"
		self:_clear_rotate_target()
		self.rotate_arrived = true
	end

	return 0.0
end

function Controller:_apply_hips_pose()
	local hips_transform = self.view_nodes["mixamorig_Hips"]:GetTransform()
	local hips_rest = self.rest_pose["mixamorig_Hips"]
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
	local knee_world = solve_two_bone_joint(hip_world, foot_target, pole_hint, upper_len, lower_len)
	local plane_normal = hg.Cross(knee_world - hip_world, foot_target - knee_world)

	if hg.Len(plane_normal) <= 0.00001 then
		plane_normal = self.current_right * side.sign
	end

	plane_normal = safe_normalize(plane_normal, self.current_right * side.sign)

	local leg_axis_offsets = LEG_IK_YAW_OFFSETS[side_name]
	local upper_basis = rotate_basis_y(make_basis_from_y(knee_world - hip_world, plane_normal), leg_axis_offsets.upper)
	local lower_basis = rotate_basis_y(make_basis_from_y(foot_target - knee_world, plane_normal), leg_axis_offsets.lower)
	local foot_pitch = 0.0

	if self.step_active and self.swing_side == side_name then
		foot_pitch = self.params.swing_foot_pitch * math.sin(compute_swing_alpha(self.step_progress) * math.pi)
	end

	upper_node:GetTransform():SetWorld(hg.TransformationMat4(hip_world, upper_basis, self:_get_world_node_scale(upper_rest.scale)))
	lower_node:GetTransform():SetWorld(hg.TransformationMat4(knee_world, lower_basis, self:_get_world_node_scale(lower_rest.scale)))
	foot_node:GetTransform():SetPosRot(foot_rest.pos, foot_rest.rot + hg.Vec3(foot_pitch, 0.0, 0.0))
end

function Controller:_apply_walk_pose()
	self:_apply_hips_pose()
	self:_apply_leg_pose("left")
	self:_apply_leg_pose("right")
end

function Controller:_apply_spine_bend()
	local bend = self.bend_state.current
	if math.abs(bend) <= 0.00001 then
		return
	end

	local spine_weights = {
		{name = "mixamorig_Spine", weight = 0.22},
		{name = "mixamorig_Spine1", weight = 0.33},
		{name = "mixamorig_Spine2", weight = 0.45}
	}

	for _, entry in ipairs(spine_weights) do
		local node = self.view_nodes[entry.name]
		local rest_pose = self.rest_pose[entry.name]
		node:GetTransform():SetPosRot(rest_pose.pos, rest_pose.rot + hg.Vec3(bend * entry.weight, 0.0, 0.0))
	end
end

function Controller:_compute_free_arm_pose(side_name)
	local neutral = FREE_ARM_NEUTRAL_OFFSETS[side_name]
	local swing_offsets = FREE_ARM_WALK_SWING_OFFSETS[side_name]
	local locomotion_weight = self.motion_weight
	local phase = self.walk_phase
	local swing = math.sin(phase) * locomotion_weight
	local side = HAND_SIDES[side_name]
	local shoulder_rest = self.rest_pose[side.shoulder]
	local arm_rest = self.rest_pose[side.arm]
	local forearm_rest = self.rest_pose[side.forearm]
	local hand_rest = self.rest_pose[side.hand]
	local swing_scale = swing * self.params.free_arm_swing_scale * self.free_arm_amplitude[side_name]

	return {
		shoulder = shoulder_rest.rot + neutral.shoulder + scale_vec3(swing_offsets.shoulder, swing_scale),
		arm = arm_rest.rot + neutral.arm + scale_vec3(swing_offsets.arm, swing_scale),
		forearm = forearm_rest.rot + neutral.forearm + scale_vec3(swing_offsets.forearm, swing_scale),
		hand = hand_rest.rot + neutral.hand + scale_vec3(swing_offsets.hand, swing_scale)
	}
end

function Controller:_compute_arm_pose_to_world_target(side_name, target_hand_pos, target_hand_rot)
	local side = HAND_SIDES[side_name]
	local arm_node = self.view_nodes[side.arm]
	local arm_rest = self.rest_pose[side.arm]
	local forearm_rest = self.rest_pose[side.forearm]
	local hand_rest = self.rest_pose[side.hand]
	local arm_root_world = get_world_position(arm_node)
	local hand_target = copy_vec3(target_hand_pos)
	local arm = self.arm_lengths[side_name]
	local upper_len = arm.upper * self.uniform_scale
	local lower_len = arm.lower * self.uniform_scale
	local pole_hint = self.current_right * (side.sign * self.params.arm_elbow_outward_bias) + self.current_forward * self.params.arm_elbow_forward_bias
	local elbow_world = solve_two_bone_joint(arm_root_world, hand_target, pole_hint, upper_len, lower_len)
	local plane_normal = hg.Cross(elbow_world - arm_root_world, hand_target - elbow_world)

	if hg.Len(plane_normal) <= 0.00001 then
		plane_normal = pole_hint
	end

	plane_normal = safe_normalize(plane_normal * side.sign, self.current_right * side.sign)

	local arm_axis_offsets = ARM_IK_YAW_OFFSETS[side_name]
	local upper_basis = rotate_basis_y(make_basis_from_y(elbow_world - arm_root_world, plane_normal), arm_axis_offsets.upper)
	local lower_basis = rotate_basis_y(make_basis_from_y(hand_target - elbow_world, plane_normal), arm_axis_offsets.lower)

	return {
		arm_world = hg.TransformationMat4(arm_root_world, upper_basis, self:_get_world_node_scale(arm_rest.scale)),
		forearm_world = hg.TransformationMat4(elbow_world, lower_basis, self:_get_world_node_scale(forearm_rest.scale)),
		hand_world = hg.TransformationMat4(hand_target, target_hand_rot, self:_get_world_node_scale(hand_rest.scale))
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

	local free_hand_world = hand_node:GetTransform():GetWorld()
	local blend = lock_state.blend
	local target_world = lock_state.target_node:GetTransform():GetWorld()
	local blended_hand_pos = lerp_vec3(hg.GetT(free_hand_world), hg.GetT(target_world), blend)
	local blended_hand_rot = lerp_vec3(hg.GetRotation(free_hand_world), hg.GetRotation(target_world), blend)
	local locked_pose = self:_compute_arm_pose_to_world_target(side_name, blended_hand_pos, blended_hand_rot)

	arm_node:GetTransform():SetWorld(locked_pose.arm_world)
	forearm_node:GetTransform():SetWorld(locked_pose.forearm_world)
	hand_node:GetTransform():SetWorld(locked_pose.hand_world)
end

function Controller:Update(dt)
	self:_refresh_instance_scale()
	self:_update_action_runner()
	self:_restore_controlled_pose()
	self:_update_root_motion(dt)
	self:_update_hand_lock_blends(dt)
	self:_update_look_at_blend(dt)
	self:_update_bend_state(dt)
	self:_apply_walk_pose()
	self:_apply_spine_bend()
	self:_apply_arm_pose("left")
	self:_apply_arm_pose("right")
	self:_apply_look_at_pose()
	self:_apply_grabbed_objects()
	self:_update_camera_state(dt)
	self:_update_action_runner()
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
		rotation_target_active = self.rotate_target_yaw ~= nil,
		current_speed = self.current_speed,
		gait_drive = self.gait_drive,
		bend_deg = math.deg(self.bend_state.current),
		left_arm_amplitude = self.free_arm_amplitude.left,
		right_arm_amplitude = self.free_arm_amplitude.right,
		support_side = self.support_side,
		step_progress = self.step_progress,
		step_pause_timer = self.step_pause_timer,
		locomotion_speed = self.locomotion_speed,
		left_hand = self.hand_locks.left.target_name or "free",
		right_hand = self.hand_locks.right.target_name or "free",
		held_left = self.held_objects.left.node_ref or "-",
		held_right = self.held_objects.right.node_ref or "-",
		look_target = self.look_at_state.target_name or "-",
		look_blend = self.look_at_state.blend,
		camera = self.camera_state.node_name or "-",
		camera_mode = self.camera_state.mode,
		camera_target = self.camera_state.target_name or "-",
		current_action_type = self.action_runner.current_action_type or "-",
		action_index = self.action_runner.current_action_index
	}
end

function Controller:GetDebugDrawState()
	local root_position = copy_vec3(self.instance_node:GetTransform():GetPos())
	local hips_node = self.view_nodes["mixamorig_Hips"]
	local head_node = self.view_nodes["mixamorig_Head"]
	local left_shoulder_pos = get_world_position(self.view_nodes["mixamorig_LeftShoulder"])
	local right_shoulder_pos = get_world_position(self.view_nodes["mixamorig_RightShoulder"])
	local left_up_leg_pos = get_world_position(self.view_nodes["mixamorig_LeftUpLeg"])
	local right_up_leg_pos = get_world_position(self.view_nodes["mixamorig_RightUpLeg"])
	local target_position = nil
	local hips_position = get_world_position(hips_node)
	local head_position = get_world_position(head_node)
	local shoulder_center = (left_shoulder_pos + right_shoulder_pos) * 0.5
	local pelvis_forward = compute_facing_from_landmarks(left_up_leg_pos, right_up_leg_pos, shoulder_center - hips_position, self.current_forward)
	local chest_forward = compute_facing_from_landmarks(left_shoulder_pos, right_shoulder_pos, head_position - shoulder_center, self.current_forward)

	if self.target_node_name ~= nil then
		local ok, resolved = pcall(function()
			return self:_resolve_node_ref(self.target_node_name)
		end)

		if ok and resolved ~= nil and resolved:IsValid() then
			target_position = get_world_position(resolved)
		end
	elseif self.target_world ~= nil then
		target_position = copy_vec3(self.target_world)
	end

	return {
		root_pos = root_position,
		hips_pos = hips_position,
		head_pos = head_position,
		target_pos = target_position,
		current_forward = copy_vec3(self.current_forward),
		desired_direction = copy_vec3(self.desired_direction),
		root_world_forward = get_world_forward_xz(self.instance_node, self.current_forward),
		hips_forward = pelvis_forward,
		head_forward = chest_forward,
		left_foot_pos = copy_vec3(self.feet.left.current_world),
		right_foot_pos = copy_vec3(self.feet.right.current_world),
		support_side = self.support_side,
		state = self.state
	}
end

local function create_controller(scene, instance_node_name)
	local instance_node = ensure_valid_node(scene:GetNode(instance_node_name), instance_node_name)
	local controller = {
		scene = scene,
		instance_node_name = instance_node_name,
		instance_node = instance_node,
		scene_view = instance_node:GetInstanceSceneView(),
		view_nodes = {},
		rest_pose = {},
		node_refs = {},
		target_world = nil,
		target_node_name = nil,
		arrived = false,
		rotate_target_yaw = nil,
		rotate_arrived = false,
		state = "Idle",
		current_speed = 0.0,
		desired_speed = 0.0,
		locomotion_speed = 0.0,
		gait_drive = 0.0,
		motion_weight = 0.0,
		step_motion_weight = 0.0,
		distance_to_target = 0.0,
		yaw_error = 0.0,
		walk_phase = 0.0,
		support_side = "left",
		swing_side = "right",
		step_active = false,
		step_progress = 0.0,
		step_pause_timer = 0.0,
		next_step_pause_duration = 0.0,
		model_facing_yaw_offset = MODEL_FACING_YAW_OFFSET,
		instance_scale = copy_vec3(instance_node:GetTransform():GetScale()),
		uniform_scale = math.max(average_abs_scale(instance_node:GetTransform():GetScale()), 0.0001),
		foot_ground_y = instance_node:GetTransform():GetPos().y,
		current_forward = forward_from_yaw(instance_node:GetTransform():GetRot().y + MODEL_FACING_YAW_OFFSET),
		current_right = right_from_yaw(instance_node:GetTransform():GetRot().y + MODEL_FACING_YAW_OFFSET),
		desired_direction = forward_from_yaw(instance_node:GetTransform():GetRot().y + MODEL_FACING_YAW_OFFSET),
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
			step_pause_duration = 0.15,
			step_settle_weight = 0.2,
			step_start_weight = 0.08,
			speed_acceleration = 1.8,
			speed_deceleration = 2.9,
			knee_forward_bias = 1.1,
			knee_outward_bias = 0.35,
			hips_bob = 0.012,
			hips_sway = 0.016,
			swing_foot_pitch = hg.Deg(8.0),
			free_arm_swing_scale = 1.0,
			hand_lock_blend_duration = 1.0,
			look_at_blend_duration = 1.0,
			-- rotate_step_angle = hg.Deg(10.0),
			rotate_arrive_angle = hg.Deg(1.0),
			rotate_step_pause_duration = 0.12,
			rotate_motion_weight = 0.22,
			rotate_step_progress_weight = 1.0,
			look_at_yaw_limit = hg.Deg(40.0),
			look_at_pitch_up_limit = hg.Deg(20.0),
			look_at_pitch_down_limit = hg.Deg(-10.0),
			bend_duration = 2.0,
			camera_tracking_latency = 0.28,
			camera_fov_blend_duration = 1.0,
			camera_steady_distance = 4.0,
			camera_steady_angle = hg.Deg(180.0),
			camera_steady_position_latency = 0.45,
			camera_steady_rotation_latency = 0.32,
			camera_velocity_latency = 0.18,
			camera_velocity_min_distance = 0.03,
			arm_elbow_forward_bias = 0.35,
			arm_elbow_outward_bias = 0.85
		},
		hand_locks = {
			left = {active = false, blend = 0.0, target_name = nil, target_node = nil},
			right = {active = false, blend = 0.0, target_name = nil, target_node = nil}
		},
		free_arm_amplitude = {
			left = 1.0,
			right = 1.0
		},
		held_objects = {
			left = {node = nil, node_ref = nil, original_parent = nil, attached_parent = nil, using_proxy = false},
			right = {node = nil, node_ref = nil, original_parent = nil, attached_parent = nil, using_proxy = false}
		},
		hand_attach_proxies = {
			left = nil,
			right = nil
		},
		look_at_state = {
			active = false,
			blend = 0.0,
			target_name = nil,
			target_node = nil,
			yaw = 0.0,
			pitch = 0.0
		},
		bend_state = {
			current = 0.0,
			start = 0.0,
			target = 0.0,
			elapsed = 0.0,
			duration = 2.0,
			active = false
		},
		camera_state = {
			node_name = nil,
			node = nil,
			mode = "static",
			target_name = nil,
			target_node = nil,
			tracking_latency = 0.0,
			steady_distance = 0.0,
			steady_angle = 0.0,
			steady_position_latency = 0.0,
			steady_rotation_latency = 0.0,
			steady_height_offset = 0.0,
			target_offset = hg.Vec3(0.0, 0.0, 0.0),
			previous_target_pos = nil,
			velocity_dir = nil,
			fov_active = false,
			fov_elapsed = 0.0,
			fov_duration = 1.0,
			fov_start = 0.0,
			fov_target = 0.0
		},
		action_runner = {
			running = false,
			actions = nil,
			next_index = 1,
			current_action = nil,
			current_action_type = nil,
			current_action_index = 0
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
		},
		turn_step = {
			active = false,
			delta_yaw = 0.0,
			applied_yaw = 0.0,
			pivot_world = hg.Vec3()
		}
	}

	setmetatable(controller, Controller)

	for _, name in ipairs(CONTROLLED_NODE_NAMES) do
		controller.view_nodes[name] = controller:_get_view_node(name)
		controller.rest_pose[name] = capture_local_pose(controller.view_nodes[name])
	end

	controller.arm_lengths.left.upper = resolve_chain_length(controller.rest_pose["mixamorig_LeftForeArm"])
	controller.arm_lengths.left.lower = resolve_chain_length(controller.rest_pose["mixamorig_LeftHand"])
	controller.arm_lengths.right.upper = resolve_chain_length(controller.rest_pose["mixamorig_RightForeArm"])
	controller.arm_lengths.right.lower = resolve_chain_length(controller.rest_pose["mixamorig_RightHand"])
	controller.leg_lengths.left.upper = resolve_chain_length(controller.rest_pose["mixamorig_LeftLeg"])
	controller.leg_lengths.left.lower = resolve_chain_length(controller.rest_pose["mixamorig_LeftFoot"])
	controller.leg_lengths.right.upper = resolve_chain_length(controller.rest_pose["mixamorig_RightLeg"])
	controller.leg_lengths.right.lower = resolve_chain_length(controller.rest_pose["mixamorig_RightFoot"])
	controller:_reset_gait_state()

	return controller
end

return {
	CreateAutomatonController = create_controller
}
