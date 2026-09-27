"""Render the existing kart source for the lobby without saving the scene.

Blender --background --offline-mode --python-exit-code 1 \
    --python scripts/art/render-lobby-kart.py -- --output web/assets/lobby-kart.png
"""

import argparse
from array import array
import hashlib
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', default='art-source/hero/hero-blockout.blend')
    parser.add_argument('--output', default='web/assets/lobby-kart.png')
    parser.add_argument('--width', type=int, default=1400)
    parser.add_argument('--height', type=int, default=1000)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if not 256 <= args.width <= 2048 or not 256 <= args.height <= 2048:
        raise ValueError('Render dimensions must be between 256 and 2048 pixels')

    source = Path(args.source).resolve()
    output = Path(args.output).resolve()
    if output.suffix.lower() != '.png' or output == source:
        raise ValueError('Output must be a separate PNG file')
    source_digest = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    hero = bpy.data.objects['HeroBlockout']
    camera = bpy.data.objects['ThreeQuarterCamera']
    bpy.data.objects['StudioGround_NotExported'].hide_render = True
    scene.camera = camera
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = args.width
    scene.render.resolution_y = args.height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'
    scene.render.image_settings.compression = 70

    # Fit the entire unchanged model with a margin, preserving the authored view.
    bpy.context.view_layer.update()
    meshes = [obj for obj in hero.children_recursive if obj.type == 'MESH']
    points = [camera.matrix_world.inverted() @ (obj.matrix_world @ Vector(corner))
              for obj in meshes for corner in obj.bound_box]
    minimum = [min(point[axis] for point in points) for axis in range(2)]
    maximum = [max(point[axis] for point in points) for axis in range(2)]
    local_center = Vector(((minimum[0] + maximum[0]) / 2,
                           (minimum[1] + maximum[1]) / 2, 0))
    camera.location += camera.matrix_world.to_quaternion() @ local_center
    aspect = args.width / args.height
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = max(maximum[0] - minimum[0],
                                 (maximum[1] - minimum[1]) * aspect) / 0.88
    output.parent.mkdir(parents=True, exist_ok=True)
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)

    rendered = bpy.data.images.load(str(output), check_existing=False)
    pixels = array('f', [0.0]) * len(rendered.pixels)
    rendered.pixels.foreach_get(pixels)
    alpha = pixels[3::4]
    if not alpha or min(alpha) != 0 or max(alpha) <= 0:
        raise RuntimeError('Expected both fully transparent and visible pixels')
    edge_indices = [*range(args.width),
                    *range((args.height - 1) * args.width, args.height * args.width),
                    *range(0, args.width * args.height, args.width),
                    *range(args.width - 1, args.width * args.height, args.width)]
    if any(alpha[index] != 0 for index in edge_indices):
        raise RuntimeError('The model touches a render edge')
    if hashlib.sha256(source.read_bytes()).hexdigest() != source_digest:
        raise RuntimeError('The source scene changed during a render-only operation')
    print('LOBBY_KART_RENDER ' + json.dumps({
        'source': str(source), 'sourceSha256': source_digest,
        'output': str(output), 'width': args.width, 'height': args.height,
        'bytes': output.stat().st_size, 'meshes': len(meshes),
        'transparentPixels': sum(value == 0 for value in alpha),
        'visiblePixels': sum(value > 0 for value in alpha),
        'clearImageEdges': True,
    }))


main()
