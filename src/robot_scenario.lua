local actions = {
	-- {type = "rotate", target = "path_1"},
-- 	{type = "camera", camera = "Camera2"}
-- {type = "camera", camera = "Camera2", FOV = 45}
-- {type = "camera", camera = "Camera2", tracking = "automaton-rig-tpose"}
-- {type = "camera", camera = "Camera2", tracking = "automaton-rig-tpose", offset = {0.0, 1.4, 0.0}}

-- {type = "sound", id = "phone_ring_audio", asset = "audio/ring.ogg", loop = true}
-- {type = "sound", id = "phone_ring_audio", stop = true}

-- {type = "instance_animation", id = "phone_ring_anim", node = "telephone_speaker", animation = "ring", loop = true}
-- {type = "instance_animation", id = "phone_ring_anim", animation = "still"}


	{type = "camera", camera = "Camera", steady_cam = {target = "automaton-rig-tpose", distance = 7.0, angle = 0, offset = {0.0, 1.4, 0.0}}},
	-- {type = "lock_arm", side = "right", target = "automaton-rig-tpose:hand_target_can"},
	{type = "move", start = "path_0", target = "path_1"},
	{type = "look_at", target = "path_2", stiffness = 180},
	{type = "rotate", target = "path_2"},
	{type = "clear_look_at", stiffness = 180},
    {type = "move", start = "path_1", target = "path_2"},
	{type = "look_at", target = "watering_can", stiffness = 180},
	{type = "lock_arm", side = "right", target = "automaton-rig-tpose:hand_target_can"},
	{type = "bend", value = -90},
	{type = "kneel", offset_y = -0.45, duration = 0.5},
	{type = "grab", side = "right", target = "watering_can"},
	{type = "bend", value = 0},
	{type = "kneel", offset_y = 0.45, duration = 0.5},
	{type = "unlock_arm", side = "right"},
	{type = "clear_look_at", stiffness = 180},
	{type = "arm_amplitude", side = "right", value = 0.15},
    {type = "rotate", target = "path_3"},
    {type = "move", start = "path_2", target = "path_3"},
	{type = "instance_animation", id = "phone_ring_anim", node = "telephone_speaker", animation = "ring", loop = true},
	{type = "sound", id = "phone_ring_audio", asset = "audio/ring.ogg", loop = true},
	{type = "camera", camera = "Camera", steady_cam = {target = "automaton-rig-tpose", distance = 3.5, angle = -120, offset = {0.0, 1.5, 0.0}}},
    {type = "rotate", target = "path_4"},
    {type = "move", start = "path_3", target = "path_4"},
	{type = "sound", id = "phone_ring_audio", stop = true},
	{type = "instance_animation", id = "phone_ring_anim", animation = "still"}
	-- {type = "grab", side = "right", target = "watering_can"},
	-- {type = "move", target = "plants_A"},
	-- {type = "lock_arm", side = "right", target = "automaton-rig-tpose:watering_anchor"},
	-- {type = "look_at", target = "plants_A"},
	-- {type = "clear_look_at"},
	-- {type = "unlock_arm", side = "right"},
	-- {type = "release", side = "right"},
	-- {type = "move", target = "telephone_area"},
	-- {type = "rotate", target = "telephone_receiver"},
	-- {type = "grab", side = "right", target = "telephone_receiver"},
	-- {type = "lock_arm", side = "right", target = "automaton-rig-tpose:phone_ear_anchor"},
	-- {type = "look_at", target = "caller_focus_A"}
}

return actions