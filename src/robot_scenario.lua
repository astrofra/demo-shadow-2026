local actions = {
	-- {type = "rotate", target = "path_1"},
-- 	{type = "camera", camera = "Camera2"}
-- {type = "camera", camera = "Camera2", FOV = 45}
-- {type = "camera", camera = "Camera2", tracking = "automaton-rig-tpose"}
-- {type = "camera", camera = "Camera2", tracking = "automaton-rig-tpose", offset = {0.0, 1.4, 0.0}}

	-- {type = "camera", camera = "Camera", steady_ca:m = {target = "automaton-rig-tpose", distance = 5.0, angle = 180, offset = {0.0, 1.4, 0.0}}},
	{type = "move", start = "path_0", target = "path_1"},
	{type = "rotate", target = "path_2"},
    {type = "move", start = "path_1", target = "path_2"},
    {type = "rotate", target = "path_3"},
    {type = "move", start = "path_2", target = "path_3"},
    {type = "rotate", target = "path_4"},
    {type = "move", start = "path_3", target = "path_4"},
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