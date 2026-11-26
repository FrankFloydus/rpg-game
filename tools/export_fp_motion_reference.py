"""Publish motion-only reference bundles through the installed Viewer sampler."""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from tempfile import TemporaryDirectory


def parse_clip(value):
    label, separator, resource = value.rpartition("=")
    if (not separator or not re.fullmatch(r"[\w-]+(?:/[\w-]+)*", label)
            or not re.fullmatch(r"[0-9a-fA-F]{16}", resource)):
        raise argparse.ArgumentTypeError("Expected clip/path=16-digit-hex-resource-ID.")
    return label, resource.upper()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def sample_bundle(config, staging):
    sys.path.insert(0, str(config.viewer.resolve()))

    import numpy as np
    from vt2.animation import discover_clips, evaluate, load_clip
    from vt2.assets import AssetIndex
    from vt2.model import load_model
    from vt2.sequence import sample_times
    from vt2.sequence_pose import sequence_pose, sequence_track_info

    index = AssetIndex.load_cached(config.assets)
    if index is None:
        raise ValueError("No current asset index. Open the Viewer and refresh the extracted asset root.")
    model_path = (index.root / config.model).resolve(strict=True)
    if not model_path.is_relative_to(index.root):
        raise ValueError("The first-person rig must be inside the indexed asset root.")
    model = load_model(model_path, index, allow_rig_only=True)
    available = {Path(path).resolve() for _, path in discover_clips(model, index)}
    root_node = next(
        (node for node, name in enumerate(model.bone_names) if name.casefold() in {"root_point", "root"}),
        None,
    )
    if root_node is None:
        raise ValueError("Could not identify the model root for in-place sampling.")

    def matrix(record):
        transform = np.eye(4)
        transform[:3, :3] = np.asarray(record["basis"]).T
        transform[:3, 3] = record["origin"]
        if not np.isfinite(transform).all():
            raise ValueError("The reference contains a nonfinite transform.")
        return transform

    results = []
    for label, identifier in config.clip:
        clip_path = index.resolve(identifier, "animation")
        if clip_path is None or clip_path.resolve() not in available:
            raise ValueError(f"{label}: {identifier} is not associated with the selected first-person rig.")
        clip = load_clip(model, clip_path)
        source_label = clip.name.replace("\\", "/").removesuffix(".animation")
        if source_label != label and not source_label.endswith("/" + label):
            raise ValueError(f"{identifier}: expected {label}, found {clip.name}.")
        duration = float(clip.duration)
        times = [float(t) for t in sample_times(duration, config.fps) if t < duration]
        times.append(duration)
        if len(times) < 2 or times[0] != 0 or any(a >= b for a, b in zip(times, times[1:])):
            raise ValueError(f"{label}: expected increasing sample times with both exact endpoints.")
        opening = evaluate(model, clip, 0.0)
        root_start = (opening[root_node] @ model.global_bind[root_node])[:3, 3]
        tracks = sequence_track_info(model, clip)
        if tracks["camera"]["status"] != "available":
            raise ValueError(f"{label}: the Viewer could not resolve a camera track.")

        samples = []
        residual = 0.0
        expected_sides = None
        for t in times:
            motion = sequence_pose(model, clip, t, root_node=root_node, root_start=root_start)["motion"]
            sockets = motion["sockets"]
            relative = motion.get("camera_relative_sockets", {})
            sides = set(sockets)
            if expected_sides is None:
                expected_sides = sides
            if not sides or sides != expected_sides or sides != set(relative):
                raise ValueError(f"{label}: attachment sockets are missing or change at {t:.6f} s.")
            camera = matrix(motion["camera"])
            for side in sorted(sides):
                change = camera @ matrix(relative[side]) - matrix(sockets[side])
                residual = max(residual, float(np.abs(change).max()))
            samples.append(motion)
        # The canonical rig can return single-precision transforms.
        if residual > 1e-6:
            raise ValueError(f"{label}: model and camera-relative sockets disagree by {residual:.3g}.")

        folder = staging / label.rsplit("/", 1)[-1]
        folder.mkdir()
        motion = {
            "format": "vermintide_sequence_motion",
            "version": 1,
            "axes": "godot",
            "units": "meters",
            "time_unit": "seconds",
            "space": "model",
            "in_place": True,
            "transform_layout": {"origin": "XYZ", "basis": "three XYZ column vectors"},
            "track_nodes": tracks,
            "samples": samples,
        }
        clip_info = {
            "name": label,
            "source_label": clip.name,
            "resource_id": identifier,
            "resource": str(clip_path),
            "sha256": hashlib.sha256(clip_path.read_bytes()).hexdigest(),
            "duration": duration,
        }
        verification = {"sample_count": len(samples), "camera_socket_residual": residual}
        write_json(folder / "motion.json", motion)
        write_json(folder / "manifest.json", {
            "format": "vermintide_analytical_motion_reference",
            "version": 1,
            "purpose": "Isolated motion reference for Hearth Below authoring.",
            "capture": {
                "clip": clip_info,
                "model": {"resource": str(model_path)},
                "fps": config.fps,
                "in_place": True,
                "track_nodes": tracks,
                "method": "Viewer sequence_pose with native clip time and an exact endpoint.",
            },
            "motion": "motion.json",
            "frames": [],
            "grids": [],
            "verification": verification,
        })
        results.append(clip_info | verification | {"manifest": f"{folder.name}/manifest.json"})
    write_json(staging / "motion-verification.json", {"references": results})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--viewer", type=Path, required=True, help="Viewer source directory")
    parser.add_argument("--assets", type=Path, required=True, help="Indexed extracted asset root")
    parser.add_argument("--model", type=Path, required=True, help="First-person .unit path under the asset root")
    parser.add_argument("--clip", type=parse_clip, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True, help="New directory for the reference bundle")
    parser.add_argument("--fps", type=int, default=60)
    config = parser.parse_args()
    names = {label.rsplit("/", 1)[-1].casefold() for label, _ in config.clip}
    if config.fps <= 0 or len(names) != len(config.clip):
        parser.error("FPS must be positive and clip names must be unique.")
    if not (config.viewer / "vt2" / "sequence_pose.py").is_file():
        parser.error("The Viewer source directory must contain vt2/sequence_pose.py.")
    output = config.output.resolve()
    if output.exists() or not output.parent.is_dir():
        parser.error("Use a new output directory inside an existing parent directory.")
    try:
        with TemporaryDirectory(prefix=".motion-reference-", dir=output.parent) as temporary:
            staging = Path(temporary) / "bundle"
            staging.mkdir()
            sample_bundle(config, staging)
            if output.exists():
                raise ValueError("The output directory was created by another process.")
            staging.rename(output)
    except (ImportError, OSError, ValueError) as error:
        parser.exit(1, f"Motion export failed: {error}\n")
    print(output / "motion-verification.json")


if __name__ == "__main__":
    main()
