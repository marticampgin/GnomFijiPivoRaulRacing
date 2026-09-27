"""Offline source-material enrichment and a glTF-compatible shared PBR atlas.

Call prepare_materials(M) after creating the source materials, then call
bake_runtime_materials(mesh_objects, source_dir) after geometry/normals are final.
The caller must export UVs. This module never exports a GLB or claims runtime QA.
"""

from array import array
import hashlib
import json
import math
from pathlib import Path

import bpy

from hero_uv import repair_uv_overlaps


VERSION = "hero-materials-v2"
UV_NAME = "HeroAtlasUV"
RUNTIME_MATERIAL = "HeroRuntimePBR"
_PREFIX = "HeroArt_"


def _node(material, node_type, label):
    node = material.node_tree.nodes.new(node_type)
    node.name = _PREFIX + label
    node.label = label
    return node


def _principled(material):
    nodes = [node for node in material.node_tree.nodes if node.type == 'BSDF_PRINCIPLED']
    if len(nodes) != 1:
        raise ValueError(f"{material.name}: exactly one authored Principled shader is required")
    return nodes[0]


def _ramp(material, signal, low, high, label, positions=(0.20, 0.80)):
    node = _node(material, 'ShaderNodeValToRGB', label)
    node.color_ramp.interpolation = 'EASE'
    for element, position, value in zip(node.color_ramp.elements, positions, (low, high)):
        element.position = position
        element.color = (*value, 1.0) if isinstance(value, tuple) else (value, value, value, 1.0)
    material.node_tree.links.new(signal, node.inputs['Fac'])
    return node.outputs['Color']


def _math(material, operation, first, second, label):
    node = _node(material, 'ShaderNodeMath', label)
    node.operation = operation
    for socket, value in zip(node.inputs[:2], (first, second)):
        if isinstance(value, (float, int)):
            socket.default_value = value
        else:
            material.node_tree.links.new(value, socket)
    return node.outputs[0]


def _noise(material, coordinates, scale, detail, label):
    node = _node(material, 'ShaderNodeTexNoise', label)
    node.noise_dimensions = '3D'
    node.inputs['Scale'].default_value = scale
    node.inputs['Detail'].default_value = detail
    node.inputs['Roughness'].default_value = 0.65
    material.node_tree.links.new(coordinates, node.inputs['Vector'])
    return node.outputs['Fac']


def _family(name):
    if name == 'TealEnamel':
        return 'enamel'
    if name in ('Brass', 'BrassLight'):
        return 'brass'
    if name == 'DarkSteel':
        return 'steel'
    if name in ('BlueCloth', 'BlueDark', 'RedCloth', 'RedDark'):
        return 'cloth'
    if name in ('Leather', 'LeatherLight'):
        return 'leather'
    if name in ('Rubber', 'Tread'):
        return 'rubber'
    if name in ('Hair', 'HairShadow'):
        return 'hair'
    if name.startswith('Skin'):
        return 'skin'
    return 'polished-detail'


def prepare_materials(materials_dict):
    """Enrich the authored nodes; source colors and emission remain authoritative.

    Detail is deliberately confined to color/roughness, so every authored effect
    is transferred to the runtime atlases without an unbaked procedural normal.
    """
    if not materials_dict:
        raise ValueError('No source materials supplied')
    result = {}
    settings = {
        'enamel': (48.0, 0.95, 1.025, 0.06),
        'brass': (75.0, 0.88, 1.025, 0.09),
        'steel': (55.0, 0.93, 1.02, 0.08),
        'cloth': (38.0, 0.93, 1.025, 0.07),
        'leather': (65.0, 0.87, 1.025, 0.10),
        'rubber': (90.0, 0.94, 1.02, 0.05),
        'hair': (16.0, 0.97, 1.015, 0.025),
        'skin': (12.0, 0.985, 1.01, 0.02),
        'polished-detail': (12.0, 1.0, 1.0, 0.0),
    }
    for name, material in sorted(materials_dict.items()):
        if material is None or not material.use_nodes:
            raise ValueError(f'{name}: node-based source material required')
        if material.get('hero_material_version') == VERSION:
            result[name] = json.loads(material['hero_material_recipe'])
            continue
        shader = _principled(material)
        family = _family(name)
        base_color = tuple(shader.inputs['Base Color'].default_value)
        base_roughness = float(shader.inputs['Roughness'].default_value)
        base_metallic = float(shader.inputs['Metallic'].default_value)
        scale, dark, light, roughness_range = settings[family]
        recipe = {
            'family': family,
            'baseColorLinear': list(base_color),
            'baseRoughness': base_roughness,
            'baseMetallic': base_metallic,
            'emissionColorLinear': list(shader.inputs['Emission Color'].default_value),
            'emissionStrength': float(shader.inputs['Emission Strength'].default_value),
            'detail': 'mild source-authored object-space grain; baked color and roughness',
        }
        material.use_fake_user = True
        if family != 'polished-detail':
            coordinates = _node(material, 'ShaderNodeTexCoord', 'Object coordinates').outputs['Object']
            grain = _noise(material, coordinates, scale, 2.0, 'Material grain')
            if family == 'cloth':
                weave = []
                for direction in ('X', 'Z'):
                    wave = _node(material, 'ShaderNodeTexWave', 'Woven thread ' + direction)
                    wave.wave_type = 'BANDS'
                    wave.bands_direction = direction
                    wave.wave_profile = 'SIN'
                    wave.inputs['Scale'].default_value = 48.0
                    wave.inputs['Distortion'].default_value = 0.12
                    material.node_tree.links.new(coordinates, wave.inputs['Vector'])
                    weave.append(wave.outputs['Fac'])
                cross_threads = _math(material, 'MULTIPLY', weave[0], weave[1], 'Thread crossings')
                grain = _math(material, 'ADD', _math(material, 'MULTIPLY', grain, 0.65, 'Cloth grain weight'), _math(material, 'MULTIPLY', cross_threads, 0.35, 'Thread weight'), 'Cloth grain and weave')
            tint = _ramp(material, grain, dark, light, 'Gentle color variation')
            color = _node(material, 'ShaderNodeMixRGB', 'Preserve identity tint')
            color.blend_type = 'MULTIPLY'
            color.inputs[0].default_value = 1.0
            color.inputs[1].default_value = base_color
            material.node_tree.links.new(tint, color.inputs[2])
            color_signal = color.outputs[0]
            roughness = _ramp(material, grain, max(0.04, base_roughness - roughness_range), min(0.98, base_roughness + roughness_range * 0.65), 'Surface roughness grain')
            if family in ('enamel', 'brass'):
                geometry = _node(material, 'ShaderNodeNewGeometry', 'Curvature-aware wear')
                edges = _node(material, 'ShaderNodeMapRange', 'Restrained exposed edges')
                edges.clamp = True
                edges.inputs['From Min'].default_value = 0.48
                edges.inputs['From Max'].default_value = 0.62
                material.node_tree.links.new(geometry.outputs['Pointiness'], edges.inputs['Value'])
                flecks = _ramp(material, grain, 0.0, 1.0, 'Sparse wear flecks', (0.65, 0.82))
                mask = _math(material, 'MULTIPLY', edges.outputs['Result'], flecks, 'Wear limited to edges')
                mask = _math(material, 'MULTIPLY', mask, 0.18 if family == 'enamel' else 0.24, 'Mild wear strength')
                wear = _node(material, 'ShaderNodeMixRGB', 'Undercoat or brass patina')
                material.node_tree.links.new(mask, wear.inputs[0])
                material.node_tree.links.new(color_signal, wear.inputs[1])
                wear.inputs[2].default_value = (0.105, 0.078, 0.035, 1.0) if family == 'enamel' else (0.055, 0.068, 0.040, 1.0)
                color_signal = wear.outputs[0]
            material.node_tree.links.new(color_signal, shader.inputs['Base Color'])
            material.node_tree.links.new(roughness, shader.inputs['Roughness'])
        material['hero_material_version'] = VERSION
        material['hero_material_recipe'] = json.dumps(recipe, sort_keys=True)
        result[name] = recipe
    return result


def _geometry_digest(objects):
    digest = hashlib.sha256()
    for obj in sorted(objects, key=lambda item: item.name):
        digest.update(obj.name.encode('utf-8'))
        digest.update((obj.parent.name if obj.parent else '').encode('utf-8'))
        for matrix in (obj.matrix_basis, obj.matrix_parent_inverse, obj.matrix_world):
            digest.update(array('d', [value for row in matrix for value in row]).tobytes())
        coordinates = array('f', [0.0]) * (len(obj.data.vertices) * 3)
        obj.data.vertices.foreach_get('co', coordinates)
        digest.update(coordinates.tobytes())
        vertices = array('i', [0]) * len(obj.data.loops)
        obj.data.loops.foreach_get('vertex_index', vertices)
        digest.update(vertices.tobytes())
        digest.update(json.dumps([(polygon.loop_start, polygon.loop_total, polygon.use_smooth) for polygon in obj.data.polygons]).encode('ascii'))
    return digest.hexdigest()


def _unwrap(objects, atlas_size):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
        # Primitive helpers may carry unrelated auto UVMaps. Export one unambiguous atlas.
        for layer in list(obj.data.uv_layers):
            if layer.name != UV_NAME:
                obj.data.uv_layers.remove(layer)
        if not obj.data.uv_layers.get(UV_NAME):
            obj.data.uv_layers.new(name=UV_NAME)
        obj.data.uv_layers.active = obj.data.uv_layers[UV_NAME]
        obj.data.uv_layers[UV_NAME].active_render = True
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.mode_set(mode='EDIT')
    try:
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.0, area_weight=0.1, correct_aspect=True, scale_to_bounds=False)
        bpy.ops.uv.select_all(action='SELECT')
        bpy.ops.uv.average_islands_scale()
        bpy.ops.uv.pack_islands(rotate=True, scale=True, margin_method='FRACTION', margin=8.0 / atlas_size, shape_method='AABB')
    finally:
        bpy.ops.object.mode_set(mode='OBJECT')
    overlap_audit = repair_uv_overlaps(objects, atlas_size)
    result = {}
    for obj in objects:
        layer = obj.data.uv_layers.get(UV_NAME)
        if layer is None or len(layer.data) != len(obj.data.loops):
            raise AssertionError(f'{obj.name}: UV layer does not cover all mesh corners')
        uv_values = array('f', [0.0]) * (len(layer.data) * 2)
        layer.data.foreach_get('uv', uv_values)
        if not uv_values or not all(math.isfinite(value) and -0.0001 <= value <= 1.0001 for value in uv_values):
            raise AssertionError(f'{obj.name}: empty, nonfinite or out-of-atlas UVs')
        obj.data.calc_loop_triangles()
        uv_area = 0.0
        for triangle in obj.data.loop_triangles:
            a, b, c = [layer.data[index].uv for index in triangle.loops]
            uv_area += abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) * 0.5
        if uv_area <= 1e-8:
            raise AssertionError(f'{obj.name}: degenerate UV projection')
        result[obj.name] = {'corners': len(layer.data), 'triangleUvArea': uv_area, 'sha256': hashlib.sha256(uv_values.tobytes()).hexdigest()}
    return result, overlap_audit


def _input_signal(material, socket, label):
    if socket.is_linked:
        return socket.links[0].from_socket
    if socket.type == 'RGBA':
        node = _node(material, 'ShaderNodeRGB', label)
        node.outputs[0].default_value = tuple(socket.default_value)
    else:
        node = _node(material, 'ShaderNodeValue', label)
        node.outputs[0].default_value = float(socket.default_value)
    return node.outputs[0]


def _bake_signal(material, channel):
    shader = _principled(material)
    if channel == 'albedo':
        return _input_signal(material, shader.inputs['Base Color'], 'Bake base color')
    if channel == 'orm':
        node = _node(material, 'ShaderNodeCombineColor', 'Bake ORM channels')
        node.mode = 'RGB'
        node.inputs['Red'].default_value = 1.0
        material.node_tree.links.new(_input_signal(material, shader.inputs['Roughness'], 'Bake roughness'), node.inputs['Green'])
        material.node_tree.links.new(_input_signal(material, shader.inputs['Metallic'], 'Bake metallic'), node.inputs['Blue'])
        return node.outputs['Color']
    node = _node(material, 'ShaderNodeMixRGB', 'Bake emission color and strength')
    node.blend_type = 'MULTIPLY'
    node.inputs[0].default_value = 1.0
    material.node_tree.links.new(_input_signal(material, shader.inputs['Emission Color'], 'Bake emission color'), node.inputs[1])
    material.node_tree.links.new(_input_signal(material, shader.inputs['Emission Strength'], 'Bake emission strength'), node.inputs[2])
    return node.outputs[0]


def _validate_image(image, objects, channel):
    pixels = array('f', [0.0]) * len(image.pixels)
    image.pixels.foreach_get(pixels)
    if not image.has_data or not pixels or not all(math.isfinite(value) for value in pixels):
        raise AssertionError(f'{channel}: missing or nonfinite baked pixels')
    sample_step = max(1, (len(pixels) // 4) // 65536)
    rgb_samples = [(pixels[index], pixels[index + 1], pixels[index + 2]) for index in range(0, len(pixels), sample_step * 4)]
    nonblack = sum(max(sample) > 0.00001 for sample in rgb_samples)
    if nonblack < 8:
        raise AssertionError(f'{channel}: bake produced an empty texture')
    coverage = {}
    if channel == 'albedo':
        width, height = image.size
        for obj in objects:
            layer = obj.data.uv_layers[UV_NAME]
            hits = 0
            # A face-center sample catches accidental per-object clearing of the shared image.
            for polygon in sorted(obj.data.polygons, key=lambda face: face.area, reverse=True)[:32]:
                corners = [layer.data[index].uv for index in polygon.loop_indices]
                u = sum(corner.x for corner in corners) / len(corners)
                v = sum(corner.y for corner in corners) / len(corners)
                x, y = min(width - 1, max(0, int(u * width))), min(height - 1, max(0, int(v * height)))
                offset = (y * width + x) * 4
                hits += max(pixels[offset:offset + 3]) > 0.00001
            if not hits:
                raise AssertionError(f'{obj.name}: no albedo in its atlas region')
            coverage[obj.name] = hits
    return {'sampledPixels': len(rgb_samples), 'nonblackSamples': nonblack, 'rgbMin': min(min(sample) for sample in rgb_samples), 'rgbMax': max(max(sample) for sample in rgb_samples), 'meshRegionHits': coverage}


def _bake_channel(objects, materials, channel, atlas_size, directory):
    image = bpy.data.images.new('Hero_' + channel, width=atlas_size, height=atlas_size, alpha=False, float_buffer=False)
    image.colorspace_settings.name = 'Non-Color' if channel == 'orm' else 'sRGB'
    image.generated_color = (0.0, 0.0, 0.0, 1.0)
    outputs = []
    temporary = []
    try:
        for material in materials:
            tree = material.node_tree
            output = next((node for node in tree.nodes if node.type == 'OUTPUT_MATERIAL' and node.is_active_output), None)
            if output is None:
                raise ValueError(f'{material.name}: active material output missing')
            outputs.append((material, output, output.inputs['Surface'].links[0].from_socket if output.inputs['Surface'].is_linked else None, tree.nodes.active))
            before = set(tree.nodes)
            signal = _bake_signal(material, channel)
            emission = _node(material, 'ShaderNodeEmission', 'Temporary bake emission')
            tree.links.new(signal, emission.inputs['Color'])
            emission.inputs['Strength'].default_value = 1.0
            tree.links.new(emission.outputs[0], output.inputs['Surface'])
            target = _node(material, 'ShaderNodeTexImage', 'Temporary bake target')
            target.image = image
            tree.nodes.active = target
            temporary.append((material, [node for node in tree.nodes if node not in before]))
        bpy.ops.object.select_all(action='DESELECT')
        for index, obj in enumerate(objects):
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            print(f'HERO_MATERIAL_BAKE {channel} {index + 1}/{len(objects)} {obj.name}', flush=True)
            status = bpy.ops.object.bake(type='EMIT', use_clear=False, use_selected_to_active=False, margin=4, uv_layer=UV_NAME)
            if 'FINISHED' not in status:
                raise RuntimeError(f'{obj.name}: {channel} bake did not finish')
            obj.select_set(False)
        stats = _validate_image(image, objects, channel)
        path = directory / f'hero-{channel}.png'
        image.filepath_raw = str(path)
        image.file_format = 'PNG'
        image.save()
        if not path.is_file() or path.stat().st_size < 1024:
            raise AssertionError(f'{channel}: nonempty PNG was not saved')
        image.pack()
        image.filepath_raw = '//textures/' + path.name
        metadata = {'path': 'textures/' + path.name, 'pathRelativeTo': 'source_dir', 'width': atlas_size, 'height': atlas_size, 'colorSpace': image.colorspace_settings.name, 'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'pixelChecks': stats}
        return image, metadata
    finally:
        for material, output, source, active in outputs:
            for link in list(output.inputs['Surface'].links):
                material.node_tree.links.remove(link)
            if source is not None:
                material.node_tree.links.new(source, output.inputs['Surface'])
            material.node_tree.nodes.active = active
        for material, nodes in temporary:
            for node in nodes:
                material.node_tree.nodes.remove(node)


def _runtime_material(images):
    material = bpy.data.materials.new(RUNTIME_MATERIAL)
    material.use_nodes = True
    shader = _principled(material)
    tree = material.node_tree
    coordinates = tree.nodes.new('ShaderNodeUVMap')
    coordinates.uv_map = UV_NAME
    textures = {}
    for channel, image in images.items():
        texture = tree.nodes.new('ShaderNodeTexImage')
        texture.name = 'Hero baked ' + channel
        texture.image = image
        texture.interpolation = 'Linear'
        texture.extension = 'EXTEND'
        tree.links.new(coordinates.outputs['UV'], texture.inputs['Vector'])
        textures[channel] = texture
    tree.links.new(textures['albedo'].outputs['Color'], shader.inputs['Base Color'])
    channels = tree.nodes.new('ShaderNodeSeparateColor')
    channels.mode = 'RGB'
    tree.links.new(textures['orm'].outputs['Color'], channels.inputs['Color'])
    tree.links.new(channels.outputs['Green'], shader.inputs['Roughness'])
    tree.links.new(channels.outputs['Blue'], shader.inputs['Metallic'])
    tree.links.new(textures['emission'].outputs['Color'], shader.inputs['Emission Color'])
    shader.inputs['Emission Strength'].default_value = 1.0
    material['hero_material_version'] = VERSION
    material['hero_pbr_channels'] = 'albedo sRGB; ORM non-color (R=1,G=roughness,B=metallic); emission sRGB'
    return material


def bake_runtime_materials(mesh_objects, source_dir, atlas_size=2048):
    """Pack one UV space, bake explicit PNGs, and bind a shared runtime material.

    Vertex positions, mesh topology, smoothing, object transforms and parenting
    are asserted unchanged. Original material slots/face assignments remain
    recoverable from custom properties and fake-user source material datablocks.
    Returned metadata is evidence of Blender baking only, not glTF/browser QA.
    """
    if atlas_size not in (1024, 2048):
        raise ValueError('Choose a bounded 1024 or 2048 atlas')
    objects = sorted(mesh_objects, key=lambda obj: obj.name)
    if not objects or any(obj.type != 'MESH' or not obj.data.polygons for obj in objects):
        raise ValueError('Nonempty mesh objects are required')
    if len({obj.data.as_pointer() for obj in objects}) != len(objects):
        raise ValueError('Meshes must not share writable mesh datablocks')
    if any(material.name.startswith(RUNTIME_MATERIAL) for obj in objects for material in obj.data.materials):
        raise ValueError('Bake authored source materials, not an already consolidated runtime atlas')
    if bpy.context.mode != 'OBJECT':
        raise ValueError('Run material baking in Object mode')
    directory = Path(source_dir).resolve() / 'textures'
    directory.mkdir(parents=True, exist_ok=True)
    source_materials = {material for obj in objects for material in obj.data.materials}
    if any(material is None or material.get('hero_material_version') != VERSION for material in source_materials):
        raise ValueError('Call prepare_materials with all source materials before baking')
    materials = sorted(source_materials, key=lambda mat: mat.name)
    before = _geometry_digest(objects)
    scene = bpy.context.scene
    settings = {'engine': scene.render.engine, 'device': scene.cycles.device, 'samples': scene.cycles.samples, 'seed': scene.cycles.seed, 'margin': scene.render.bake.margin, 'use_clear': scene.render.bake.use_clear, 'use_selected_to_active': scene.render.bake.use_selected_to_active}
    selection = list(bpy.context.selected_objects)
    active = bpy.context.view_layer.objects.active
    images, textures = {}, {}
    try:
        uv, overlap_audit = _unwrap(objects, atlas_size)
        scene.render.engine = 'CYCLES'
        scene.cycles.device = 'CPU'
        scene.cycles.samples = 1
        scene.cycles.seed = 0
        scene.render.bake.margin = 4
        scene.render.bake.use_clear = False
        scene.render.bake.use_selected_to_active = False
        for channel in ('albedo', 'orm', 'emission'):
            images[channel], textures[channel] = _bake_channel(objects, materials, channel, atlas_size, directory)
        runtime = _runtime_material(images)
        for obj in objects:
            obj.data['hero_source_material_names'] = json.dumps([material.name for material in obj.data.materials])
            obj.data['hero_source_material_indices'] = [polygon.material_index for polygon in obj.data.polygons]
            obj.data.materials.clear()
            obj.data.materials.append(runtime)
            for polygon in obj.data.polygons:
                polygon.material_index = 0
        after = _geometry_digest(objects)
        if before != after:
            raise AssertionError('Material pass changed geometry, smoothing, parenting or transforms')
        return {
            'version': VERSION,
            'blenderVersion': bpy.app.version_string,
            'source': 'authored local Blender nodes, no external textures or third-party assets',
            'atlasSize': atlas_size,
            'uvLayer': UV_NAME,
            'uv': uv,
            'uvOverlapAudit': overlap_audit,
            'textures': textures,
            'runtimeMaterial': runtime.name,
            'sourceMaterials': {material.name: json.loads(material['hero_material_recipe']) for material in materials},
            'meshCount': len(objects),
            'runtimeMaterialSurfaces': len(objects),
            'geometryAndPivotSha256Before': before,
            'geometryAndPivotSha256After': after,
            'geometryAndPivotsPreserved': True,
            'bake': {'engine': 'Cycles CPU', 'type': 'EMIT channel transfer', 'samples': 1, 'seed': 0, 'marginPixels': 4, 'islandMarginPixels': 8, 'ambientOcclusion': 'constant one, no lighting baked into albedo', 'tangentNormal': None},
            'sourceMaterialRestore': 'Assign material datablocks named in mesh hero_source_material_names; restore per-face indices from hero_source_material_indices',
            'requiredExportOptions': {'export_texcoords': True, 'export_materials': 'EXPORT', 'export_format': 'GLB'},
            'runtimeVerification': 'pending real Godot import and browser inspection; no final task 5.3 acceptance asserted',
        }
    finally:
        scene.render.engine = settings['engine']
        scene.cycles.device = settings['device']
        scene.cycles.samples = settings['samples']
        scene.cycles.seed = settings['seed']
        scene.render.bake.margin = settings['margin']
        scene.render.bake.use_clear = settings['use_clear']
        scene.render.bake.use_selected_to_active = settings['use_selected_to_active']
        bpy.ops.object.select_all(action='DESELECT')
        for obj in selection:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = active
