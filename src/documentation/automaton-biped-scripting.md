# Automaton Biped Scripting Guide

## Overview

This document describes how to script the procedural automaton biped driven by `automaton_controller.lua`.

The controller combines several orthogonal subsystems:

- locomotion on the XZ plane
- in-place rotation by discrete turning steps
- independent arm lock and unlock blending
- persistent pelvis height offset with leg IK foot planting
- object grabbing with release and ungrab per hand
- persistent head and neck look-at
- persistent scripted camera selection and tracking
- non-blocking keyed sound playback and keyed instance animation playback
- a blocking action sequence runner

The goal is staged character choreography.
This is not a generic AI system and it is not a physics-driven character controller.

## Module Setup

Create the controller from Lua like this:

```lua
local automaton_controller_lib = require("automaton_controller")

local ctrl = automaton_controller_lib.CreateAutomatonController(scene, "automaton-rig-tpose")
```

Update it once per frame:

```lua
ctrl:Update(dt_sec)
```

Typical integration:

```lua
local automaton_controller_lib = require("automaton_controller")
local ctrl = automaton_controller_lib.CreateAutomatonController(scene, "automaton-rig-tpose")

while running do
	scene:Update(dt)
	ctrl:Update(dt_sec)
end
```

## Node Reference Rules

Most scripting calls use string node references.

The controller resolves references in this order:

1. `Scene.GetNodeEx(path)`
2. the automaton instance `SceneView` by short internal name
3. `Scene.GetNode(name)`

This means the following styles are all supported:

- host scene nodes such as `path_A`
- host scene nodes such as `telephone_receiver`
- absolute scene paths compatible with `Scene.GetNodeEx`
- instance paths such as `automaton-rig-tpose:phone_ear_anchor`
- short internal automaton node names such as `hand_target_A`

Practical recommendation:
use `Scene.GetNodeEx`-style paths whenever possible, especially for authored anchors in the host scene.

## Public API

The controller currently exposes these methods.

### Movement

```lua
ctrl:MoveToNode(target_name)
ctrl:MoveFromNodeToNode(start_name, target_name)

ctrl:RotateToNode(target_name)
ctrl:RotateFromNodeToNode(start_name, target_name)

ctrl:IsMoving()
ctrl:IsAtTarget()
ctrl:IsRotationDone()
ctrl:GetCurrentTargetNodeName()
```

Behavior:

- `MoveToNode` moves the biped toward a target node on the world XZ plane.
- `MoveFromNodeToNode` first places the biped at `start_name`, then starts the move.
- `RotateToNode` rotates in place until the biped faces the target node.
- `RotateFromNodeToNode` first places the biped at `start_name`, then starts the rotation.
- `IsMoving()` only reports movement state, not rotation state.
- `IsAtTarget()` only reports movement completion.
- `IsRotationDone()` reports rotation completion.
- `GetCurrentTargetNodeName()` returns the currently active move or rotate target, or `nil`.

### Arm Locking

```lua
ctrl:PlaceLeftHandOnNode(target_name)
ctrl:PlaceRightHandOnNode(target_name)
ctrl:UnlockLeftHand(duration_sec)
ctrl:UnlockRightHand(duration_sec)
```

Behavior:

- locking a hand blends from free swing to IK hand placement over `1.0` second
- unlocking blends back to procedural walk swing over `duration_sec`
- if `duration_sec` is omitted, unlock uses the default `1.0` second transition
- `duration_sec = 0.0` makes the unlock immediate
- left and right hands are fully independent
- a locked hand keeps following its target until it is explicitly unlocked

### Body Pose

```lua
ctrl:SetFreeArmAmplitude(side, amplitude)
ctrl:SetBendDegrees(degrees)
ctrl:SetKneelOffsetY(offset_y, duration_sec)
```

Behavior:

- `SetFreeArmAmplitude` clamps `amplitude` between `0.0` and `1.0`
- `SetBendDegrees` animates a persistent torso bend over `2.0` seconds
- `SetKneelOffsetY` animates a persistent pelvis Y offset over `duration_sec`
- if `duration_sec` is omitted, `SetKneelOffsetY` uses the default `1.0` second transition
- negative `offset_y` lowers the pelvis and bends the legs
- positive `offset_y` raises the pelvis again
- feet stay planted through the existing leg IK system; the applied offset is clamped if leg reach would be exceeded

### Object Grabbing

```lua
ctrl:GrabNodeWithLeftHand(node_ref)
ctrl:GrabNodeWithRightHand(node_ref)
ctrl:ReleaseLeftHandObject()
ctrl:ReleaseRightHandObject()
ctrl:UngrabLeftHandObject()
ctrl:UngrabRightHandObject()
```

Behavior:

- one held object maximum per hand
- grab has no distance check
- grab may teleport the object to the hand
- the object snaps immediately to the hand and is then parented to it
- if the hand already holds something, that object is released first
- release restores the current world transform, then reparents to the original parent if still valid
- if the original parent is gone, release detaches the object to world space
- ungrab restores the current world transform, then always detaches the object to world space

Implementation note:
the controller first tries to parent directly to the internal hand node.
If cross-instance parenting does not hold at runtime, it falls back to a host-scene proxy node that follows the hand every frame.

### Look-At

```lua
ctrl:LookAtNode(node_ref, stiffness)
ctrl:ClearLookAt(stiffness)
```

Behavior:

- `LookAtNode` blends into a persistent tracking state over `1.0` second
- optional `stiffness` limits the neck/head angular speed in degrees per second
- if `stiffness` is omitted, look-at uses the default `90 degrees/sec`
- the target is the target node position, not its orientation
- after the blend, the neck and head keep tracking the target until `ClearLookAt()` is called
- `ClearLookAt()` blends back to the captured rest pose over `1.0` second
- `ClearLookAt()` accepts the same optional `stiffness` parameter
- if `ClearLookAt()` omits `stiffness`, it reuses the currently active look-at stiffness

Current look distribution:

- neck: `40%`
- head: `60%`

Current angular limits:

- target clamp before distribution: yaw `+-40 degrees`
- target clamp before distribution: pitch up `+20 degrees`
- target clamp before distribution: pitch down `-10 degrees`
- effective neck contribution at full blend: yaw `+-16 degrees`
- effective neck contribution at full blend: pitch up `+8 degrees`
- effective neck contribution at full blend: pitch down `-4 degrees`
- effective head contribution at full blend: yaw `+-24 degrees`
- effective head contribution at full blend: pitch up `+12 degrees`
- effective head contribution at full blend: pitch down `-6 degrees`
- roll: none

The rest pose is captured from the automaton rig when the controller is created.

### Camera

```lua
ctrl:SetCurrentCamera(camera_name, options)
```

Behavior:

- selects a scene camera node and calls `scene:SetCurrentCamera()` immediately
- `camera_name` is the node carrying the Camera component, for example `"Camera"` or `"Camera2"`
- camera behavior is persistent until another camera command overrides it
- the action sequence command is non-blocking and completes immediately
- optional `FOV`/`fov` is expressed in degrees and blends over `1.0` second
- optional `tracking` keeps the camera position unchanged and smooths only its rotation toward a target node
- optional `steady_cam` follows a target node with latency, at a configurable horizontal distance
- optional `offset` is a fixed world-space vector added to the tracked target position
- `tracking` and `steady_cam` are mutually exclusive in one command

Steady-cam angle convention:

- `angle = 0` places the camera in front of the target along its velocity vector
- `angle = 180` places the camera behind the target
- `angle = 90` places the camera on the target's right side
- `angle = -90` places the camera on the target's left side

`steady_cam` waits until the target has moved enough to infer a velocity direction. Until then, the camera does not change its position from the velocity-relative rule, but it can already rotate toward the target.

### Audio

```lua
ctrl:PlaySound(sound_id, asset_name, options)
ctrl:StopSound(sound_id)
```

Behavior:

- `PlaySound()` plays an asset-backed audio file in `sound` mode, not as a stream
- currently supported sound asset formats are `.ogg` and `.wav`
- `asset_name` is an asset-relative path such as `"audio/ring.ogg"`
- optional `options.loop = true` loops the sound; by default it plays once
- reusing the same `sound_id` stops the previous source before the new one starts
- `StopSound(sound_id)` stops the currently active source for that id immediately
- stopping an unknown `sound_id` is a no-op

### Instance Animation

```lua
ctrl:PlayInstanceNodeAnimation(playback_id, node_ref, animation_name, options)
ctrl:StopInstanceNodeAnimation(playback_id)
```

Behavior:

- `node_ref` must resolve to a node carrying an instantiated scene
- the controller fetches the animation with `Node:GetInstanceSceneAnim(animation_name)`
- optional `options.loop = true` loops the animation; by default it plays once
- reusing the same `playback_id` stops the previous playing animation ref before starting the new one
- `StopInstanceNodeAnimation(playback_id)` stops the currently active animation for that id immediately
- this is useful for switching a looping instance animation such as `ring` back to `still`

### Sequence Runner

```lua
ctrl:RunActionSequence(actions)
ctrl:StopActionSequence()
ctrl:IsActionSequenceRunning()
```

Behavior:

- actions are blocking unless their completion semantics explicitly say otherwise
- the next action starts only when the current one is considered complete
- `StopActionSequence()` only stops the sequence runner itself
- persistent subsystem states are not automatically reset on stop

Examples:

- a locked arm stays locked after the sequence stops
- a held object stays held after the sequence stops
- a look-at target stays active after the sequence stops
- a looping sound keeps playing after the sequence stops until its id is stopped or replaced
- a looping instance animation keeps playing after the sequence stops until its id is stopped or replaced
- a movement or rotation already started is not cancelled by `StopActionSequence()`

## Action Sequence Format

Canonical action types:

- `move`
- `rotate`
- `lock_arm`
- `unlock_arm`
- `arm_amplitude`
- `grab`
- `release`
- `ungrab`
- `bend`
- `kneel`
- `look_at`
- `clear_look_at`
- `say`
- `sound`
- `instance_animation`
- `camera`

The action type normalizer also accepts spaces and hyphens.
For example, `lock arm` and `lock-arm` will be interpreted as `lock_arm`.

### Supported Action Fields

`move`

```lua
{type = "move", target = "path_B"}
{type = "move", start = "path_A", target = "path_B"}
```

`rotate`

```lua
{type = "rotate", target = "path_B"}
{type = "rotate", start = "path_A", target = "path_B"}
```

`lock_arm`

```lua
{type = "lock_arm", side = "left", target = "automaton-rig-tpose:watering_anchor"}
```

`unlock_arm`

```lua
{type = "unlock_arm", side = "left"}
{type = "unlock_arm", side = "left", duration = 1.0}
```

`arm_amplitude`

```lua
{type = "arm_amplitude", side = "left", value = 0.0}
{type = "arm_amplitude", side = "right", amplitude = 0.5}
```

`grab`

```lua
{type = "grab", side = "right", target = "telephone_receiver"}
```

`release`

```lua
{type = "release", side = "right"}
```

`ungrab`

```lua
{type = "ungrab", side = "right"}
```

`bend`

```lua
{type = "bend", value = 20}
{type = "bend", degrees = -10}
```

`kneel`

```lua
{type = "kneel", offset_y = -0.12, duration = 0.8}
{type = "kneel", value = 0.0, duration = 0.6}
```

`look_at`

```lua
{type = "look_at", target = "path_C"}
{type = "look_at", target = "path_C", stiffness = 90}
```

`clear_look_at`

```lua
{type = "clear_look_at"}
{type = "clear_look_at", stiffness = 90}
```

`say`

```lua
{type = "say", text = "Hello from the automaton"}
{type = "say", text = "Bonjour", lang = "fr", volume = 0.8}
{type = "say", phrase = "ax ay iy", phonemes = true}
```

`sound`

```lua
{type = "sound", id = "phone_ring_audio", asset = "audio/ring.ogg"}
{type = "sound", id = "phone_ring_audio", asset = "audio/ring.ogg", loop = true}
{type = "sound", id = "phone_ring_audio", stop = true}
```

`instance_animation`

```lua
{type = "instance_animation", id = "phone_ring_anim", node = "telephone_speaker", animation = "ring", loop = true}
{type = "instance_animation", id = "phone_ring_anim", animation = "still"}
{type = "instance_animation", id = "phone_ring_anim", stop = true}
```

`camera`

```lua
{type = "camera", camera = "Camera2"}
{type = "camera", camera = "Camera2", FOV = 45}
{type = "camera", camera = "Camera2", tracking = "automaton-rig-tpose"}
{type = "camera", camera = "Camera2", tracking = {target = "automaton-rig-tpose", latency = 0.35}}
{type = "camera", camera = "Camera2", tracking = {target = "automaton-rig-tpose", offset = {0.0, 1.4, 0.0}}}
{type = "camera", camera = "Camera2", steady_cam = {target = "automaton-rig-tpose", distance = 5.0, angle = 180}}
{type = "camera", camera = "Camera2", steady_cam = {target = "automaton-rig-tpose", distance = 5.0, angle = 90, offset = hg.Vec3(0.0, 1.2, 0.0)}}
```

Aliases:

- `set_camera` is accepted as an action type
- `camera`, `camera_node`, `node`, or `name` can identify the camera node
- `fov` and `FOV` are both accepted
- `track` is accepted as an alias for `tracking`
- `steady`, `steadycam`, `steady_cam`, `steady cam`, and `steady-cam` are accepted for steady-cam mode
- `offset` accepts `hg.Vec3(x, y, z)`, `{x, y, z}`, or `{x = x, y = y, z = z}`
- top-level `offset` is accepted when `tracking`/`steady_cam` is just a target string

`side` accepts `left` or `right`.
The implementation lowercases the input, so `Left` and `RIGHT` are also accepted.

`sound` details:

- `id` is required; `playback_id` is accepted as an alias
- to play a sound, `asset`, `path`, `sound`, or `file` is required
- the asset path is resolved from the HARFANG assets system, for example `"audio/ring.ogg"`
- the sound is loaded and played as a `sound`, not streamed
- `loop` or `repeat` is optional and must be a boolean
- `once` is accepted as the inverse of `loop`
- if no loop flag is provided, the sound plays once
- `stop = true` stops the current playback for that id and ignores play fields
- if the same id is played again while already active, the previous source is stopped first
- the action is non-blocking

`say` details:

- `text`, `phrase`, or `value` is required
- playback is synthesized on demand through the Lua `say` module, using `format = "raw"`
- the generated buffer is bridged to HARFANG with `LoadLPCMSound(..., AFF_LPCM_44KHZ_S16_Mono)`
- `lang` or `language` is optional
- `volume` or `gain` is optional and defaults to `1.0`
- `phonemes`, `amiga`, and `frame_ms` are forwarded when provided
- this command currently expects the synth output to be mono 16-bit LPCM at `44100 Hz`
- starting a new `say` playback stops and replaces the previous one if it is still active
- the action is blocking until the spoken audio source reaches `SS_Stopped`

`instance_animation` details:

- `id` is required; `playback_id` is accepted as an alias
- `animation`, `anim`, or `name` is required when starting playback
- `node`, `target`, `instance`, or `node_ref` is required the first time an id is used
- when an id is already active, `node` may be omitted and the previous node is reused
- `loop` or `repeat` is optional and must be a boolean
- `once` is accepted as the inverse of `loop`
- if no loop flag is provided, the animation plays once
- `stop = true` stops the current playback for that id and ignores play fields
- replaying the same id stops the previous animation ref before the new animation starts
- accepted action type aliases are `instance_anim`, `node_animation`, and `node_anim`
- the action is non-blocking

`arm_amplitude` details:

- `side` is required
- `value` or `amplitude` is required
- values are clamped between `0.0` and `1.0`
- `0.0` keeps the unlocked arm visually fixed
- `1.0` keeps the current default free-arm swing amplitude

`bend` details:

- `value`, `degrees`, or `angle` is required
- the value is interpreted in degrees
- positive values bend the torso forward
- negative values bend the torso backward
- the bend is distributed across `mixamorig_Spine`, `mixamorig_Spine1`, and `mixamorig_Spine2`
- the bend animation is blocking and lasts `2.0` seconds

`kneel` details:

- `offset_y`, `offset`, `value`, or `y` is required
- the value is interpreted as a pelvis local Y offset
- negative values lower the pelvis
- positive values raise the pelvis again
- `duration` or `time` controls the kneel animation length in seconds
- if omitted, duration defaults to `1.0`
- the animation is blocking
- the applied offset is clamped by leg reach so the feet stay on their IK plant targets

`unlock_arm` details:

- `side` is required
- `duration` or `time` is optional and expressed in seconds
- if omitted, duration defaults to `1.0`
- `0.0` unlocks immediately
- the action is blocking until the unlock blend reaches `0.0`

`look_at` and `clear_look_at` details:

- `look_at` requires `target`
- `stiffness`, `speed`, or `angular_speed` is optional
- the value is interpreted in degrees per second
- if omitted, stiffness defaults to `90`
- `clear_look_at` reuses the current stiffness when omitted
- the controller clamps the gaze target before distribution to neck/head
- the action stays blocking until both the blend and the angular settling are complete

### Action Completion Semantics

- `move`: completes when `IsAtTarget()` becomes true
- `rotate`: completes when `IsRotationDone()` becomes true
- `lock_arm`: completes when the blend reaches `1.0`
- `unlock_arm`: completes when the blend reaches `0.0` after the requested duration
- `arm_amplitude`: completes immediately after updating the selected side amplitude
- `grab`: completes immediately after the parenting operation
- `release`: completes immediately after the reparenting operation
- `ungrab`: completes immediately after the world detach operation
- `bend`: completes when the 2-second torso bend animation reaches its target
- `kneel`: completes when the pelvis offset animation reaches its target duration
- `look_at`: completes when the look blend reaches `1.0` and the neck/head have settled to the requested look target
- `clear_look_at`: completes when the look blend reaches `0.0` and the neck/head have settled back to rest
- `say`: completes when the synthesized speech playback reaches `SS_Stopped`
- `sound`: completes immediately after starting or stopping the keyed playback
- `instance_animation`: completes immediately after starting or stopping the keyed playback
- `camera`: completes immediately after changing the camera state

## Movement and Rotation Semantics

### Move

`move` is standard locomotion.

Important traits:

- translation happens on the XZ plane only
- the character can turn before stepping forward
- if heading error is large enough, the controller enters a turn-in-place locomotion state
- feet are procedurally planted and swung through the existing leg IK system
- free arms swing automatically while walking unless they are locked
- `arm_amplitude` scales that unlocked swing independently for the left and right arms

### Rotate

`rotate` is a dedicated in-place turning mode designed for staged motion.

Current implementation details:

- the biped rotates in discrete `10 degree` steps
- each turning step swaps the support foot
- the planted support foot acts as the pivot
- the swing foot is relocated on the ground plane
- there is a short pause between turning steps
- rotation ends when the remaining yaw error is within `1 degree`

This produces a simple robotic compromise:
clear orientation control, visible footwork, and low implementation complexity.

## Persistence Rules

Subsystems are persistent by design.

- movement persists until the current target is reached or another movement command overrides it
- rotation persists until the facing target is reached or another locomotion command overrides it
- a hand lock persists until that hand is unlocked
- a held object persists until that hand releases or ungrabs it
- a kneel offset persists until another `kneel` command overrides it
- look-at persists until `ClearLookAt()` is called
- a looping sound persists until the same `sound` id is stopped or replaced; a one-shot sound persists until it ends
- a looping instance animation persists until the same `instance_animation` id is stopped or replaced; a one-shot animation persists until it ends
- camera selection, camera tracking mode, and steady-cam mode persist until another camera command overrides them

This is important when building sequences.
You do not need to repeat persistent commands every frame.

## Direct Calls vs. Sequence Runner

Both styles are valid.

Use direct calls when:

- you are prototyping interactively
- you want manual control from debug keys
- you need immediate one-off reactions

Use `RunActionSequence()` when:

- you want authored choreography
- you want blocking order without hand-written state code
- you are building narrative scenes

Practical recommendation:
avoid mixing ad-hoc direct calls with an active sequence unless you are intentionally overriding the current staged action.

## Example: Simple Direct Scripting

```lua
local automaton_controller_lib = require("automaton_controller")
local ctrl = automaton_controller_lib.CreateAutomatonController(scene, "automaton-rig-tpose")

ctrl:MoveFromNodeToNode("path_A", "path_B")

if ctrl:IsAtTarget() then
	ctrl:RotateToNode("telephone_receiver")
end

if ctrl:IsRotationDone() then
	ctrl:PlaceRightHandOnNode("automaton-rig-tpose:phone_ear_anchor")
end
```

## Example: Narrative Sequence

```lua
local actions = {
	{type = "camera", camera = "Camera2", steady_cam = {target = "automaton-rig-tpose", distance = 5.0, angle = 180}, FOV = 45},
	{type = "move", start = "path_A", target = "watering_can_pickup"},
	{type = "rotate", target = "watering_can_pickup"},
	{type = "grab", side = "right", target = "watering_can"},
	{type = "move", target = "plants_A"},
	{type = "lock_arm", side = "right", target = "automaton-rig-tpose:watering_anchor"},
	{type = "look_at", target = "plants_A"},
	{type = "clear_look_at"},
	{type = "unlock_arm", side = "right"},
	{type = "release", side = "right"},
	{type = "move", target = "telephone_area"},
	{type = "rotate", target = "telephone_receiver"},
	{type = "grab", side = "right", target = "telephone_receiver"},
	{type = "lock_arm", side = "right", target = "automaton-rig-tpose:phone_ear_anchor"},
	{type = "look_at", target = "caller_focus_A"}
}

ctrl:RunActionSequence(actions)
```

## Example: Phone Ring Cue

```lua
local actions = {
	{type = "sound", id = "phone_ring_audio", asset = "audio/ring.ogg", loop = true},
	{type = "instance_animation", id = "phone_ring_anim", node = "telephone_speaker", animation = "ring", loop = true},
	{type = "move", start = "path_A", target = "telephone_area"},
	{type = "rotate", target = "telephone_receiver"},
	{type = "sound", id = "phone_ring_audio", stop = true},
	{type = "instance_animation", id = "phone_ring_anim", animation = "still"}
}

ctrl:RunActionSequence(actions)
```

## Debug State

The controller exposes a compact runtime snapshot through:

```lua
local debug_state = ctrl:GetDebugState()
```

Current fields:

- `state`
- `target`
- `distance_to_target`
- `yaw_error_deg`
- `rotation_target_active`
- `current_speed`
- `gait_drive`
- `bend_deg`
- `kneel_offset_y`
- `left_arm_amplitude`
- `right_arm_amplitude`
- `support_side`
- `step_progress`
- `step_pause_timer`
- `locomotion_speed`
- `left_hand`
- `right_hand`
- `held_left`
- `held_right`
- `look_target`
- `look_blend`
- `camera`
- `camera_mode`
- `camera_target`
- `current_action_type`
- `action_index`

This is mainly intended for in-game debug UI and staging.

## Current Constraints

This controller is intentionally simple.

- no pathfinding
- no obstacle avoidance
- no grasp distance validation
- no finger animation
- no drop physics
- no authored animation blending
- no callback system inside the action runner
- no concurrent multi-action scheduling inside one sequence

## Recommended Scene Authoring Workflow

- create clear host-scene path markers for travel points
- create explicit look targets as separate nodes when you want clean gaze control
- create explicit hand anchors near props or body landmarks
- expose detachable props such as the phone receiver as separate nodes
- prefer stable, named anchors over hardcoded offsets in Lua

The controller works best when the scene provides intentional staging nodes.
