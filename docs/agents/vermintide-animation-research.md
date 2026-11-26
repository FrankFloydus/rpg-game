# Vermintide 2 animation research

Start with a named weapon and a reproducible action, such as a stationary heavy release with no confirmed hit. Record the game build, equipped item and skin, selected action, input sequence, and any known attack-speed modifiers. If using footage, record which times are visibly observed and which are inferred. Follow the [weapon motion reference workflow](weapon-motion-reference.md) once you have identified and sampled the clip.

## Pick the tool for the question

| Question | Evidence to use |
| --- | --- |
| Which weapon template, input branch, chain window, hit frame, or camera script applies? | Unpack the relevant installed resource and read its LuaJIT bytecode with LJD. Follow the item, action selector, action implementation, and dispatched event. |
| Which clip, playback rate, transition, layer, recovery, or bone mask does that event select? | Decode the compiled `.state_machine`. Check reachable state IDs, conditions, resource IDs, rate expressions, and the bone names assigned to the mask. |
| How do the weapon, arm joints, and camera move? | Sample the verified `.animation` on its canonical `.unit` with the Viewer. Compare sampled transforms with the right live capture and provenance. |
| How does an engine-native function implement a remaining behavior? | Inspect the local executable or relevant DLL statically with Ghidra. Cross-check the function against its registration, callers, and the relevant resource or capture. |

The existing hammer findings below come from the installed Lua, compiled controller, Viewer samples, and footage. The Ghidra route is for separate native questions such as how a controller evaluates a mask or combines camera transforms after a Lua engine call.

## Recover the installed Lua action chain

1. Read the installed build ID from Steam's `steamapps/appmanifest_552500.acf` and locate the bundle for the relevant logical package. For the recorded Steam build `25901688`, `resource_packages/game_scripts` is `bundle/4781bad4b7d3a395`, with SHA-256 `636b1153ca5399d38f5489874e92fbc4341152df777485724e0d5b79504524A4`. Re-resolve the bundle and record any sibling patch on another build. Keep the unpacker's normal patch handling enabled. The `list` command can confirm that the intended resource is present before extraction. If the package lacks the needed module, check its DLC or feature package.
2. Extract only the files needed into a fresh directory outside the repo. The local VT2 Bundle Unpacker `0.5.1`, shipped with the Viewer and the Bitsquid Blender Tools `0.8.3` parser package, reads the game installation's shared compression dictionary. Its resource-name dictionary supplies logical names for known hashes. Preserve the extracted resource bytes separately from the decompiled output.
3. Check the resource's bytecode header before removing any wrapper. The recorded hammer script has a 12-byte resource header followed by `1B 4C 4A 02`, which is LuaJIT revision 2. The local checkout of `Aussiemon/ljd` at commit `2ed0381b2e563531b0fe8de0a574cea8e6a04478` selects revision 2 from the file header. Run it in its default strict mode with the Viewer Python environment, currently CPython `3.13.11`. Treat assertion failures, decoded warnings, unresolved constants, or guessed control flow as incomplete evidence and inspect the relevant bytecode or corroborating callers.
4. Follow the active item through weapon template and action selection. Inspect the ordered allowed-chain rows and input buffering, then the action implementation that writes the speed and sends the animation event. Interpret damage windows with the action's time scale and direction or hit-stop overrides. Save source build, resource names, raw and decompiled hashes, exact line ranges, and how any wall-clock time was derived.

This PowerShell example uses the workstation's local installation and the retained LJD checkout. Substitute the paths or resource names for another machine or build. The expected SHA-256 for the strict decompiled hammer script on this build is `097E44C3CEA5272EE1862E25AA993564F90019A886E05788F9D15384C9496D2F`.

```powershell
$game = 'C:/Program Files (x86)/Steam/steamapps/common/Warhammer Vermintide 2'
$unpack = 'D:/TOOLS/Vermintide2/package-0.8.3/unpacking'
$viewer = 'C:/Users/Drako/Desktop/_CRIMSON_CARNAGE_DEV/VermintideViewer'
$ljd = Join-Path $env:TEMP 'hearth-vt2-lua-da4fcd87c84d4ed2a4dd84fb46fe7503/ljd-tool/main.py'
$out = Join-Path $env:TEMP ('vt2-hammer-research-' + [guid]::NewGuid().ToString('N'))
$bundle = Join-Path $game 'bundle/4781bad4b7d3a395'
$entry = 'scripts/settings/equipment/weapon_templates/2h_hammers.lua'
$expected = '636B1153CA5399D38F5489874E92FBC4341152DF777485724E0D5B79504524A4'
if ((Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash -ne $expected) {
    throw 'Bundle differs from the documented build. Resolve its package and header again.'
}

New-Item -ItemType Directory -Path $out | Out-Null
& "$unpack/unpacker.exe" --dict "$unpack/dictionary.csv" list $bundle | Select-String -SimpleMatch $entry
& "$unpack/unpacker.exe" --dict "$unpack/dictionary.csv" extract --include $entry $bundle $out
if ($LASTEXITCODE -ne 0) { throw 'Bundle extraction failed.' }

$raw = Join-Path $out $entry
$bytes = [IO.File]::ReadAllBytes($raw)
if ($bytes.Length -lt 16 -or [BitConverter]::ToString($bytes, 12, 4) -ne '1B-4C-4A-02') {
    throw 'Unexpected LuaJIT header.'
}
$bytecode = Join-Path $out '2h_hammers.ljbc'
$source = Join-Path $out '2h_hammers.strict.lua'
[IO.File]::WriteAllBytes($bytecode, $bytes[12..($bytes.Length - 1)])
& "$viewer/.venv/Scripts/python.exe" $ljd --file $bytecode --output $source
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw 'Strict LJD decompilation failed.'
}
Get-FileHash -LiteralPath $raw, $bytecode, $source -Algorithm SHA256
rg -n 'allowed_chain_actions|anim_event|anim_time_scale|damage_window' $source
```

For the hammer, useful follow-up resources are `scripts/helpers/action_utils.lua`, the player input extension and state helper, `weapon_unit_extension.lua`, and `action_melee_start.lua` and `action_sweep.lua`. For a camera question, follow the first-person system and camera extension through the camera follow state, carrier, and manager. Separate a clip's animated camera from input look, recoil, shake, and any conditional contact branch.

Resolve an unmapped resource with the Viewer's `vt2.upstream.IDString64.from_str(path).ID`. It uses MurmurHash64A with seed zero and the exact UTF-8 logical path without the extension. Resource types are separate from the 64-bit path hash. Controller event IDs use the upper 32 bits. If a name is still uncertain, keep its typed numeric ID and trace the emitting action or referring resource.

## Decode the controller and sample the rig

1. Load the relevant canonical first-person rig and verified controller from the prepared Viewer cache. For the shared hammer rig, the logical controller path is `units/beings/player/first_person_base/state_machines/melee/2h_hammer`. The audited `.state_machine` is `CD700C4CFDAC1556.state_machine` with SHA-256 `8ea6d78b9bb5836b87b3c5a67412f1434da7e1171e5dcb3a1be4e0c14e2f9625`. Use a decoder that resolves transition events, masks, and playback expressions, such as the retained `evidence/controller/inspect_controller.py` and `report.json` in the local remaining-attacks bundle.
2. Record the exact event and destination state, source clip resource ID, blend duration and sync mode, layer and bone weights, rate expression, and recovery and contact branches. Keep authored clip seconds, gameplay action units, and observed elapsed seconds explicit. A held charge can be interrupted before the end of its raw source clip. A transition can advance the new clip during the blend. [Stingray clip state properties](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/stingray_help/animation/animation_controllers/clip_state_properties.html) and [Stingray transitions](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/stingray_help/animation/animation_controllers/transitions.html) describe those serialized concepts.
3. Sample the isolated resource on `units/beings/player/first_person_base/chr_first_person_base.unit` with the [project exporter](../../tools/export_fp_motion_reference.py). Verify resource ID and hash, sample count, exact endpoint, and available tracks. `camera_node` is scene node `175` on this rig. Use the camera track under that name. The rig has no verified separate head track. The standard socket export records the weapon attachments. Inspect `j_righthand` and `j_lefthand` for the actual wrists and `j_rightforearm` and `j_leftforearm` for the elbows, using named scene-node lookup and `evaluate_pose()` at the same times.
4. Compare idle, chamber, crossing, contact, and recovery against a capture of the equipped hammer. Use a known or recorded FOV and stationary world landmarks when checking camera direction. Qualify unknown timing, player look, live speed buffs, and hit reactions. A transform report describes the sampled resource and a static mask describes weighting. The player's final view depends on live state and composition.

### Worked example on the audited hammer build

| Action evidence | Incoming event | Layer 2 state | Clip and resource ID |
| --- | --- | ---: | --- |
| Normal left-heavy load | `attack_swing_charge` | 8 | `heavy_swing_left_charge`, `5C25A3794ACA1D84` |
| Left-heavy release | `attack_swing_heavy` | 7 | `heavy_swing_left`, `CCBC471EDB146AEE` |
| Ordinary right-heavy follow-up load | `attack_swing_charge_right` | 33 | `heavy_swing_right_charge_pose`, `596E0A846FECCC83` |
| Full right-charge asset route | `attack_swing_charge_hold` | 14 | `heavy_swing_right_charge`, `A03F0C9198F4326E` |
| Right-heavy release | `attack_swing_heavy_right` | 16 | `heavy_swing_right`, `02FCFB8B6C55E74D` |
| First ordinary tap | `attack_swing_down_left` | 12 | `swing_left_down`, `CC4A8DAA6933C2BD` |
| Second ordinary tap | `attack_swing_down_right` | 17 | `swing_right_down`, `D4E21763FE6D7D55` |
| Third ordinary tap | `attack_swing_left` | 2 | `swing_left`, `0E70FF1F341D1BB0` |
| Literal right swing route in the controller | `attack_swing_right` | 1 | `swing_right`, `C14694876225AAEF` |

The ordinary template audit found action branches for the three listed taps. The literal right event requires separate runtime provenance before assigning it an ordinary input branch or damage window. Hearth Below has its own four-step light sequence. See [Combat and player](combat-and-player.md) for current controls and variant selection.

The left-heavy charge begins blending over `0.3 s` and plays at the authored rate of `1.0`. The release starts at source time zero during a `0.2 s` blend and reads `attack_speed`. For an unbuffed held input, the ordered hold blocker keeps the charge active through `1.5 s`. The full charge resource is about `2.167 s`. The raw left release is `1.1 s` and its main fast hammer-head arc lasts about `0.22 s` within that clip. The sampled camera turns about `6.37°` right at release time `0.375 s`, then about `6.54°` left at `0.688 s`, relative to a shared idle baseline. Recovery mask `16` gives zero weight to camera and aim, so the outgoing attack camera blends toward the lower layer. Keep this mask separate from the raw recovery camera samples.

The installed first-person attachment map links `j_rightweaponattach` to weapon `node0`. The inspected Empire `wpn_2h_hammer_03_t1` has an identity root and its authored mesh extends toward the head along converted local `+Y`. The narrow cap that leads the left-heavy cut faces approximately local `−Z`. Those are measured features of that mesh and mount. Record the target weapon's own grip and face axes when applying this comparison to a different model.

### Chain the next action from the current pose

The installed input extension stores one press or release edge with an expiry timer. The inspected default and profile setting are `0.50 s` for ordinary input. A hold is read live. If the selector consumes a buffered press that the player has already released, resetting the buffer converts it into a release with a fresh timer. The next charge can then resolve to a light on a subsequent update. Repeated clicks can refresh or replace the slot, subject to edge debounce. Holding through the swing supplies no fresh edge for an active combo. The idle default can start a new charge from a live hold after the current action has naturally ended. See `scripts_unit_extensions_default_player_unit_player_input_extension.strict.lua` lines 281–365 and `scripts_unit_extensions_default_player_unit_states_player_character_state_helper.strict.lua` lines 747–767, 1107–1157 and 1320–1334 in the retained hammer evidence. These are source-level input rules. Exact execution on a same-frame press and release depends on the live input poll.

The ordinary hammer's first down-light opens its follow-up at `0.70` action units and enters `default_left`, which emits `attack_swing_charge_right`. The second down-light opens at `0.70` and enters `default_right`, which emits `attack_swing_charge_left`. The third light opens at `0.75` and enters the ordinary opener. At the unbuffed light rate of `0.9`, these first eligible follow-ups are about `0.778` or `0.833 s` after the prior release begins. The early direction branch on the first two attacks lasts through `1.8` action units, after which a new input takes the opener.

The handoff starts from the active swing, hit reaction, or recovery pose. The accepted press sends a charge event and the accepted release sends the next swing event, without firing `attack_finished` for the interrupted action. The ordinary directional charge-pose edges blend over `0.20 s`. Lateral and down-light swing edges blend over `0.15 s` and `0.20 s` respectively. A swing that completes on its own enters recovery state `27` with a `0.30 s` blend. That state can still accept the next move and otherwise fades to empty attack idle on `attack_finished`. The controller's blend durations and the input gates use different clocks.

See the retained strict hammer template around lines 6–174, 516–555, 676–714, and 999–1038 and controller layer 2 in `hammer-remaining-attacks-20e08090b5/evidence`. These are the ordinary installed hammer routes. Use the same handoff principle for the separately authored Hearth Below combo.

### Calculate a hit and select the response

1. **Sample the damage window.** The installed hammer actions use baked weapon poses in first-person root space, with interpolated substeps up to `1/60 s`. The active action boundaries are scaled by the attack rate, and there is one final closure sample after leaving the window. The engine runs three oriented-box sweeps for each movement interval to cover the previous shaft, rotation, and translation. It merges duplicate actors before applying once-per-unit, own-side, and custom melee view-cone rules. The cone uses authored vertical and horizontal angles independent of the rendered lens.
2. **Select physical contacts.** Ordinary down-lights prefer a dedicated aim target within `2.85 m` and defer other overlaps until that target is lost or the window ends. An aim preference still requires a sweep overlap. The heavies use the broad sweep path. Authored damage windows are left down `0.30–0.45 s`, right down `0.35–0.53 s`, left heavy `0.30–0.50 s`, and right heavy `0.35–0.50 s`. Those windows belong to the audited actions.
3. **Spend the cleave budget.** Damage and stagger have independent budgets derived from the effective cleave power and profile. For each unit the prior accumulated mass gates these outcomes, then the target's effective mass is added. The sweep tests enemy count and accumulated mass against the larger of the damage and stagger thresholds. An AI shield block uses block mass and an extra `3` to test the stop. AI shield blocks and hero guards also add that `3` to the accumulated mass. Applicable armor can stop an ordinary light. The two heavy actions set `slide_armour_hit`, so an armored target can be cleaved if its mass and the remaining budget permit it. A heavy can still stop on a high-mass target.
4. **Handle world contact.** The installed world-contact branch also tests the point against the fixed melee view. It must sit in front of aim, within 57.775° of yaw and 60° of elevation in either direction. Elevation uses horizontal distance to the point, including its lateral offset. A nondamageable surface in the inn can abort the swing. In ordinary mission geometry the same branch can present a surface effect while the swing runs. Damageable network props default to stopping when melee damage is allowed, with a `weapon_hit_through` override. Damageable level objects use their own damage path with the ordinary heavy camera event when configured. Material mapping selects sound, particles and decals. The stop decision and first-person event come from the contact and action branches.
5. **Choose first-person feedback.** On a stop, the generic selector tries an action's kill-specific reaction, then a non-head armor-category-2 reaction, then a shield reaction, then its generic hit reaction. The inspected hammer lights and heavies use `attack_hit` for the generic reaction. Both heavies also supply an ordinary, non-stopping contact shake `hit_left_shake` or `hit_right_shake`. The stopping event replaces that ordinary shake in the selector. The verified stop ends sweep processing and transitions the pose immediately.

The controller resolves `attack_hit` from each supported swing as follows.

| Source swing direction | Attack-layer reaction state | Resource | Clip duration at rate 1 |
| --- | ---: | --- | ---: |
| Left lateral or heavy | 6 | `2266E14A8B4BFFCC` | 0.967 s |
| Right lateral or heavy | 5 | `62598D94A84E61D6` | 0.967 s |
| Left down | 18 | `D04BF62B5C79AABD` | 1.600 s |
| Right down | 11 | `102772F4D353AF2A` | 1.283 s |

The `attack_hit` edges use a serialized blend time of `0.0 s`. These are full weapon, arm, and camera poses. They retain follow-up edges and otherwise blend toward idle over `0.30 s` on `attack_finished`. The ordinary heavy shake is a separate camera-only additive layer. Left is resource `34303E6EF0C56A45` and right is `AA1F421EFC3E4D4C`. Sampling the authored local deltas at 240 Hz on the canonical rig found about `4.2°` of opposing yaw at `29 ms`, a roll reversal by about `85 ms`, and a smaller yaw pulse around `120 ms`. Camera translation stayed below `0.53 mm`. The camera motion settings modify the additive mask weight. Exact in-game frames depend on the native layer evaluation, settings and accepted input timing.

The hard-stop camera tracks differ in both axes and timing. In raw 240 Hz clip samples about `33 ms` after the first frame, the lateral reactions rotate `+0.89°` and `−1.68°` in yaw for left and right respectively. Their pitch changes by less than `0.2°`. Both downcut reactions already pitch downward by about `4.1–4.3°` and roll by about `2.3–2.4°` with yaw near zero. By `125 ms` both downcuts reverse into upward pitch and about `−5°` of roll. The lateral reactions have different pitch and roll curves on each side. These are camera-local deltas against each reaction's first frame. Material sound and effects are selected separately from the controller's hard-stop camera pose.

The weapon drops as well. With the Empire hammer identity-mounted to its right socket, the raw head-centre proxy moves from 15 cm above the animated eye to 22 cm below it within about 33 ms for the left downcut. The right moves from 1 cm above to 43 cm below. With the eye held at the reaction's first frame, the head is still 30 cm and 51 cm below that eye at 33 ms. This measurement isolates an authored weapon pose change from camera shake. The inn branch also uses 65% of the normal sweep reach and one quarter of its width with no downward sweep offset. Those are source behaviors. Hearth Below uses its own cut-specific catch and geometry rules.

The retained strict `action_sweep.lua` in `hammer-remaining-attacks-20e08090b5/evidence/lua/sources` exposes the window and cast at lines 348–437 and 611–734, target and world handling at 837–1139, and the first-person event selector at 1464–1487. The same bundle's controller report identifies the reaction states. The camera audit's `controller/vt2-hammer-camera-controller.json` provides the additive states and masks. The local sampled verification is at `%TEMP%/hearth_trace_vt2_impact_profiles.json`. These references establish the visible stop and recoil structure. A separate gameplay freeze duration and material-specific camera tuning remain unverified.

Hearth Below implements the three-pass sweep, precision deferral, independent cleave gates, and location-specific stop rules in its [live contact path](combat-and-player.md#two-handed-mace-contacts). It samples its own weapon joints and enemy capsules with Godot physics. The installed source uses baked collision poses, body hit zones, and a two-update offset in its action post-update path. Hearth keeps its authored action clock, local collision shapes, and direction-specific rebound. Training offers full-reach practice and a narrower Refuge profile. Compare matching targets, surfaces, and action phases when validating the two engines.

### Hammer movement during a swing

The installed ordinary 2H hammer template schedules movement multipliers on the attacking player. Holding a charge supplies a `0.2` target, approached over `1.0 s` by the charging buff. Both heavy releases supply a `1.4` target for the first `0.20 s` of the release action. The fast movement buff eases into that target over `0.01 s`. The ordinary audited light actions schedule `0.4` at entry for `0.20 s`, `1.4` from `0.20 s` for `0.35 s`, and another `0.4` from `0.50 s` for `0.80 s`. The last two windows overlap for `0.05 s`. The scheduler adds each duration to its own start. On removal a return buff can ease the departing contribution back toward `1.0` over `0.20 s`. Multipliers can overlap on the same movement setting, and locomotion response, collision and accepted input determine actual travel.

The multiplier acts on the hero's movement settings and the walking code uses the requested movement direction. A held forward input can produce a short forward surge. The ordinary hammer's sweep applies its explicit knockback velocity to the target. The decoded first-person heavy release and charge samples shift `camera_node` relative to the rig root by at most about `0.53 mm`, so the named tracks supply visible rotation and negligible translation. The in-game recording has no movement-input telemetry. It cannot establish how much of a particular surge is due to the player's input.

Read `2h_hammers.strict.lua` around lines 15–20, 203–210, 350–357 and 495–515 in the retained hammer Lua bundle. `ActionUtils.init_action_buff_data` and `update_action_buff_data` establish the action clock and external multiplier. The installed `buff_extension.strict.lua`, `buff_templates.strict.lua`, and the reviewed movement functions in the partially recovered `buff_function_templates` confirm the multiplier and the settings it updates. The extracted files are under `%TEMP%/hearth-vt2-installed-hammer-movement-audit`.

In Hearth Below, the [player movement loop](../../player/player.gd) adapts the `1.40×` move speed target to the retimed mace clips. The shorter charge-to-impact transition opens the heavy surge from release to `Trace Start`. A light briefly braces and builds speed before `Impact`. Both fade to ordinary movement by `Trace End`, or end the boost early on a hard stop. See [player movement](combat-and-player.md#player-input-movement-and-aiming) for the runtime contract and verification.

## Use Ghidra for a native engine question

1. Start a local non-shared analysis project and record the tool version, Steam build, binary SHA-256, architecture, and image base. Import the executable or DLL that owns the suspected native behavior. The audited installation has `binaries/vermintide2.exe`. Use Ghidra's detected PE architecture and confirm it in the import summary. Start with CodeBrowser Auto-Analyze. [Ghidra's official CodeBrowser guide](https://ghidra.re/ghidra_docs/GhidraClass/Beginner/Introduction_to_Ghidra_Student_Guide.html)
2. Start with a known engine API or a string from the script or resource side of the investigation. Inspect string and import cross-references, find the script registration or native entry point, and trace the relevant arguments into the function that applies the behavior. If expected references are absent, continue through verified callers, tables, or resource identifiers and record where the connection runs out.
3. Cross-check the decompiler against the Listing and calling conventions. Verify field offsets, widths, branch conditions, and matrix order at call sites. Use labels and signatures that distinguish confirmed identifiers from inferred meanings. Save addresses as RVAs alongside the binary hash so another review can resolve the same function after rebasing. Record the assembly and pseudocode facts that support the specific verified behavior.
4. Challenge a likely explanation with a resource or sample where the behaviors differ. For example, verify both a full-weight camera state and a zero-camera recovery mask when investigating native blending. If the behavior depends on live input, native constraints, or multiple layers, identify what the static result establishes and capture the corresponding gameplay separately.

### Reuse the local native analysis

The retained project is under `%TEMP%/hearth-ranged-references-fe49fb18a34448b88f253aa5bc4627a9/vermintide-projects/vermintide.gpr`. The recorded import used Ghidra `12.0.4` and Java `21.0.8` for `binaries/vermintide2.exe`, PE language `x86:LE:64:default:windows`, SHA-256 `F2D8A65B68478437164382F891A8AC2D579ECA791E340A73E2E5D243D9822BA9`. `vermintide.log` shows a successful import and save after the 45-second analysis budget expired. `vermintide-trace2.log` shows that `TraceRangedReferences.java` found Lua bridge imports, including `luaL_loadbuffer` and `lua_pcall`, and decompiled six candidate functions. These establish an engine-to-Lua investigation route. The native animation evaluator remains unresolved. Later attack- and lens-related searches that reported zero cross-references remain leads rather than behavior evidence.

The following headless replay was verified with Ghidra `12.2` and Temurin `25.0.5.1+2`. It matched all six function addresses and reported that changes to the original project file were discarded. The log captures selected Lua calls from the decompilation. For a different program or build, import and analyze that program in its own project first.

```powershell
$native = Join-Path $env:TEMP 'hearth-ranged-references-fe49fb18a34448b88f253aa5bc4627a9'
$toolchain = 'C:/Users/Drako/Documents/Codex/2026-11-20/i-h/work/toolchain'
$ghidra = Join-Path $toolchain 'ghidra_12.2_PUBLIC'
$projects = Join-Path $native 'vermintide-projects'
$scripts = Join-Path $native 'trace_scripts'
$replayLog = Join-Path $env:TEMP 'hearth_ghidra_12_2_bridge_replay.log'
$jdk = Join-Path $toolchain 'jdk-25.0.5.1+2'
if (!(Test-Path -LiteralPath "$jdk/bin/java.exe")) { throw 'Ghidra JDK is missing.' }
$previousJavaHome = $env:JAVA_HOME
try {
    $env:JAVA_HOME = $jdk
    & "$ghidra/support/analyzeHeadless.bat" $projects vermintide -process vermintide2.exe -readOnly -noanalysis -scriptPath $scripts -postScript TraceRangedReferences.java vermintide -log $replayLog
    if ($LASTEXITCODE -ne 0) { throw 'Headless Ghidra replay failed.' }
} finally {
    $env:JAVA_HOME = $previousJavaHome
}
rg -n 'TRACE_DECOMP|REPORT: Discarding changes' $replayLog
```

Use a fresh log path for repeated runs. Keep the retained project and original logs available for comparison, and record the Ghidra and JDK versions for each new run.

## Find the retained evidence

Local motion investigations live under `D:/_GAME_ART/Vermintide2/motion_references/` on this workstation. Look for each investigation's `readback.json` for paths, observations, and evidence limits.

- `hammer-camera-tracks-23c91a58fd` contains the idle, left charge, left release, cadence, and native hammer mount evidence. Its `camera-motion-audit-20261125-c47fc1bab9` subdirectory includes `readback.json`, `camera-local-deltas240.json`, and the camera layer, mask, and video comparisons.
- `hammer-remaining-attacks-20e08090b5` contains the right heavies and four light references, the installed Lua evidence in `evidence/lua/report.json`, and the decoded controller in `evidence/controller/report.json`. Its `analysis` directory has dense joint samples and comparison tables. The retained controller script also exists at `%TEMP%/hammer-remaining-controller/inspect_controller.py`.
- `hammer-light-discrepancy-20261125-a67696535d` contains the matched light phase, actual wrist, head proxy, target trace, and game footage comparisons.

Record the title, item and variant, evidence path and hashes, tool versions, findings, and uncertainty in the local review so a later investigation can retrace the chain. Keep extracted resources, decompiled files, Ghidra databases, and capture bundles outside Git. Use the linked Hearth Below guide to author and verify the target motions on our own weapon and rig.
