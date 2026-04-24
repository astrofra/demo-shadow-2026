# Automaton Biped Scripting Guide

## Overview

This document describes how to script the procedural automaton biped driven by `automaton_controller.lua`.

The controller combines several orthogonal subsystems:

- locomotion on the XZ plane
- in-place rotation by discrete turning steps
- independent arm lock and unlock blending
- object grabbing and releasing per hand
- persistent head and neck look-at
- persistent scripted camera selection and tracking
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
ctrl:UnlockLeftHand()
ctrl:UnlockRightHand()
```

Behavior:

- locking a hand blends from free swing to IK hand placement over `1.0` second
- unlocking blends back to procedural walk swing over `1.0` second
- left and right hands are fully independent
- a locked hand keeps following its target until it is explicitly unlocked

### Object Grabbing

```lua
ctrl:GrabNodeWithLeftHand(node_ref)
ctrl:GrabNodeWithRightHand(node_ref)
ctrl:ReleaseLeftHandObject()
ctrl:ReleaseRightHandObject()
```

Behavior:

- one held object maximum per hand
- grab has no distance check
- grab may teleport the object to the hand
- the object snaps immediately to the hand and is then parented to it
- if the hand already holds something, that object is released first
- release restores the current world transform, then reparents to the original parent if still valid
- if the original parent is gone, release detaches the object to world space

Implementation note:
the controller first tries to parent directly to the internal hand node.
If cross-instance parenting does not hold at runtime, it falls back to a host-scene proxy node that follows the hand every frame.

### Look-At

```lua
ctrl:LookAtNode(node_ref)
ctrl:ClearLookAt()
```

Behavior:

- `LookAtNode` blends into a persistent tracking state over `1.0` second
- the target is the target node position, not its orientation
- after the blend, the neck and head keep tracking the target until `ClearLookAt()` is called
- `ClearLookAt()` blends back to the captured rest pose over `1.0` second

Current look distribution:

- neck: `40%`
- head: `60%`

Current angular limits:

- yaw: `+-70 degrees`
- pitch up: `+35 degrees`
- pitch down: `-45 degrees`
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

### Sequence Runner

```lua
ctrl:RunActionSequence(actions)
ctrl:StopActionSequence()
ctrl:IsActionSequenceRunning()
```

Behavior:

- actions are blocking
- the next action starts only when the current one is considered complete
- `StopActionSequence()` only stops the sequence runner itself
- persistent subsystem states are not automatically reset on stop

Examples:

- a locked arm stays locked after the sequence stops
- a held object stays held after the sequence stops
- a look-at target stays active after the sequence stops
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
- `bend`
- `look_at`
- `clear_look_at`
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

`bend`

```lua
{type = "bend", value = 20}
{type = "bend", degrees = -10}
```

`look_at`

```lua
{type = "look_at", target = "path_C"}
```

`clear_look_at`

```lua
{type = "clear_look_at"}
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
- the bend is distributed across `mixamorig:Spine`, `mixamorig:Spine1`, and `mixamorig:Spine2`
- the bend animation is blocking and lasts `2.0` seconds

### Action Completion Semantics

- `move`: completes when `IsAtTarget()` becomes true
- `rotate`: completes when `IsRotationDone()` becomes true
- `lock_arm`: completes when the blend reaches `1.0`
- `unlock_arm`: completes when the blend reaches `0.0`
- `arm_amplitude`: completes immediately after updating the selected side amplitude
- `grab`: completes immediately after the parenting operation
- `release`: completes immediately after the reparenting operation
- `bend`: completes when the 2-second torso bend animation reaches its target
- `look_at`: completes when the look blend reaches `1.0`
- `clear_look_at`: completes when the look blend reaches `0.0`
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
- a held object persists until that hand releases it
- look-at persists until `ClearLookAt()` is called
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
