"""Build a tiny GLB round-trip fixture, not a hero asset or an art-quality proof."""

import argparse
from pathlib import Path
import sys

import bpy


def material(name, color, metallic, roughness):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    destination = Path(args.out_dir).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    root = bpy.data.objects.new("ExportProbe", None)
    scene.collection.objects.link(root)
    samples = [
        ("TealSample", (0.025, 0.34, 0.30), 0.25, 0.35),
        ("BrassSample", (0.62, 0.38, 0.13), 0.9, 0.3),
        ("RubberSample", (0.025, 0.03, 0.035), 0.0, 0.9),
        ("CrystalSample", (0.02, 0.70, 0.9), 0.1, 0.15),
        ("UVSample", (1.0, 1.0, 1.0), 0.0, 0.8),
    ]
    for index, (name, color, metallic, roughness) in enumerate(samples):
        bpy.ops.mesh.primitive_cube_add(size=0.4, location=(index * 0.6, 0, 0.2))
        obj = bpy.context.object
        obj.name = name
        obj.parent = root
        surface = material(name + "Material", color, metallic, roughness)
        if name == "CrystalSample":
            shader = surface.node_tree.nodes.get("Principled BSDF")
            shader.inputs["Emission Color"].default_value = (0.02, 0.7, 0.9, 1.0)
            shader.inputs["Emission Strength"].default_value = 1.5
        if name == "UVSample":
            checker = bpy.data.images.new("PackedUVGrid", width=64, height=64)
            checker.generated_type = "COLOR_GRID"
            checker.pack()
            texture = surface.node_tree.nodes.new("ShaderNodeTexImage")
            texture.image = checker
            surface.node_tree.links.new(
                texture.outputs["Color"],
                surface.node_tree.nodes.get("Principled BSDF").inputs["Base Color"],
            )
        obj.data.materials.append(surface)

    # Blender +Y forward must become Godot -Z after the glTF Y-up conversion.
    for name, location in [
        ("ForwardAttachment", (0.0, 1.0, 0.0)),
        ("UpAttachment", (0.0, 0.0, 1.0)),
        ("RightAttachment", (1.0, 0.0, 0.0)),
    ]:
        point = bpy.data.objects.new(name, None)
        scene.collection.objects.link(point)
        point.parent = root
        point.location = location

    bpy.ops.wm.save_as_mainfile(filepath=str(destination / "export-probe.blend"))
    bpy.ops.export_scene.gltf(
        filepath=str(destination / "export-probe.glb"),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_animations=False,
        export_cameras=False,
        export_lights=False,
    )
    print("EXPORT_PROBE_READY " + str(destination / "export-probe.glb"))


main()
