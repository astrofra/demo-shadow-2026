hg = require("harfang")
require("config_gui")

local function open_demo_window(res_x, res_y, default_fullscreen)
	local win = hg.NewWindow("Demo Shadow 2026", res_x, res_y, 32, default_fullscreen)
	hg.RenderInit(win)
	hg.RenderReset(res_x, res_y, hg.RF_VSync | hg.RF_MSAA4X | hg.RF_MaxAnisotropy)
	return win
end

local function create_pipeline_aaa(config)
	if not config.enable_aaa then
		return nil, nil
	end

	local pipeline_aaa_config = hg.ForwardPipelineAAAConfig()
	local pipeline_aaa = hg.CreateForwardPipelineAAAFromAssets("core", pipeline_aaa_config, hg.BR_Half, hg.BR_Half)

	if config.low_aaa then
		pipeline_aaa_config.temporal_aa_weight = 0.2
		pipeline_aaa_config.sample_count = 1
	else
		pipeline_aaa_config.temporal_aa_weight = 0.05
		pipeline_aaa_config.sample_count = 2
	end

	pipeline_aaa_config.z_thickness = 4.0
	pipeline_aaa_config.bloom_bias = 0.61
	pipeline_aaa_config.bloom_intensity = 1.74
	pipeline_aaa_config.bloom_threshold = 1.55
	pipeline_aaa_config.exposure = 1.59
	pipeline_aaa_config.gamma = 2.09

	return pipeline_aaa, pipeline_aaa_config
end

local function load_main_scene(res)
	local scene = hg.Scene()
	hg.LoadSceneFromAssets("main_scene.scn", scene, res, hg.GetForwardPipelineInfo())

	local cam = scene:GetNode("Camera")
	if not cam:IsValid() then
		error('Camera "Camera" not found in main_scene.scn')
	end

	scene:SetCurrentCamera(cam)
	return scene
end

local function run_demo_3d(win, res_x, res_y, config)
	local pipeline = hg.CreateForwardPipeline()
	local res = hg.PipelineResources()
	local scene = load_main_scene(res)
	local pipeline_aaa, pipeline_aaa_config = create_pipeline_aaa(config)
	local frame = 0

	while not hg.ReadKeyboard():Key(hg.K_Escape) and hg.IsWindowOpen(win) do
		local dt = hg.TickClock()
		scene:Update(dt)

		if config.enable_aaa then
			hg.SubmitSceneToPipeline(
				0,
				scene,
				hg.IntRect(0, 0, res_x, res_y),
				true,
				pipeline,
				res,
				pipeline_aaa,
				pipeline_aaa_config,
				frame
			)
		else
			hg.SubmitSceneToPipeline(
				0,
				scene,
				hg.IntRect(0, 0, res_x, res_y),
				true,
				pipeline,
				res
			)
		end

		frame = hg.Frame()
		hg.UpdateWindow(win)
	end
end

local function main(cmd_arg)
	local config = {enable_aaa = true, low_aaa = false}

	hg.InputInit()
	hg.WindowSystemInit()

	if cmd_arg[1] == "--launcher" then
		hg.AddAssetsFolder("data/assets_compiled")
	else
		hg.AddAssetsFolder("assets_compiled")
	end

	local config_done
	local res_x
	local res_y
	local default_fullscreen
	local low_aaa
	local no_aaa

	hg.ShowCursor()
	config_done, res_x, res_y, default_fullscreen, _, low_aaa, no_aaa = config_gui()

	if no_aaa then
		config.enable_aaa = false
	else
		config.enable_aaa = true
		config.low_aaa = low_aaa and true or false
	end

	if config_done == 1 then
		local win = open_demo_window(res_x, res_y, default_fullscreen)
		run_demo_3d(win, res_x, res_y, config)
		hg.RenderShutdown()
		hg.DestroyWindow(win)
	end

	hg.WindowSystemShutdown()
	hg.InputShutdown()
end

main(arg)
