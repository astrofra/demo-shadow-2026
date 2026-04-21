# Skills for an AI Coding Agent Building HARFANG Projects From Scratch

## Purpose

This document defines the capabilities an AI coding agent should have in order to create, extend, debug, and ship a real-time 3D project with HARFANG from an empty or near-empty repository.

The target is not a toy script. The target is a runnable, maintainable, automatable project with a clear asset pipeline, a stable runtime loop, and a release path.

## Agent Mission

The agent should be able to:

- bootstrap a HARFANG project from zero
- create a minimal runnable vertical slice early
- grow the project without losing structure
- automate repetitive build and content steps
- expose debugging and tuning tools
- package the result into a distributable build

## Core Working Principles

### 1. Start runnable, then expand

The first milestone should always be a project that opens a window, runs a frame loop, and renders something visible. Every later system should be added on top of that baseline.

### 2. Keep source, generated data, compiled assets, and packaged output separate

The agent should treat these as different layers:

- source code and editable assets
- generated runtime data
- compiled/imported assets
- packaged release output

Mixing them makes automation and debugging harder.

### 3. Prefer explicit data flow

Systems should not hide state in too many implicit globals. The agent should favor clear ownership of runtime state, straightforward Lua modules, and visible dependencies between update and draw steps.

### 4. Move heavy work offline when possible

Expensive analysis, conversion, asset preparation, content validation, and data generation should be done in scripts outside the real-time loop whenever practical.

### 5. Make every system observable

If a system is important, it should be debuggable. The agent should expose internal state through logs, debug drawing, overlays, or small UI tools.

### 6. Fail clearly

Missing assets, bad scene naming, broken config, or unsupported runtime assumptions should produce clear errors. Silent failure wastes time.

## Skill Map

| Skill Area | Priority | What the agent must be able to produce |
| --- | --- | --- |
| Project scaffolding | Critical | A clean repository layout, run scripts, and a first runnable app |
| HARFANG runtime lifecycle | Critical | Window, input, render, update loop, resize handling, shutdown |
| Lua architecture | Critical | Maintainable runtime modules with explicit state flow |
| Filesystem, paths, and asset namespace management | High | Safe local and asset-path access, packages, persistence, and path-aware generation |
| Math, transforms, and spatial reasoning | Critical | Cameras, transforms, projection, picking, bounds, and view-state computations |
| Asset and scene pipeline | Critical | Import, compile, organize, and load scenes and resources |
| Scene scripting and systems orchestration | High | Scene script lifecycle, host-script communication, and system updates |
| Rendering and shaders | Critical | Cameras, lights, pipelines, materials, render targets, custom effects |
| Input and interaction | High | Keyboard, mouse, gamepad, UI capture handling, and scene-space interactions |
| Animation and actor control | High | Scene-driven behaviors, animation playback, FSM-based controllers |
| Physics integration | High | Rigid bodies, collisions, impulses, system sync, and debug visualization |
| Low-level geometry, text, image, and capture workflows | High | Generated meshes, immediate drawing, text rendering, picture I/O, and capture/export |
| Procedural systems | High | Particles, simulation, generated meshes, reactive effects |
| Audio and reactive data | High | Playback, transport, timing, offline analysis, runtime sampling |
| Debug UI and instrumentation | High | ImGui tools, debug views, overlays, tuning controls |
| Tooling and automation | Critical | Build scripts, validators, generators, packaging scripts |
| Performance and validation | High | Runtime stability, bounded costs, profiling, smoke checks, and release verification |
| XR/VR and immersive runtime | Optional | Stereo rendering, tracked input, eye buffers, and XR frame submission |
| Binding and API-surface literacy | Critical | Using HARFANG bindings and tutorials to discover capabilities and call shapes |

## Detailed Skills

### 1. Project Scaffolding

The agent must know how to create a workable project skeleton before adding features.

It should be able to define:

- a source code directory for Lua runtime code
- a source asset directory for editable scenes, textures, audio, and shaders
- a compiled asset directory for imported or built runtime assets
- a tools directory for Python, PowerShell, or batch automation
- a release or package output directory
- one-command or one-script local startup

Expected deliverables:

- a minimal folder structure
- a startup script
- a basic configuration file or config entry point
- a short README describing how to run and build the project

Definition of done:

- a fresh checkout can be started without manual file shuffling

### 2. HARFANG Runtime Lifecycle

The agent must be able to build the application shell around HARFANG.

This includes:

- window initialization
- input initialization
- audio initialization when needed
- render initialization and reset
- per-frame ticking
- resize handling
- orderly shutdown

The agent should understand the difference between:

- initialization time setup
- per-frame update logic
- per-frame rendering
- final cleanup

Definition of done:

- the project runs a stable main loop and exits cleanly

### 3. Lua Runtime Architecture

The agent must be able to structure Lua code so the project can grow without turning into a pile of script fragments.

Required habits:

- small focused modules
- explicit function arguments
- clear ownership of mutable state
- simple naming conventions
- minimal hidden coupling

The agent should be comfortable with:

- update/draw separation
- controller state tables
- data-oriented utility functions
- generated Lua data files for runtime lookup

Definition of done:

- adding a new system does not require rewriting the project core

### 4. Filesystem, Paths, and Asset Namespace Management

The agent must understand that HARFANG projects usually operate in more than one resource space.

This includes:

- local file access versus mounted asset access
- mounted asset folders versus packaged asset archives
- path normalization and path joining
- recursive directory listing and existence checks
- text, binary, and generated data persistence
- safe decisions about which files belong in source, generated data, compiled assets, or release output

The agent should be able to decide when to use:

- a local filesystem path
- an asset-relative path
- a generated runtime file
- a captured output such as a screenshot or exported image

Definition of done:

- the agent can build and maintain a path-safe workflow without confusing local files and runtime assets

### 5. Math, Transforms, and Spatial Reasoning

The agent must be able to reason directly about HARFANG spatial primitives instead of treating them as opaque engine values.

This includes:

- vectors, matrices, quaternions, and Euler conversions
- world, local, and view transforms
- look-at matrices and transform builders
- perspective and orthographic view state computation
- screen-space projection and coordinate conversion
- bounds, min-max boxes, and simple ray or visibility tests

This skill is required for:

- cameras
- picking
- actor steering
- chase cameras
- diegetic UI
- debug overlays over world objects

Definition of done:

- the agent can derive and debug transform math needed for cameras, projection, interaction, and spatial queries

### 6. Asset and Scene Pipeline

The agent must be able to build a reliable path from editable content to runtime content.

This includes:

- organizing source assets
- compiling or importing assets for HARFANG runtime use
- maintaining scene naming conventions
- defining how scripts locate cameras, lights, anchors, and interactable nodes
- handling texture, mesh, material, animation, and scene dependencies
- acquiring required engine-side rendering resources when they are not already present in the project

The agent should design scene conventions intentionally, for example:

- anchor node naming
- animation naming
- interaction node naming
- debug-only nodes
- content folders by feature or asset type

For greenfield setups, the `core/` folder that contains the rendering pipeline shaders can be fetched from `https://github.com/harfang3d/harfang-core-package.git`, then unzipped and renamed to `core/`.

Definition of done:

- a scene can be authored once and consumed predictably by runtime code

### 7. Scene Scripting and Systems Orchestration

The agent must understand HARFANG scene systems as more than a plain `scene:Update(dt)` call.

This includes:

- scene clocks and system update ordering
- scene Lua script VMs
- creating scene scripts from source, files, or assets
- host-to-scene and scene-to-host value exchange
- script lifecycle, garbage collection, and cleanup
- orchestrating scene updates together with physics and scripted systems

The agent should also know when a coroutine-based sequence is enough and when a full controller or FSM is the better fit.

Definition of done:

- the agent can wire scene logic through engine systems rather than forcing everything into a single host-side script

### 8. Rendering, Materials, and Shaders

The agent must be able to work beyond a default scene render.

Core rendering skills:

- forward pipeline setup
- camera configuration
- light setup
- material loading and updates
- shader uniform management
- render state setup
- view and pass organization
- rendering to textures or framebuffers

Advanced expectations:

- custom shader integration
- post-process or compositing passes
- multi-viewport rendering
- built-in post effects such as AAA, DOF, bloom, or ambient occlusion when appropriate
- immediate-mode drawing when useful
- dynamic texture workflows when useful

Definition of done:

- the agent can implement both standard scene rendering and at least one custom visual effect path

### 9. Input and Interaction

The agent must be able to create interaction systems, not just passive rendering.

This includes:

- keyboard input
- mouse input
- gamepad input when relevant
- device discovery when multiple input devices are present
- screen-space UI interaction
- world-space interaction
- projected hit areas or pick logic
- interaction feedback

The agent should know how to connect interaction with runtime systems such as:

- transport controls
- camera mode switches
- object toggles
- debug actions
- scene events

It should also handle input arbitration correctly when debug UI is active, for example when ImGui should capture mouse or keyboard focus.

Definition of done:

- a user can reliably control at least one meaningful runtime system

### 10. Animation and Actor Controllers

The agent must be able to drive scene actors with code.

Required capabilities:

- locating animation-capable scene nodes
- playing and stopping instance animations
- building finite state machines
- separating motion logic from animation playback logic
- using scene anchors instead of hardcoded paths where possible

The agent should be able to implement controllers for:

- idle, walk, turn, and action states
- patrol or wander behaviors
- event-triggered scene reactions
- presentation or scripted sequence logic

Definition of done:

- a character or scene actor can be controlled by a readable runtime controller with predictable transitions

### 11. Physics Integration

The agent must treat physics as a dedicated subsystem with its own constraints and lifecycle.

Required capabilities:

- creating rigid bodies and collision shapes
- setting up dynamic and static physics nodes
- synchronizing scene and physics systems
- applying impulses and forces
- understanding when physics owns a node transform
- spawning and destroying physical objects without leaking system state
- rendering or inspecting physics debug information

Definition of done:

- the agent can build a physics-backed interaction or simulation feature without corrupting transform logic or update order

### 12. Low-Level Geometry, Text, Image, and Capture Workflows

The agent must be comfortable dropping below scene-level workflows when needed.

This includes:

- low-level vertex and model construction
- geometry building and generated mesh output
- immediate-mode drawing and no-pipeline rendering paths
- engine-native text rendering for HUDs and labels
- picture loading, saving, format conversion, and pixel editing
- texture capture, readback, and image export
- optional video-to-texture workflows where supported

This area matters because many tools, debug views, and special effects do not fit cleanly into a purely scene-authored pipeline.

Definition of done:

- the agent can build a one-off rendering, overlay, export, or generated-geometry workflow without needing a full scene authoring pass

### 13. Procedural Systems and Simulation

The agent must be able to create systems that generate motion and visual behavior algorithmically.

Examples include:

- particles
- flocking or boids
- ambient motion fields
- procedural animation helpers
- custom geometry generation
- lightweight simulation systems

Required engineering skills:

- bounded simulation volumes
- update stability across frame rates
- lightweight per-entity state
- cost-aware neighbor lookup or spatial partitioning
- reuse of temporary structures where possible

Definition of done:

- the agent can implement a procedural effect that remains stable under continuous real-time execution

### 14. Audio Runtime and Data-Driven Reactivity

The agent must treat audio as a runtime system with timing constraints, not as a loose media attachment.

It should be able to handle:

- audio playback
- transport logic such as play, stop, next, repeat
- playback state tracking
- time-based synchronization
- reactive systems driven by music or sound analysis

For reactive projects, the agent should also know how to:

- preprocess audio offline
- normalize features into a compact representation
- export those features into runtime-readable data
- sample and interpolate them during playback

Definition of done:

- audio timing is reliable enough to drive gameplay, visuals, or simulation

### 15. Debug UI and Instrumentation

The agent must expose internal runtime state in a form that helps iteration.

Expected capabilities:

- ImGui overlay setup
- debug windows
- stats displays
- parameter visualizations
- toggles for dev-only systems
- text overlays and debug labels
- simple runtime diagnostics

Useful debug targets include:

- active state machines
- timing values
- current scene data
- audio transport state
- simulation parameters
- render mode toggles

It should also know when to use:

- ImGui widgets
- text overlays
- debug lines
- per-object labels
- on-screen capture or export tools

Definition of done:

- the project includes at least one debug surface that materially reduces tuning and debugging time

### 16. Tooling and Automation

The agent must be able to create the scripts that make the project reproducible.

This usually includes:

- asset build scripts
- content generation scripts
- validation scripts
- packaging scripts
- convenience wrappers for local development

The agent should be comfortable mixing:

- Lua runtime code
- Python generators or analyzers
- PowerShell or batch wrappers for local workflows

Definition of done:

- the project can be rebuilt and repackaged through scripted steps rather than manual editor rituals

### 17. Performance, Stability, and Validation

The agent must be able to keep a real-time project healthy as complexity increases.

Important skills:

- limiting per-frame allocations
- capping dangerous time steps when appropriate
- checking for missing assets or broken scene assumptions early
- keeping algorithmic costs bounded
- instrumenting hot sections with profiler markers when needed
- validating packaging outputs
- creating smoke tests or startup checks

The agent should think in terms of:

- frame-to-frame stability
- deterministic startup
- clear runtime assumptions
- measurable failure points

Definition of done:

- the project starts reliably, runs predictably, and surfaces breakage quickly

### 18. XR/VR and Immersive Runtime

This is an optional advanced skill area, but it is real HARFANG surface area and should be recognized explicitly.

The agent should understand:

- stereo eye framebuffers
- XR-specific render submission flow
- tracked controllers and haptics
- head pose and controller pose handling
- hand tracking or eye-gaze extensions where available
- how XR rendering changes camera and frame orchestration

Definition of done:

- the agent can identify when a project needs XR-specific architecture instead of trying to force a desktop-only render loop into an immersive runtime

### 19. Binding and API-Surface Literacy

An autonomous agent should not rely only on memory or tutorials. It should know how to inspect HARFANG binding definitions and infer what is actually available.

This includes:

- reading binding or generation scripts to discover exposed engine areas
- identifying overloads and argument directions such as out or in-out values
- distinguishing host-language conveniences from engine-level capabilities
- spotting advanced but optional features that are not visible in beginner tutorials
- using tutorials as examples, not as the full API boundary

Definition of done:

- when asked to build a new feature, the agent can discover the relevant HARFANG API surface before inventing unnecessary workarounds

## Agent-Specific Execution Pattern

An AI coding agent building a HARFANG project from scratch should usually work in this order:

1. Create the repository structure and a minimal run command.
2. Build a tiny HARFANG app that opens a window and renders a visible baseline.
3. Define path, asset, and generated-data conventions before content starts to spread.
4. Read the relevant bindings and tutorials for the feature area instead of guessing the API surface.
5. Add asset folder conventions and the first scene loading path.
6. Introduce camera, transform math, input, and one controllable behavior.
7. Add debug UI before the project becomes hard to inspect.
8. Add one content pipeline script for generated or imported runtime data.
9. Add higher-level systems such as animation, physics, procedural effects, or reactive audio.
10. Create validation and packaging scripts before the project is considered done.

This order matters. If the agent postpones tooling and observability too long, later work becomes slower and more fragile.

## What "Autonomous" Looks Like

An AI coding agent is reasonably autonomous on a HARFANG greenfield project when it can:

- scaffold a clean repository
- create a runnable HARFANG application shell
- define a sustainable Lua architecture
- manage local paths, mounted assets, and generated runtime data correctly
- reason about transforms, projection, and screen-space conversion
- load and use scenes and assets through a clear pipeline
- orchestrate scene systems and embedded scripts when needed
- implement at least one gameplay or presentation controller
- add one physics, procedural, or reactive system
- expose debugging tools
- script the build and package flow
- discover missing API details from bindings and engine docs
- verify the result with basic runtime checks

## Common Failure Modes

The agent should actively avoid these patterns:

- writing feature code before a runnable baseline exists
- mixing source assets, generated data, and packaged output together
- confusing local file access with asset-relative runtime access
- hardcoding scene logic without naming conventions
- guessing transform math or projection logic without validating it
- hiding too much state in globals
- ignoring scene-system ownership rules for physics or embedded scripts
- doing expensive preprocessing in the real-time loop
- shipping systems with no debug surface
- relying on manual packaging steps
- assuming tutorials cover the whole engine API
- treating audio timing as approximate when reactive systems depend on it

## Minimum Deliverables for a New HARFANG Project

If asked to create a HARFANG project from zero, the agent should aim to leave behind at least:

- a runnable application entry point
- a documented directory structure
- a documented asset and path convention
- one sample scene or render path
- one math-validated camera or interaction path
- one scripted build path
- one debug overlay or diagnostic tool
- one packaging path for distribution

That is the minimum bar for a useful starting project rather than an isolated prototype.
