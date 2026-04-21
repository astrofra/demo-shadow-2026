hg = require("harfang")
-- profiler = require("profiler")
require("scrolltext")
require("particles")
require("boids")
-- require("bubbles")
require("animations")
require("walkman")
require("music_analysis_runtime")
require("neural_controller")
require("config_gui")
require("utils")
local astronaut_wander = require("astronaut_wander")
local songs = require("songs")
local winamp_ui = require("winamp_ui")
require("aurora")

-- credits
-- concept & graphics : fra
-- music : Erk, Nainain, GliGli, Aceman, mAZE, Riddlemak, WillBe
-- code : fra, erk
-- 3D engine : xbarr, mooz, scorpheus, kipixelle

function draw_line(pos_a, pos_b, line_color, vid, vtx_line_layout, line_shader)
	local vtx = hg.Vertices(vtx_line_layout, 2)
	vtx:Begin(0):SetPos(pos_a):SetColor0(line_color):End()
	vtx:Begin(1):SetPos(pos_b):SetColor0(line_color):End()
	hg.DrawLines(vid, vtx, line_shader)
end

function compute_dof_focus_length(max_focus_length, min_focus_length, blend, curve_power)
	local shaped_blend = clamp(blend, 0.0, 1.0) ^ curve_power
	local log_focus_length = hg.Lerp(math.log(max_focus_length), math.log(min_focus_length), shaped_blend)
	return math.exp(log_focus_length)
end

local function open_demo_window(res_x, res_y, default_fullscreen)
	local win = hg.NewWindow("Martian Melodies^Orion^Resistance(2026)", res_x, res_y, 32, default_fullscreen)
	hg.RenderInit(win)
	hg.RenderReset(res_x, res_y, hg.RF_VSync | hg.RF_MSAA4X | hg.RF_MaxAnisotropy)
	return win
end

local function run_demo_3d(win, res_x, res_y, config)
	local i
	local music_analysis = require("music_analysis")
	local FOCUS_LEN_MAX = 10000.0
	local FOCUS_LEN_WALKMAN = 10.0
	local FOCUS_TRANSITION_TIME = 1.5
	local FOCUS_CURVE_POWER = 0.5
	local FOCUS_RELEASE_DELAY = 0.12
	local ENABLE_GROUND_FOG = false
	local res_vec2 = hg.Vec2(res_x, res_y)
	local font_size = math.floor((70 * res_x) / 1280)

	local pipeline = hg.CreateForwardPipeline()
	local res = hg.PipelineResources()

	local scene_intro = hg.Scene()
	hg.LoadSceneFromAssets("props/logo_rse/logo_rse.scn", scene_intro, res, hg.GetForwardPipelineInfo())

	local cam_intro = scene_intro:GetNode("Camera")
	scene_intro:SetCurrentCamera(cam_intro)

	local scene = hg.Scene()
	hg.LoadSceneFromAssets("main_scenery.scn", scene, res, hg.GetForwardPipelineInfo())
	local intro_anims = {"begin", "fadein", "fadeout", "title_fadein", "title_fadeout", "end"}
	local intro_current_anim = 0
	local intro_playing_anim = 0
	local intro_anim_has_started = false

	local physics = hg.SceneBullet3Physics()
	physics:SceneCreatePhysicsFromAssets(scene)

	local scene_clocks = hg.SceneClocks()
	local bubble_scene = hg.Scene()

	local color = hg.CreateTexture(res_x, res_y, "color texture", hg.TF_RenderTarget, hg.TF_RGBA8)
	local depth = hg.CreateTexture(res_x, res_y, "depth texture", hg.TF_RenderTarget, hg.TF_D32F)
	local frame_buffer = hg.CreateFrameBuffer(color, depth, "framebuffer")

	local bubble_color = hg.CreateTexture(res_x, res_y, "color texture", hg.TF_RenderTarget, hg.TF_RGBA8)
	local bubble_depth = hg.CreateTexture(res_x, res_y, "depth texture", hg.TF_RenderTarget, hg.TF_D32F)
	local bubble_frame_buffer = hg.CreateFrameBuffer(bubble_color, bubble_depth, "bubble_framebuffer")

	local vtx_layout = hg.VertexLayoutPosFloatNormUInt8TexCoord0UInt8()
	local screen_mdl = hg.CreatePlaneModel(vtx_layout, 1, res_y / res_x, 1, 1)
	local screen_ref = res:AddModel("screen", screen_mdl)

	vtx_layout = hg.VertexLayoutPosFloatNormUInt8TexCoord0UInt8()

	local particle_intro_mdl = build_random_particles_model(hg.ModelBuilder(), vtx_layout, 3, 25.0)
	local particle_dirt_mdl = build_random_particles_model(hg.ModelBuilder(), vtx_layout, 5, 15.0)
	local particle_ground_fog_mdl
	if ENABLE_GROUND_FOG then
		particle_ground_fog_mdl = build_random_particles_model(hg.ModelBuilder(), vtx_layout, 8, 6.0)
	end

	local particle_dirt_ref = res:AddModel("dirt_particle", particle_dirt_mdl)
	local particle_dirt_render_state = hg.ComputeRenderState(hg.BM_Alpha, hg.DT_Less, hg.FC_Disabled, false)
	local boid_render_state = hg.ComputeRenderState(hg.BM_Opaque, hg.DT_Less, hg.FC_Disabled, false)
	local particle_ground_fog_render_state
	if ENABLE_GROUND_FOG then
		particle_ground_fog_render_state = particle_dirt_render_state
	end

	local vtx_line_layout = hg.VertexLayoutPosFloatColorUInt8()
	local shader_for_line = hg.LoadProgramFromAssets("shaders/pos_rgb")
	local shader_for_particle = hg.LoadProgramFromAssets("shaders/dirt_particle")
	local shader_for_boid = hg.LoadProgramFromAssets("shaders/white")
	local shader_for_aurora = hg.LoadProgramFromAssets("shaders/aurora")
	local aurora_model = aurora_build_mesh(vtx_layout)
	local aurora_render_state = hg.ComputeRenderState(hg.BM_Alpha, hg.DT_Less, hg.FC_Disabled, false)
	local aurora_uniforms = {
		hg.MakeUniformSetValue("u_time", hg.Vec4(0, 0, 0, 0)),
		hg.MakeUniformSetValue("u_aurora_params", hg.Vec4(0.55, 0, 0, 0)),
	}
	local aurora_time = 0.0
	local shader_for_ground_fog
	if ENABLE_GROUND_FOG then
		shader_for_ground_fog = hg.LoadProgramFromAssets("shaders/ground_fog")
	end
	local dirt_particle_texture, _ = hg.LoadTextureFromAssets("maps/dirt_particle.png",
		hg.TF_UBorder | hg.TF_VBorder | hg.TF_SamplerMinAnisotropic | hg.TF_SamplerMagAnisotropic)
	local dirt_particle_tex_uniforms = {hg.MakeUniformSetTexture("s_tex", dirt_particle_texture, 0)}
	local particle_uniforms = {}
	local ground_fog_uniforms
	if ENABLE_GROUND_FOG then
		ground_fog_uniforms = {}
	end

	local font = hg.LoadFontFromAssets("fonts/WDXLLubrifontTC-Regular.ttf", font_size)
	local font_program = hg.LoadProgramFromAssets("core/shader/font")
	local text_uniform_values = {hg.MakeUniformSetValue("u_color", hg.Vec4(1, 1, 0, 1))}
	local text_render_state = hg.ComputeRenderState(hg.BM_Alpha, hg.DT_Always, hg.FC_Disabled)
	local imgui_prg = hg.LoadProgramFromAssets("core/shader/imgui")
	local imgui_img_prg = hg.LoadProgramFromAssets("core/shader/imgui_image")
	hg.ImGuiInit(14, imgui_prg, imgui_img_prg)

	local cam = scene:GetNode("Camera")
	scene:SetCurrentCamera(cam)
	local z_near = cam:GetCamera():GetZNear()
	local z_far = cam:GetCamera():GetZFar()
	local fov = cam:GetCamera():GetFov()

	local bubble_cam = hg.CreateCamera(bubble_scene, cam:GetTransform():GetWorld(), z_near, z_far, fov)
	bubble_scene:SetCurrentCamera(bubble_cam)
	local ground_fog_node
	local ground_fog_radius = 12.0
	local ground_fog_center
	local ground_fog_ceiling = 1.8
	if ENABLE_GROUND_FOG then
		ground_fog_node = scene:GetNode("ground_fog")
		ground_fog_center = ground_fog_node:GetTransform():GetPos()
		ground_fog_ceiling = ground_fog_center.y + 1.8
	end

	local intro_particles = {}
	local max_intro_particles = 100
	for i = 1, max_intro_particles do
		local particle_alpha = i / max_intro_particles
		local particle_age = hg.time_from_sec_f((i / max_intro_particles) * math.pi * 2.0)
		table.insert(intro_particles, {
			pos = hg.Vec3(math.random(-40, 40), math.random(-20, 20), math.random(100, 200)),
			rot = hg.Vec3(0.0, 0.0, math.random() * math.pi * 2.0),
			alpha = particle_alpha,
			age = particle_age
		})
	end

	local dirt_particles = {}
	local max_dirt_particles = 150
	dirt_particles.boundaries = {min = hg.Vec3(-30, 0, -20), max = hg.Vec3(30, 20, 100)}
	for i = 1, max_dirt_particles do
		local particle_alpha = i / max_dirt_particles
		local particle_age = hg.time_from_sec_f((i / max_dirt_particles) * math.pi * 2.0)
		table.insert(dirt_particles, {
			pos = hg.Vec3(math.random(-30, 30), math.random(0, 20), math.random(-20, 100)),
			rot = hg.Vec3(0.0, 0.0, math.random() * math.pi * 2.0),
			alpha = particle_alpha,
			age = particle_age
		})
	end

	local boid_model = boids_build_quad_model(hg.ModelBuilder(), vtx_layout)
	local boids_state = boids_create(dirt_particles.boundaries, 72)
	local boid_uniforms = {}
	local music_analysis_frame = music_analysis_make_frame()
	local neural_state = neural_controller_create()
	local boid_params = {}
	local boids_debug_visible = false
	local tab_key_was_down = false

	local ground_fog_particles = {}
	if ENABLE_GROUND_FOG then
		local max_ground_fog_particles = 64
		ground_fog_particles.boundaries = {
			min = hg.Vec3(ground_fog_center.x - ground_fog_radius, ground_fog_center.y, ground_fog_center.z - ground_fog_radius),
			max = hg.Vec3(ground_fog_center.x + ground_fog_radius, ground_fog_ceiling, ground_fog_center.z + ground_fog_radius)
		}
		for i = 1, max_ground_fog_particles do
			local fog_angle = math.random() * math.pi * 2.0
			local fog_radius = math.sqrt(math.random())
			local fog_pos = hg.Vec3(
				ground_fog_center.x + math.cos(fog_angle) * fog_radius * ground_fog_radius,
				hg.Lerp(ground_fog_particles.boundaries.min.y, ground_fog_particles.boundaries.max.y, math.random()),
				ground_fog_center.z + math.sin(fog_angle) * fog_radius * ground_fog_radius
			)
			local fog_scale_xz = hg.Lerp(2.4, 4.8, math.random())
			table.insert(ground_fog_particles, {
				pos = hg.Vec3(fog_pos.x, fog_pos.y, fog_pos.z),
				home_pos = hg.Vec3(fog_pos.x, fog_pos.y, fog_pos.z),
				vel = hg.Vec3(0.0, 0.0, 0.0),
				rot = hg.Vec3(0.0, math.random() * math.pi * 2.0, 0.0),
				scale = hg.Vec3(fog_scale_xz, hg.Lerp(1.0, 1.8, math.random()), fog_scale_xz),
				alpha = hg.Lerp(0.10, 0.24, math.random()),
				age = hg.time_from_sec_f(math.random() * math.pi * 2.0),
				seed = hg.Vec3(math.random(), math.random(), math.random())
			})
		end
	end

	local frame = 0
	local mouse = hg.Mouse()
	local walkman_button_pressed_timeout = song_player_get_clock()
	local walkman_buttons_nodes = {}
	for i = 0, 3 do
		local nd = scene:GetNode("walkman_click_zone_" .. i)
		if nd:IsValid() then
			table.insert(walkman_buttons_nodes, nd)
		end
	end

	local buttons = {"walkman_button_0", "walkman_button_1", "walkman_button_2", "walkman_button_3"}

	song_player_reset_clock()
	local song_player = create_song_player(songs)
	local walkman_button_change_state = false
	local walkman_button_hover = -1
	local walkman_button_hover_hit = -1
	local walkman_button_on = WALKMAN_PLAY

	local buttons_trs = {}
	for i = 1, #buttons do
		table.insert(buttons_trs, scene:GetNode("walkman_rig"):GetInstanceSceneView():GetNode(scene, buttons[i]):GetTransform())
	end

	local walkman_osd = {clock_str = nil, led_rail_timer = nil, current_led = 0}
	local osd_instance_view = scene:GetNode("walkman_rig"):GetInstanceSceneView():GetNode(scene, "osd"):GetInstanceSceneView()
	walkman_osd["icon_mode_repeat"] = osd_instance_view:GetNode(scene, "icon_mode_repeat")
	walkman_osd["icon_mode_next"] = osd_instance_view:GetNode(scene, "icon_mode_next")
	walkman_osd["double_dot"] = osd_instance_view:GetNode(scene, "double_dot")
	walkman_osd["digit_0"] = osd_instance_view:GetNode(scene, "digit_0"):GetObject():GetMaterial(0)
	walkman_osd["digit_1"] = osd_instance_view:GetNode(scene, "digit_1"):GetObject():GetMaterial(0)
	walkman_osd["digit_2"] = osd_instance_view:GetNode(scene, "digit_2"):GetObject():GetMaterial(0)
	walkman_osd["digit_3"] = osd_instance_view:GetNode(scene, "digit_3"):GetObject():GetMaterial(0)
	walkman_osd["songs_titles"] = osd_instance_view:GetNode(scene, "songs_titles"):GetObject():GetMaterial(0)
	walkman_osd["dot_0"] = osd_instance_view:GetNode(scene, "dot_0"):GetObject():GetMaterial(0)
	walkman_osd["dot_1"] = osd_instance_view:GetNode(scene, "dot_1"):GetObject():GetMaterial(0)
	walkman_osd["dot_2"] = osd_instance_view:GetNode(scene, "dot_2"):GetObject():GetMaterial(0)
	walkman_osd["dot_3"] = osd_instance_view:GetNode(scene, "dot_3"):GetObject():GetMaterial(0)
	walkman_osd["dot_4"] = osd_instance_view:GetNode(scene, "dot_4"):GetObject():GetMaterial(0)

	local event_table = {}
	local scroll_x = 0
	local char_offset = 0
	local ns = 0
	local dt
	local dts

	if profiler then
		profiler.start()
	end

	play_song(song_player)

	local p_nodes = {}
	local all_nodes = scene:GetNodes()
	for i = 0, all_nodes:size() - 1 do
		if string.sub(all_nodes:at(i):GetName(), 1, 3) == "col" then
			table.insert(p_nodes, all_nodes:at(i))
		end
	end

	local intro_pipeline_aaa_config
	local intro_pipeline_aaa
	if config.enable_aaa then
		intro_pipeline_aaa_config = hg.ForwardPipelineAAAConfig()
		intro_pipeline_aaa = hg.CreateForwardPipelineAAAFromAssets("core", intro_pipeline_aaa_config, hg.BR_Half, hg.BR_Half)
		if config.low_aaa then
			intro_pipeline_aaa_config.temporal_aa_weight = 0.2
			intro_pipeline_aaa_config.sample_count = 1
		else
			intro_pipeline_aaa_config.temporal_aa_weight = 0.0100
			intro_pipeline_aaa_config.sample_count = 2
		end
		intro_pipeline_aaa_config.z_thickness = 0.2600
		intro_pipeline_aaa_config.bloom_bias = 0.5
		intro_pipeline_aaa_config.bloom_intensity = 0.1
		intro_pipeline_aaa_config.bloom_threshold = 5.0
	end

	local astronaut_wander_state = astronaut_wander.create(scene)
	local intro_particle_fade
	local intro_clock = hg.time_from_sec_f(0.0)
	local ground_fog_time = 0.0
	local astronaut_prev_pos = astronaut_wander_state.transform:GetPos()
	local astronaut_velocity = hg.Vec3(0.0, 0.0, 0.0)
	local function maybe_collect_garbage()
		collectgarbage("collect")
	end

	hg.HideCursor()

	if config.skip_intro == false then
		while not hg.ReadKeyboard():Key(hg.K_Escape) and hg.IsWindowOpen(win) and intro_current_anim < #intro_anims do
			intro_anim_has_started, intro_playing_anim, intro_current_anim = anim_player(scene_intro, intro_anims, intro_anim_has_started, intro_playing_anim, intro_current_anim)

			dt = math.min(hg.time_from_sec_f(5.0 / 60.0), hg.TickClock())
			intro_clock = intro_clock + dt
			song_player_advance_clock(dt)
			song_player = song_player_update_transport(song_player)
			scene_intro:Update(dt)

			local view_id = 0
			local pass_ids
			if config.enable_aaa then
				view_id, pass_ids = hg.SubmitSceneToPipeline(view_id, scene_intro, hg.IntRect(0, 0, res_x, res_y), true, pipeline, res, intro_pipeline_aaa, intro_pipeline_aaa_config, frame)
			else
				view_id, pass_ids = hg.SubmitSceneToPipeline(view_id, scene_intro, hg.IntRect(0, 0, res_x, res_y), true, pipeline, res)
			end

			local transparent_view_id = hg.GetSceneForwardPipelinePassViewId(pass_ids, hg.SFPP_Transparent)
			intro_particle_fade = clamp(map(hg.time_to_sec_f(intro_clock), 1.0, 10.0, 0.0, 1.0), 0.0, 1.0)
			intro_particle_fade = intro_particle_fade * clamp(map(hg.time_to_sec_f(intro_clock), 31.0, 34.0, 1.0, 0.0), 0.0, 1.0)

			intro_particles = particles_update_draw_model(transparent_view_id, dt, intro_particles,
				particle_intro_mdl, shader_for_particle, particle_uniforms, dirt_particle_tex_uniforms, particle_dirt_render_state, 2.0, intro_particle_fade)

			frame = hg.Frame()
			hg.UpdateWindow(win)
			maybe_collect_garbage()
		end
	end

	local pipeline_aaa_config
	local pipeline_aaa
	local dof_focus_blend = 0.0
	local dof_focus_blend_speed = 1.0 / FOCUS_TRANSITION_TIME
	local dof_release_delay_timer = 0.0
	local current_dof_focus_length = FOCUS_LEN_MAX
	if config.enable_aaa then
		pipeline_aaa_config = hg.ForwardPipelineAAAConfig()
		pipeline_aaa = hg.CreateForwardPipelineAAAFromAssets("core", pipeline_aaa_config, hg.BR_Half, hg.BR_Half)
		if config.low_aaa then
			pipeline_aaa_config.temporal_aa_weight = 0.2
			pipeline_aaa_config.sample_count = 1
		else
			pipeline_aaa_config.temporal_aa_weight = 0.05
			pipeline_aaa_config.sample_count = 2
		end
		pipeline_aaa_config.z_thickness = 4.0
		pipeline_aaa_config.bloom_bias = 0.6100
		pipeline_aaa_config.bloom_intensity = 1.7400
		pipeline_aaa_config.bloom_threshold = 1.5500
		pipeline_aaa_config.exposure = 1.5900
		pipeline_aaa_config.gamma = 2.0900
		pipeline_aaa_config.dof_focus_length = current_dof_focus_length
		pipeline_aaa_config.dof_focus_point = 12.0
	end

	local fade = 0.0
	local fade_pow = 1.0
	local show_cursor_count = 0
	hg.ShowCursor()

	while not hg.ReadKeyboard():Key(hg.K_Escape) and hg.IsWindowOpen(win) do
		local keyboard_state = hg.ReadKeyboard()
		local tab_key_down = keyboard_state:Key(hg.K_Tab)
		if tab_key_down and not tab_key_was_down then
			boids_debug_visible = not boids_debug_visible
		end
		tab_key_was_down = tab_key_down

		show_cursor_count = show_cursor_count + 1
		if show_cursor_count > 30 then
			show_cursor_count = 0
			hg.ShowCursor()
		end

		if keyboard_state:Key(hg.K_G) then
			event_table = start_event(scene, "guru_meditation_event", event_table)
		end

		event_table = update_events(scene, event_table)
		mouse:Update()

		local lines = {}
		dt = hg.TickClock()
		dts = hg.time_to_sec_f(dt)
		song_player_advance_clock(dt)

		walkman_button_on, walkman_button_hover, walkman_button_change_state, walkman_button_pressed_timeout, walkman_button_hover_hit =
			walkman_interaction_update(scene, mouse, res_vec2, dts, buttons, walkman_buttons_nodes, buttons_trs, walkman_button_on, walkman_button_hover, walkman_button_change_state, walkman_button_pressed_timeout)

		if config.enable_aaa then
			if walkman_button_hover_hit > -1 then
				dof_release_delay_timer = FOCUS_RELEASE_DELAY
			else
				dof_release_delay_timer = math.max(0.0, dof_release_delay_timer - dts)
			end

			local target_dof_focus_blend = 0.0
			if walkman_button_hover_hit > -1 or dof_release_delay_timer > 0.0 then
				target_dof_focus_blend = 1.0
			end

			local dof_focus_blend_step = dof_focus_blend_speed * dts
			if dof_focus_blend < target_dof_focus_blend then
				dof_focus_blend = math.min(dof_focus_blend + dof_focus_blend_step, target_dof_focus_blend)
			elseif dof_focus_blend > target_dof_focus_blend then
				dof_focus_blend = math.max(dof_focus_blend - dof_focus_blend_step, target_dof_focus_blend)
			end

			current_dof_focus_length = compute_dof_focus_length(FOCUS_LEN_MAX, FOCUS_LEN_WALKMAN, dof_focus_blend, FOCUS_CURVE_POWER)
			pipeline_aaa_config.dof_focus_length = current_dof_focus_length
		end

		song_player, walkman_osd, walkman_button_change_state, walkman_button_on =
			song_player_update(song_player, walkman_osd, walkman_button_change_state, walkman_button_on, walkman_button_pressed_timeout, config)

		local current_song = song_player_get_current_song(song_player)
		if current_song ~= nil then
			music_analysis_frame = music_analysis_sample(music_analysis, current_song.id, song_player_get_elapsed_seconds(song_player), music_analysis_frame)
			neural_state = neural_controller_update(neural_state, current_song.id, music_analysis_frame, dts)
			boid_params = neural_controller_get_boid_params(neural_state, music_analysis_frame, boid_params)
		end

		astronaut_wander_state = astronaut_wander.update(scene, dt, astronaut_wander_state)
		scene:Update(dt)
		if ENABLE_GROUND_FOG then
			ground_fog_time = ground_fog_time + dts
		end

		local astronaut_pos = astronaut_wander_state.transform:GetPos()
		if dts > 0.0 then
			astronaut_velocity = (astronaut_pos - astronaut_prev_pos) * (1.0 / dts)
		else
			astronaut_velocity = hg.Vec3(0.0, 0.0, 0.0)
		end
		astronaut_prev_pos = hg.Vec3(astronaut_pos.x, astronaut_pos.y, astronaut_pos.z)

		local view_id = 0
		local pass_ids
		if config.enable_aaa then
			view_id, pass_ids = hg.SubmitSceneToPipeline(view_id, scene, hg.IntRect(0, 0, res_x, res_y), true, pipeline, res, pipeline_aaa, pipeline_aaa_config, frame)
		else
			view_id, pass_ids = hg.SubmitSceneToPipeline(view_id, scene, hg.IntRect(0, 0, res_x, res_y), true, pipeline, res)
		end

		local opaque_view_id = hg.GetSceneForwardPipelinePassViewId(pass_ids, hg.SFPP_Opaque)
		for i = 1, #lines do
			draw_line(lines[i].pos_a, lines[i].pos_b, lines[i].color, opaque_view_id, vtx_line_layout, shader_for_line)
		end

		local transparent_view_id = hg.GetSceneForwardPipelinePassViewId(pass_ids, hg.SFPP_Transparent)
		aurora_time = aurora_draw(transparent_view_id, dt, aurora_model, shader_for_aurora, aurora_uniforms, aurora_render_state, aurora_time)

		boids_state = boids_update_draw(transparent_view_id, dt, boids_state, boid_params,
			boid_model, shader_for_boid, boid_uniforms, {},
			boid_render_state, dirt_particles.boundaries)

		if ENABLE_GROUND_FOG then
			ground_fog_particles = ground_fog_update_draw_model(transparent_view_id, dt, ground_fog_particles,
				particle_ground_fog_mdl, shader_for_ground_fog, ground_fog_uniforms, dirt_particle_tex_uniforms, particle_ground_fog_render_state,
				astronaut_pos, astronaut_velocity, ground_fog_time)
		end

		dirt_particles = particles_update_draw_model(transparent_view_id, dt, dirt_particles,
			particle_dirt_mdl, shader_for_particle, particle_uniforms, dirt_particle_tex_uniforms, particle_dirt_render_state)

		hg.SetViewPerspective(view_id, 0, 0, res_x, res_y, hg.TranslationMat4(hg.Vec3(0, 0, -0.5)))

		fade = math.min(1.0, fade + dts * 0.35)
		fade_pow = 2.0 - EaseInOutQuick(fade)

		view_id = view_id + 1
		hg.SetView2D(view_id, 0, 0, res_x, res_y, -1, 1, hg.CF_None, hg.Color.Black, 1, 0)
		view_id, scroll_x, char_offset, ns = update_demo_scroll_text(dt, view_id, res_x, res_y, scroll_x, char_offset, ns, scroll_text, font, font_program, font_size, text_render_state, EaseInOutQuick(fade))

		if boids_debug_visible then
			view_id = view_id + 1
			hg.ImGuiBeginFrame(res_x, res_y, dt, hg.ReadMouse(), keyboard_state)
			neural_controller_draw_debug(neural_state, music_analysis_frame, boids_state, boid_params)
			hg.SetView2D(view_id, 0, 0, res_x, res_y, -1, 1, hg.CF_None, hg.Color(0.0, 0.0, 0.0, 0.0), 1, 0)
			hg.ImGuiEndFrame(view_id)
		end

		if false then
			view_id = view_id + 1
			hg.SetViewClear(view_id, 0, 0, 1.0, 0)
			hg.SetViewRect(view_id, 0, 0, res_x, res_y)
			local cam_mat = cam:GetTransform():GetWorld()
			local view_matrix = hg.InverseFast(cam_mat)
			local cam_component = cam:GetCamera()
			local projection_matrix = hg.ComputePerspectiveProjectionMatrix(cam_component:GetZNear(), cam_component:GetZFar(), hg.FovToZoomFactor(cam_component:GetFov()), hg.Vec2(res_x / res_y, 1))
			hg.SetViewTransform(view_id, view_matrix, projection_matrix)
			local rs = hg.ComputeRenderState(hg.BM_Opaque, hg.DT_Disabled, hg.FC_Disabled)
			physics:RenderCollision(view_id, vtx_line_layout, shader_for_line, rs, 0)
		end

		frame = hg.Frame()
		hg.UpdateWindow(win)
		maybe_collect_garbage()
	end

	song_player_stop(song_player)
	hg.ImGuiShutdown()

	if profiler then
		profiler.stop()
		profiler.report("profiler.log")
	end
end

function main(cmd_arg)
	local config = {enable_aaa = true, low_aaa = false, skip_intro = true, winamp = false}

	hg.InputInit()
	hg.AudioInit()
	hg.WindowSystemInit()

	if cmd_arg[1] == "--launcher" then
		hg.AddAssetsFolder("data/assets_compiled")
	else
		hg.AddAssetsFolder("assets_compiled")
	end

	local win
	local config_done
	local default_res_x
	local default_res_y
	local default_fullscreen
	local full_aaa
	local low_aaa
	local no_aaa
	local winamp

	hg.ShowCursor()
	config_done, default_res_x, default_res_y, default_fullscreen, full_aaa, low_aaa, no_aaa, winamp = config_gui()

	local res_x = default_res_x
	local res_y = default_res_y
	config.winamp = winamp

	if config.winamp then
		res_x, res_y = winamp_ui.get_window_size()
		default_fullscreen = hg.WV_Windowed
	end

	if no_aaa then
		config.enable_aaa = false
	else
		config.enable_aaa = true
		config.low_aaa = low_aaa and true or false
	end

	if config_done == 1 then
		win = open_demo_window(res_x, res_y, default_fullscreen)
		if config.winamp then
			winamp_ui.run(win, res_x, res_y, config, songs)
		else
			run_demo_3d(win, res_x, res_y, config)
		end

		hg.RenderShutdown()
		hg.DestroyWindow(win)
	end

	hg.AudioShutdown()
	hg.WindowSystemShutdown()
	hg.InputShutdown()
end

main(arg)
