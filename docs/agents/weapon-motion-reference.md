# Weapon motion reference workflow

Use the [batch audit](../../tools/weapon_motion_audit.gd) to compare a Viewer export with an authored Hearth Below weapon animation. The tool reads the export and samples Godot's actual animation tracks. It writes a report and leaves the editable weapon scene to the author.

Start with [Vermintide 2 animation research](vermintide-animation-research.md) when the source clip, runtime event, or camera layer still needs to be identified. Record the source build, rig, clip ID and hash, source rate, transition, and gameplay phase evidence for each requested attack. Keep a separate row for each intended Hearth Below variant so the same source calibration can be reused across a batch.

## Calibrate the weapon and view once

- Record the weapon's attachment, visual head center, shaft direction, and striking face for the source and target meshes in their own local spaces. Use the same calibration for all clips that share that mounting. The source attachment follows the weapon. Use the actual wrist chain as the hand reference wherever it was exported.
- Record how the source view was obtained. Camera-relative samples use Godot's right-handed axes and metres. The basis vectors are columns and forward is negative Z. Keep FOV and aspect ratio with visual captures. Apply any head or camera animation as a local render layer in Hearth Below.
- Keep the raw export and local batch jobs outside Git. Preserve the manifest with the motion file so the selected asset and its endpoint are traceable.

## Sample a reference from the local Viewer

Use the [reference exporter](../../tools/export_fp_motion_reference.py) with the Viewer virtual environment and a prepared extracted asset index. Pass the first-person rig path relative to the extracted root. The shared meshless rig works for the two-handed hammer set. Give each clip its verified resource ID and logical path. The exporter checks that the ID resolves to the named clip on that rig and samples the camera and available attachment sockets at the exact opening and end. It publishes a new motion-only bundle in the requested directory. Sample times describe the isolated clip, including when a runtime action would blend across it.

```powershell
$viewer = 'C:/motion-review/VermintideViewer'
$assets = 'D:/motion-review/extracted'
& "$viewer/.venv/Scripts/python.exe" tools/export_fp_motion_reference.py --viewer $viewer --assets $assets --model 'units/beings/player/first_person_base/chr_first_person_base.unit' --clip '2h_hammer/swing_left_down=CC4A8DAA6933C2BD' --clip '2h_hammer/swing_right_down=D4E21763FE6D7D55' --output 'D:/motion-review/new-downswings'
```

The exporter reads an existing local index. If the index is missing or stale, refresh it in the Viewer first. The output contains one `manifest.json` and `motion.json` per clip and a shared `motion-verification.json`. The standard motion sampler reports attachment sockets. For arm comparisons, resolve unique wrist and forearm names on the sampled rig and use the Viewer's `evaluate_pose()` to read their scene-node transforms. Express those transforms relative to the camera at the matching source time and apply the same axis conversion once.

Check the first sample, exact source endpoint, monotonic timestamps, transform finiteness, and identity of the sampled rig. The verification report checks that each model-space socket equals the model-space camera multiplied by its camera-relative transform. Use the report and companion manifest as a pair. For a visual reference, retain images of the actual weapon if its head and mount are part of the comparison. The Viewer image sequence can show an arms model and socket trails with no equipped weapon. Its chronological frame labels and exact times belong to the manifest, even when the user selects sparse frames. Trail dots mark authored source keys.

## Retarget the weapon, arms, and camera

1. Calibrate the target mount using a ready pose, chamber, contact, and finish. Compare the source weapon head center and striking face as rigid features of its mount to those of the Hearth Below mesh. Record both meshes' actual dimensions, their shaft axes, and the calibrated striking-face normal. Apply a constant mount calibration across the weapon family. Preserve per-clip changes in depth and roll, including the head moving forward while the hands retract.
2. Solve through the target scene hierarchy. If `P` maps `Pose`'s parent to the neutral camera frame, `R(t)` is the desired camera-relative weapon attachment, and `G` maps the target attachment to `Pose`, the corresponding local pose is `P.affine_inverse() * R(t) * G.affine_inverse()`. Use the target's original meshes and rig. Compare source wrists and forearm landmarks to target arm guides, with the weapon following the dominant attachment. Keep both hands seated on the target handle, preserve forearm length, and let the shoulders and elbows load into the cut. Check the support hand through interpolation and any hand repositioning. Attachment sockets can be offset substantially from the anatomy and can move differently from the actual wrists.
3. Derive camera motion from a shared camera-local neutral baseline. Remove the source root placement before computing the relative rotation and translation. Use the exported camera-relative weapon data for screen placement, and drive the [local render camera layer](../../player/effects/camera/first_person_camera_effects.gd) with a calibrated `CameraMotion` track. Preview both together so a source camera transform is applied only once. Respect source layer masks when deciding which camera motion to use during recovery. Keep the gameplay eye and aim in their existing space.
4. Preserve source seconds through phase matching. If you retime or blend a target clip, apply the same time map to the weapon, arm and camera tracks and to the gameplay markers. Use shortest-path normalized quaternion interpolation for orientation comparisons. Check interpolated positions as well as authored keys wherever the chamber approaches the near plane, the weapon changes sides, or a sleeve approaches its reach limit.

## Mark the phases and author the path

Identify the chamber, first and last contact, impact, and retraction. Use the installed action timeline or a labeled capture for gameplay events. Label measured landmarks from an isolated clip as diagnostic times. The clip name and a velocity peak alone cannot establish a gameplay event.

Build the rigid weapon path against those phases in the weapon scene. For a lateral cut with a wound-up pose, check the head's depth change through the swing as well as its side-to-side travel. Compare lead and support hand framing against actual wrist data, then solve the arms to the grips. Keep the target `Trace Start`, `Impact`, `Trace End`, and `Input Buffer` aligned to that motion. The game's timeline and playback rate determine elapsed time. Sample the camera against the authored attack phases and verify it settles at the recovery boundary.

Author the target animation in the owning weapon scene and register it in its animation library. The [two-handed mace scene](../../player/weapons/mace_2h.tscn) uses `Pose` for its rigid weapon motion, `PreviewArmRig` for the arms, and `CameraMotion` for the attack camera. The [weapon view](../../player/weapon_view.gd) selects and samples the tracks. Use track types its manual sampler reads. [AttackAnimation](../../combat/attack_animation.gd) validates the marker sequence, and the [player](../../player/player.gd) samples the strike pose and traces within the same attack timeline. Track changes must travel through the normal input and selection path to affect combat. Keep the authored charge, release, and return paths connected to the canonical close ready pose.

For a linked light, match the destination's `Combo Entry` against the previous swing's follow-through at its `Combo Exit` and `Input Buffer`. Leave enough time to finish the weapon, arm, and camera blend before `Trace Start`. Keep the standalone opening and full unchained recovery in the clip. `Terrain Start` arms solid-surface checks. Downcuts and heavies also require the head centre to enter the strike region near aim. Choose an `Impact` pose that shows the contact orientation and arms clearly, since these four rebounds use it to shape the compact catch. Check beside a pillar for a raised or wide graze and aim into the shaft for a confirmed strike. [Combat and player](combat-and-player.md#two-handed-mace-contacts)

## Run the batch

Run from the project root with the Godot console executable.

```powershell
godot --headless --path . --script res://tools/weapon_motion_audit.gd -- C:/motion-review/jobs.json C:/motion-review/report.json
```

Each job compares one reference with one target animation. Give the job a unique ID. Use `reference.manifest` when the export has a manifest, or `reference.motion` for a standalone motion file. Paths to the reference are relative to the job file unless absolute. Reference phase values use source clip seconds. The target chamber and retraction also use clip seconds, and the tool reads the other target phases from the animation's markers. Both head offsets are local to their own weapon reference, the right attachment in the source and `Pose` in the target. Use per-clip bounds backed by the intended motion and change them for a thrust or overhead strike.

```json
{
  "jobs": [
    {
      "id": "maul-light-left-close",
      "reference": {
        "manifest": "references/swing_left/manifest.json",
        "head": [0, 1.06, 0],
        "phases": {
          "chamber": 0.329,
          "trace_start": 0.30,
          "impact": 0.380,
          "trace_end": 0.45,
          "retraction": 0.575
        },
        "provenance": "Isolated clip phase measurements for the reference comparison"
      },
      "target": {
        "scene": "res://player/weapons/mace_2h.tscn",
        "animation": "light_left",
        "head": [0.002, 0.934, 0],
        "chamber": 0.1375,
        "retraction": 0.5125
      },
      "gates": {
        "target.metrics.chamber_to_impact_forward": { "min": 0.65 },
        "target.metrics.impact_to_retraction_back": { "min": 0.60 },
        "target.metrics.impact_right_wrist_depth": { "max": 0.50 }
      }
    }
  ]
}
```

Check the report for invalid transforms or sequences, phase coverage, chamber and retraction depth, shaft orientation, and target wrist placement. Standard motion exports provide attachment sockets. The source wrist comparison requires additional evidence. A batch can compare multiple clips and weapons. Omit `target` to preflight a reference before authoring. A report can mark a job for review if evidence is missing. A failed job exits with code 1, and a configuration or output error exits with code 2. Read the report's review count when gating a batch.

## Accept the rendered attack

Play each attack in Forward+ through its normal input path. Use a fixed aim and the intended field of view. Check the loaded silhouette, grip contact and sleeve shape through impact, frame exits and re-entries, and the return to ready. Enable **Show Player Weapon Traces** and confirm that the actual weapon trace leads with the intended face and follows the same cut. Verify a tap, follow-up, and interruption where the input permits them. A numeric pass catches common placement and timing errors before this test. The rendered check still owns what the player actually sees.

Equip the two-handed mace in the Training Ground and check each attack against its default close ready pose. Verify the accepted light inputs produce left → right → left down → right down → left, a held attack reaches its heavy, and an expired chain restarts at left. Check queued inputs and both trace and recovery at 1× before testing other tempos. Record the batch report and rendered findings in the local review.
