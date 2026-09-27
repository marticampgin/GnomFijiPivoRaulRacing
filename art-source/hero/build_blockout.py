"""Editable, review-only hero blockout. No final UV, skeletal rig or baked textures."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Quaternion, Vector

PI = math.pi
M = {}


def rgb(value):
    components = [int(value[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in components)


def make_material(name, color, metallic=0.0, roughness=0.5, emission=0.0):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*rgb(color), 1)
    material.use_nodes = True
    shader = material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*rgb(color), 1)
    shader.inputs['Metallic'].default_value = metallic
    shader.inputs['Roughness'].default_value = roughness
    if emission:
        shader.inputs['Emission Color'].default_value = (*rgb(color), 1)
        shader.inputs['Emission Strength'].default_value = emission
    M[name] = material
    return material


def empty(name, position=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = position
    if parent:
        parent_keep(obj, parent)
    return obj


def parent_keep(obj, parent):
    bpy.context.view_layer.update()
    transform = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = transform


def mesh(name, vertices, faces, material, smooth=True):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    data.materials.append(M[material])
    for polygon in data.polygons:
        polygon.use_smooth = smooth
    return obj


def loft(name, rings, material, smooth=True, close=True):
    count = len(rings[0])
    vertices = [point for ring in rings for point in ring]
    faces = []
    for row in range(len(rings) - 1):
        for index in range(count):
            following = (index + 1) % count
            faces.append((row * count + index, row * count + following, (row + 1) * count + following, (row + 1) * count + index))
    if close:
        faces.extend([tuple(reversed(range(count))), tuple((len(rings) - 1) * count + i for i in range(count))])
    return mesh(name, vertices, faces, material, smooth)


def tube(name, points, radii, material, sides=10):
    points = [Vector(p) for p in points]
    if 2 < len(points) < 8:
        radii = radii if isinstance(radii, list) else [radii] * len(points)
        smoothed, smooth_radii = [], []
        for index in range(len(points) - 1):
            p0, p1 = points[max(0, index - 1)], points[index]
            p2, p3 = points[index + 1], points[min(len(points) - 1, index + 2)]
            for step in range(5):
                t = step / 5
                smoothed.append(.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t))
                smooth_radii.append(radii[index] * (1 - t) + radii[index + 1] * t)
        points, radii = smoothed + [points[-1]], smooth_radii + [radii[-1]]
    rings = []
    for index, center in enumerate(points):
        tangent = points[min(index + 1, len(points) - 1)] - points[max(index - 1, 0)]
        tangent.normalize()
        reference = Vector((1, 0, 0)) if abs(tangent.x) < 0.8 else Vector((0, 1, 0))
        right = tangent.cross(reference).normalized()
        up = tangent.cross(right).normalized()
        radius = radii[index] if isinstance(radii, list) else radii
        rings.append([center + radius * (right * math.cos(2 * PI * step / sides) + up * math.sin(2 * PI * step / sides)) for step in range(sides)])
    return loft(name, rings, material)


def ring(name, center, right, up, radius, thickness, material, steps=40):
    c, u, v = Vector(center), Vector(right), Vector(up)
    points = [c + radius * (u * math.cos(2 * PI * i / steps) + v * math.sin(2 * PI * i / steps)) for i in range(steps + 1)]
    return tube(name, points, thickness, material, 8)


def ellipsoid(name, center, scale, material, segments=24, rings=16):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(M[material])
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def box(name, center, size, material, bevel=0.025, rotation=(0, 0, 0), bevel_segments=2):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(M[material])
    if bevel:
        mod = obj.modifiers.new('Form fillet', 'BEVEL')
        mod.width = bevel
        mod.segments = bevel_segments
        bpy.ops.object.modifier_apply(modifier=mod.name)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        mod = obj.modifiers.new('Face normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj


def cylinder(name, a, b, radius, material, vertices=32):
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=(b - a).length, location=(a + b) / 2)
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = (b - a).to_track_quat('Z', 'Y')
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(M[material])
    for polygon in obj.data.polygons:
        polygon.use_smooth = len(polygon.vertices) == 4
    return obj


def batch(parts, name, parent, origin=(0, 0, 0)):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    bpy.context.scene.cursor.location = origin
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    parent_keep(obj, parent)
    return obj


def body_loft(name, rows, material):
    rings = []
    for y, width, height, thickness in rows:
        points = []
        for i in range(32):
            angle = 2 * PI * i / 32
            x = math.copysign(abs(math.cos(angle)) ** 0.65, math.cos(angle)) * width
            z = height + math.copysign(abs(math.sin(angle)) ** 0.85, math.sin(angle)) * thickness
            points.append((x, y, z))
        rings.append(points)
    return loft(name, rings, material)


def make_body(root):
    parts = []
    parts.append(body_loft('Lower coach shell', [(-1.13, .33, .34, .065), (-1.00, .53, .35, .095), (-.6, .56, .37, .09), (.1, .54, .38, .10), (.7, .5, .38, .10), (1.18, .34, .36, .075)], 'TealEnamel'))
    parts.append(body_loft('Rounded hood', [(1.19, .27, .54, .12), (1.10, .38, .56, .16), (.90, .48, .60, .17), (.62, .51, .64, .18), (.39, .48, .69, .17), (.28, .41, .70, .09)], 'TealEnamel'))
    parts.append(body_loft('Low rear cowl', [(-1.08, .42, .60, .12), (-.94, .5, .65, .13), (-.64, .48, .65, .13), (-.43, .37, .61, .07)], 'TealEnamel'))
    parts.append(box('Chassis', (0, -.02, .29), (.94, 2.12, .18), 'DarkSteel', .07))
    for side in (-1, 1):
        x = side * .81
        for axle_y, radius in ((.78, .455), (-.78, .49)):
            rows = []
            for i in range(25):
                angle = PI * (.18 + .64 * i / 24)
                y, z = axle_y + math.cos(angle) * radius, (.42 if axle_y > 0 else .45) + math.sin(angle) * radius
                rows.append([(x - .18, y, z), (x + .18, y, z), (x + .18, y, z - .038), (x - .18, y, z - .038)])
            parts.append(loft('Rolled fender', rows, 'TealEnamel'))
            edge = [(x + side * .182, axle_y + math.cos(PI * (.18 + .64 * i / 24)) * radius, (.42 if axle_y > 0 else .45) + math.sin(PI * (.18 + .64 * i / 24)) * radius) for i in range(25)]
            parts.append(tube('Fender brass lip', edge, .012, 'Brass'))
        parts.append(tube('Cockpit tube', [(side * .42, .35, .47), (side * .47, -.2, .55), (side * .40, -.47, .90), (side * .30, -.57, 1.04)], .04, 'DarkSteel'))
        parts.append(tube('Side step', [(side * .53, .34, .37), (side * .63, .25, .39), (side * .63, -.3, .39), (side * .51, -.5, .37)], .03, 'Brass'))
        for axle_y in (.78, -.78):
            start = Vector((side * .40, axle_y - .04, .64))
            finish = Vector((side * .74, axle_y, .35))
            parts.append(cylinder('Damper', start, finish, .037, 'DarkSteel'))
            along = (finish - start).normalized()
            u = along.cross(Vector((0, 1, 0))).normalized()
            v = along.cross(u).normalized()
            spring = [start.lerp(finish, .12 + .76 * i / 64) + (u * math.cos(i / 64 * 12 * PI) + v * math.sin(i / 64 * 12 * PI)) * .055 for i in range(65)]
            parts.append(tube('Suspension spring', spring, .011, 'Brass', 6))
            parts.append(tube('Wishbone', [(side * .3, axle_y - .12, .34), (side * .76, axle_y, .34), (side * .3, axle_y + .12, .34)], .022, 'DarkSteel'))
        for y in (.45, .65, .87, 1.04):
            parts.append(ellipsoid('Hood fastener', (side * (.45 if y < 1 else .36), y, .745 if y < .9 else .68), (.013, .013, .009), 'Brass', 10, 6))
        parts.append(tube('Hood seam', [(side * .12, 1.19, .66), (side * .29, 1.0, .74), (side * .35, .72, .815), (side * .30, .37, .86)], .008, 'Brass'))
        lamp = (side * .43, 1.06, .59)
        parts.append(cylinder('Lamp brass barrel', (lamp[0], .96, lamp[2]), (lamp[0], 1.12, lamp[2]), .139, 'Brass'))
        parts.append(cylinder('Lamp ivory glass', (lamp[0], 1.123, lamp[2]), (lamp[0], 1.137, lamp[2]), .112, 'Headlamp'))
        parts.append(ring('Lamp protective ring', (lamp[0], 1.14, lamp[2]), (1, 0, 0), (0, 0, 1), .118, .009, 'BrassLight'))
        parts.append(box('Split bumper', (side * .38, 1.29, .34), (.37, .15, .14), 'TealEnamel', .05))
        parts.append(box('Bumper cap', (side * .535, 1.292, .34), (.055, .16, .15), 'Brass', .02))
    parts.append(box('Grille dark opening', (0, 1.203, .47), (.45, .035, .27), 'Rubber', .085))
    for x in (-.17, -.085, 0, .085, .17):
        parts.append(box('Grille slat', (x, 1.23, .47), (.018, .025, .24), 'Brass', .008))
    parts.append(tube('Front crossbar', [(-.52, 1.24, .29), (0, 1.29, .265), (.52, 1.24, .29)], .025, 'DarkSteel'))
    for index in range(3):
        parts.append(box('Hood louvre', (0, .60 + index * .10, .825 - index * .035), (.24, .027, .014), 'DarkSteel', .009))
    badge = [(0, 1.202, .79), (-.075, 1.217, .705), (0, 1.236, .63), (.075, 1.217, .705), (0, 1.25, .709)]
    parts.append(mesh('Simple brass badge', badge, [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], 'BrassLight', False))
    parts.append(ellipsoid('Seat cushion', (0, -.16, .62), (.31, .34, .095), 'Leather'))
    seat = ellipsoid('Padded seat back', (0, -.44, .88), (.31, .09, .32), 'Leather')
    seat.rotation_euler.x = math.radians(-10)
    parts.append(seat)
    for x in (-.2, -.1, 0, .1, .2):
        parts.append(tube('Seat stitched channel', [(x, -.348, .70), (x, -.32, .89), (x * .88, -.35, 1.08)], .007, 'LeatherLight', 6))
    parts.append(tube('Seat roll hoop', [(-.32, -.48, .61), (-.35, -.50, 1.03), (-.25, -.52, 1.18), (.25, -.52, 1.18), (.35, -.50, 1.03), (.32, -.48, .61)], .035, 'DarkSteel'))
    return batch(parts, 'Body', root)


def make_wheel(root, name, side, y, radius, width, steering):
    center = Vector((side * (.80 if steering else .825), y, radius))
    pivot = empty(name + ('Steer' if steering else 'Pivot'), center, root)
    parts = []
    profile = [(-width / 2, radius * .52), (-width / 2, radius * .82), (-width * .43, radius * .97), (-width * .22, radius), (width * .22, radius), (width * .43, radius * .97), (width / 2, radius * .82), (width / 2, radius * .52)]
    rings = []
    for i in range(49):
        angle = i * 2 * PI / 48
        rings.append([center + Vector((x, math.sin(angle) * r, math.cos(angle) * r)) for x, r in profile])
    parts.append(loft('Rounded rubber carcass', rings, 'Rubber', True, False))
    for i in range(28):
        theta = i * 2 * PI / 28
        for row in (-1, 1):
            point = center + Vector((row * width * .23, math.sin(theta) * (radius - .003), math.cos(theta) * (radius - .003)))
            tread = box('Directional tread', point, (width * .48, .095, .028), 'Tread', .009, bevel_segments=1)
            # Twist in the contact plane before rotating the block around the axle.
            tread.rotation_mode = 'QUATERNION'
            tread.rotation_quaternion = Quaternion((1, 0, 0), -theta) @ Quaternion((0, 0, 1), row * .18)
            parts.append(tread)
    outside = center + Vector((side * (width / 2 + .005), 0, 0))
    parts.append(cylinder('Rim face', outside - Vector((side * .035, 0, 0)), outside, radius * .59, 'Brass'))
    parts.append(cylinder('Inset hub dark', outside, outside + Vector((side * .01, 0, 0)), radius * .43, 'DarkSteel'))
    parts.append(ring('Rim rolled edge', outside, (0, 1, 0), (0, 0, 1), radius * .555, .018, 'BrassLight'))
    for index in range(6):
        angle = index * 2 * PI / 6
        a = outside + Vector((side * .02, math.sin(angle) * radius * .13, math.cos(angle) * radius * .13))
        b = outside + Vector((side * .018, math.sin(angle + .1) * radius * .47, math.cos(angle + .1) * radius * .47))
        parts.append(tube('Rim spoke', [a, b], .025, 'Brass'))
        bolt = outside + Vector((side * .038, math.sin(angle) * radius * .28, math.cos(angle) * radius * .28))
        parts.append(ellipsoid('Wheel bolt', bolt, (.011, .014, .014), 'BrassLight', 8, 6))
    parts.append(cylinder('Axle cap', outside, outside + Vector((side * .06, 0, 0)), radius * .15, 'BrassLight', 16))
    return batch(parts, name + 'Roll', pivot, center)


def make_driver(root):
    lean = empty('DriverLean', (0, -.08, .71), root)
    body = []
    rows = []
    for z, x_radius, y_radius, cy in [(.68, .18, .14, -.07), (.78, .245, .155, -.09), (.99, .27, .16, -.09), (1.16, .23, .14, -.11), (1.24, .12, .105, -.10)]:
        rows.append([(x_radius * math.cos(i * 2 * PI / 24), cy + y_radius * math.sin(i * 2 * PI / 24), z) for i in range(24)])
    body.append(loft('Coat torso', rows, 'BlueCloth'))
    body.append(tube('Coat front seam', [(0, .077, .73), (0, .085, .92), (0, .055, 1.12)], .011, 'BlueDark'))
    for z in (.82, .94, 1.06):
        body.append(ellipsoid('Coat button', (0, .099, z), (.015, .008, .015), 'Brass', 10, 6))
    for side in (-1, 1):
        body.append(tube('Bent sleeve', [(side * .18, -.07, 1.14), (side * .28, .02, 1.085), (side * .30, .17, .965), (side * .205, .36, .97)], [.093, .09, .078, .059], 'BlueCloth', 16))
        body.append(tube('Sleeve seam', [(side * .244, -.006, 1.15), (side * .345, .10, 1.028), (side * .255, .31, 1.0)], .009, 'BlueDark', 6))
        body.append(ellipsoid('Bent trouser thigh', (side * .15, .08, .70), (.14, .27, .105), 'BlueDark'))
        body.append(ellipsoid('Boot', (side * .17, .38, .50), (.12, .18, .08), 'Leather'))
        body.append(tube('Leather shoulder strap', [(side * .13, -.20, 1.17), (side * .155, .005, 1.15), (side * .20, .064, .87)], .025, 'Leather', 8))
    batch(body, 'DriverBody', lean, (0, -.08, .71))
    head_pivot = empty('HeadMotion', (0, -.075, 1.43), lean)
    face = []
    face.append(ellipsoid('Head sculpt mass', (0, -.07, 1.427), (.203, .175, .228), 'Skin', 32, 24))
    face.append(ellipsoid('Jaw mass', (0, .02, 1.29), (.156, .13, .125), 'Skin'))
    for side in (-1, 1):
        face.append(ellipsoid('Cheekbone', (side * .13, .063, 1.387), (.069, .044, .048), 'SkinWarm'))
        face.append(ellipsoid('Eye socket', (side * .083, .091, 1.479), (.062, .022, .046), 'SkinShadow'))
        face.append(ellipsoid('Eye white', (side * .083, .112, 1.483), (.041, .014, .027), 'EyeWhite'))
        face.append(ellipsoid('Iris', (side * .079, .126, 1.482), (.017, .007, .018), 'Iris', 18, 12))
        face.append(ellipsoid('Pupil', (side * .078, .133, 1.482), (.008, .003, .011), 'Rubber', 12, 8))
        face.append(ellipsoid('Eye light', (side * .072, .136, 1.489), (.003, .002, .003), 'EyeWhite', 8, 6))
        eye_x = side * .083
        face.append(tube('Upper eyelid sculpt', [(eye_x - .044, .11, 1.478), (eye_x - .026, .124, 1.500), (eye_x + .011, .126, 1.503), (eye_x + .045, .109, 1.479)], [.009, .013, .013, .009], 'Skin', 8))
        face.append(tube('Lower eyelid sculpt', [(eye_x - .044, .11, 1.478), (eye_x, .126, 1.46), (eye_x + .044, .11, 1.478)], [.008, .01, .008], 'SkinWarm', 8))
        ear_outline = [(side * .166, -.068, 1.52), (side * .26, -.022, 1.535), (side * .357, -.07, 1.59), (side * .297, -.068, 1.428), (side * .215, -.04, 1.408)]
        ear_center = Vector((side * .238, .022, 1.487))
        outer = [Vector(p) for p in ear_outline]
        verts = outer + [ear_center, Vector((side * .235, -.064, 1.493))]
        faces = [(i, (i + 1) % 5, 5) for i in range(5)] + [((i + 1) % 5, i, 6) for i in range(5)]
        ear = mesh('Pointed ear', verts, faces, 'Skin', True)
        bpy.context.view_layer.objects.active = ear
        mod = ear.modifiers.new('Ear sculpt smoothing', 'SUBSURF'); mod.levels = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
        face.append(ear)
        face.append(tube('Ear inner fold', [(side * .205, .005, 1.49), (side * .266, -.002, 1.51), (side * .308, -.035, 1.554)], [.018, .021, .006], 'SkinWarm', 8))
        face.append(tube('Swept eyebrow', [(side * .022, .103, 1.548), (side * .065, .137, 1.542), (side * .127, .128, 1.554), (side * .166, .070, 1.54)], [.024, .033, .027, .007], 'Hair', 10))
        face.append(tube('Moustache wing', [(side * .012, .183, 1.398), (side * .071, .209, 1.388), (side * .133, .189, 1.369), (side * .186, .143, 1.388)], [.028, .049, .036, .003], 'Hair', 12))
    face.append(ellipsoid('Nose bridge', (0, .111, 1.48), (.046, .055, .085), 'Skin'))
    face.append(ellipsoid('Prominent nose', (0, .179, 1.438), (.065, .08, .055), 'SkinWarm', 28, 18))
    face.append(tube('Mouth under moustache', [(-.051, .163, 1.343), (0, .183, 1.338), (.051, .163, 1.343)], .012, 'SkinShadow', 8))
    beard_rings = []
    for z, width, cy, depth in [(1.39, .15, .085, .086), (1.31, .183, .103, .103), (1.22, .149, .124, .103), (1.12, .091, .158, .061), (1.047, .012, .176, .013)]:
        beard_rings.append([(width * math.cos(i * 2 * PI / 24), cy + depth * math.sin(i * 2 * PI / 24), z) for i in range(24)])
    face.append(loft('Continuous beard sculpt', beard_rings, 'HairShadow'))
    for index in range(-4, 5):
        x = index * .036
        face.append(tube('Swept beard lock', [(x, .163 - abs(index) * .006, 1.347), (x * 1.06, .214 - abs(index) * .009, 1.272), (x * .73, .226 - abs(index) * .01, 1.176 + abs(index) * .014), (x * .40, .19, 1.06 + abs(index) * .031)], [.029, .029, .021, .0015], 'Hair', 10))
    for index in range(13):
        angle = PI * .05 + PI * .9 * index / 12
        x = math.cos(angle) * .198
        y = -.075 - math.sin(angle) * .177
        face.append(tube('Back hair sculpt lock', [(x, y, 1.58), (x * 1.06, y - .014, 1.49), (x * 1.03, y - .02, 1.37), (x * .92, y + .025, 1.325 + .03 * math.sin(index))], [.030, .033, .026, .002], 'Hair', 9))
    batch(face, 'Head', head_pivot, (0, -.075, 1.43))
    hat_rings = []
    rows = [(1.60, 0, -.072, .206, .174), (1.64, 0, -.075, .21, .18), (1.69, .005, -.085, .186, .165), (1.78, .022, -.11, .15, .14), (1.88, .053, -.14, .12, .106), (1.965, .10, -.18, .082, .073), (2.02, .166, -.22, .060, .046), (2.007, .237, -.253, .048, .037), (1.953, .302, -.269, .029, .025), (1.928, .346, -.254, .004, .004)]
    for row_index, (z, cx, cy, rx, ry) in enumerate(rows):
        before = rows[max(0, row_index - 1)]
        after = rows[min(len(rows) - 1, row_index + 1)]
        tangent = Vector((after[1] - before[1], after[2] - before[2], after[0] - before[0])).normalized()
        right = (Vector((1, 0, 0)) - tangent * tangent.x).normalized()
        across = tangent.cross(right).normalized()
        ring_points = []
        for i in range(32):
            a = i * 2 * PI / 32
            wrinkle = 1.0 + .03 * math.sin(a * 5 + row_index * .75)
            ring_points.append(Vector((cx, cy, z)) + right * (math.cos(a) * rx * wrinkle) + across * (math.sin(a) * ry * wrinkle) + tangent * (.004 * math.cos(a * 3 + row_index)))
        hat_rings.append(ring_points)
    hat_parts = [loft('Bent cloth crown', hat_rings, 'RedCloth')]
    hat_parts.append(tube('Hat rolled hem', [(math.cos(i * 2 * PI / 48) * .208, -.074 + math.sin(i * 2 * PI / 48) * .178, 1.628 + .006 * math.sin(i * 4 * PI / 48)) for i in range(49)], .018, 'RedDark'))
    batch(hat_parts, 'Hat', head_pivot, (0, -.075, 1.43))
    return lean


def make_steering(root):
    center = Vector((0, .39, .99))
    pivot = empty('SteeringPivot', center, root)
    up = Vector((0, -.48, .877)).normalized()
    points = [center + Vector((1, 0, 0)) * math.cos(i * 2 * PI / 40) * .215 + up * math.sin(i * 2 * PI / 40) * .215 for i in range(41)]
    parts = [tube('Leather wheel grip', points, .025, 'Leather', 10)]
    for angle in (PI / 2, PI * 7 / 6, PI * 11 / 6):
        parts.append(tube('Steering spoke', [center, center + Vector((1, 0, 0)) * math.cos(angle) * .197 + up * math.sin(angle) * .197], .013, 'Brass'))
    parts.append(ellipsoid('Steering hub', center, (.038, .025, .038), 'Brass'))
    batch(parts, 'SteeringWheel', pivot, center)
    for side, name in ((-1, 'LeftHand'), (1, 'RightHand')):
        hand_center = center + Vector((side * .205, 0, 0))
        glove = [ellipsoid('Gloved palm', hand_center + Vector((0, -.019, .006)), (.062, .056, .071), 'Leather')]
        for finger in range(4):
            x = hand_center.x + (finger - 1.5) * .025
            glove.append(tube('Curled gloved finger', [(x, .369, 1.030), (x, .421, 1.021), (x, .43, .988), (x, .399, .97)], [.014, .015, .015, .011], 'LeatherLight', 8))
        glove.append(tube('Gloved thumb', [hand_center + Vector((-side * .03, -.036, .024)), hand_center + Vector((-side * .052, .015, .047)), hand_center + Vector((-side * .018, .040, .025))], [.026, .022, .015], 'Leather', 10))
        batch(glove, name, pivot, center)
    return pivot


def make_engine(root):
    parts = []
    crystal_origin = Vector((0, -.91, .70))
    pivot = empty('CrystalPivot', crystal_origin, root)
    rings = []
    for z, rx, ry, cx in [(.72, .07, .055, 0), (.81, .166, .13, -.02), (1.01, .141, .108, .015), (1.16, .008, .008, .027)]:
        rings.append([(cx + math.cos(i * 2 * PI / 7) * rx, -.91 + math.sin(i * 2 * PI / 7) * ry, z) for i in range(7)])
    crystal = loft('Crystal', rings, 'Crystal', False)
    parent_keep(crystal, pivot)
    parts.append(cylinder('Crystal lower socket', (0, -.91, .64), (0, -.91, .77), .20, 'DarkSteel', 16))
    for z, radius in ((.72, .201), (.80, .194)):
        parts.append(ring('Crystal brass socket lip', (0, -.91, z), (1, 0, 0), (0, 1, 0), radius, .021, 'Brass'))
    for side in (-1, 1):
        parts.append(tube('Reactor cradle', [(side * .20, -.82, .72), (side * .25, -.88, .91), (side * .16, -.87, 1.08)], .025, 'Brass'))
        parts.append(cylinder('Rear spring housing', (side * .31, -.68, .54), (side * .35, -1.00, .68), .045, 'DarkSteel'))
        outlet = Vector((side * .39, -1.285, .505))
        parts.append(cylinder('Exhaust dark barrel', (side * .39, -.86, .53), outlet, .13, 'DarkSteel'))
        parts.append(cylinder('Exhaust brass muzzle', (side * .39, -1.18, .507), outlet, .15, 'Brass'))
        parts.append(cylinder('Nozzle dark bore', outlet + Vector((0, -.004, 0)), outlet + Vector((0, -.014, 0)), .121, 'Rubber'))
        parts.append(cylinder('Nozzle luminous inset', outlet + Vector((0, -.015, 0)), outlet + Vector((0, -.018, 0)), .069, 'Crystal'))
        parts.append(ring('Nozzle rim', outlet + Vector((0, -.022, 0)), (1, 0, 0), (0, 0, 1), .133, .017, 'BrassLight'))
        empty('ExhaustLeft' if side < 0 else 'ExhaustRight', outlet + Vector((0, -.03, 0)), root)
    parts.append(box('Rear battery', (0, -1.10, .44), (.40, .29, .19), 'DarkSteel', .06))
    for z in (.4, .49):
        parts.append(box('Rear battery strap', (0, -1.252, z), (.41, .025, .027), 'Brass', .009))
    batch(parts, 'EngineCradle', root)


def camera(name, position, target, ortho=3.45):
    data = bpy.data.cameras.new(name)
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    data.type = 'ORTHO'
    data.ortho_scale = ortho
    return obj


def stage():
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.world.color = (.35, .35, .35)
    scene.view_settings.view_transform = 'AgX'
    scene.view_settings.look = 'AgX - Medium High Contrast'
    floor_material = make_material('StudioOnly', '9babad', 0, .8)
    bpy.ops.mesh.primitive_plane_add(size=200)
    bpy.context.object.name = 'StudioGround_NotExported'
    bpy.context.object.data.materials.append(floor_material)
    for name, position, power, size, color in [
        ('Key', (3.5, 4.5, 5.5), 900, 5, (1, .87, .73)),
        ('Fill', (-4, 2, 3.0), 750, 4, (.69, .85, 1)),
        ('Rim', (1, -4, 4.5), 1200, 3, (1, .95, .8)),
    ]:
        data = bpy.data.lights.new(name, 'AREA'); data.energy = power; data.shape = 'DISK'; data.size = size; data.color = color
        obj = bpy.data.objects.new(name, data); scene.collection.objects.link(obj); obj.location = position
        obj.rotation_euler = (Vector((0, 0, .8)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    return [camera('FrontCamera', (0, 6, 2.7), (0, 0, 1), 3.1), camera('RearCamera', (0, -6, 2.7), (0, 0, 1), 3.1), camera('SideCamera', (-6, 0, 2.1), (0, 0, 1.0), 3.4), camera('ThreeQuarterCamera', (-4.4, 5.4, 3.1), (0, 0, 1.0), 3.25)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-dir', required=True)
    parser.add_argument('--runtime', required=True)
    parser.add_argument('--renders', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    source = Path(args.source_dir).resolve(); runtime = Path(args.runtime).resolve(); renders = Path(args.renders).resolve()
    for directory in (source, runtime.parent, renders): directory.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    bpy.context.scene.unit_settings.system = 'METRIC'; bpy.context.scene.unit_settings.scale_length = 1
    for params in [
        ('TealEnamel', '248d89', .18, .4), ('Brass', 'ad853f', .75, .37), ('BrassLight', 'd1af6b', .75, .3),
        ('DarkSteel', '303b3b', .7, .38), ('Rubber', '20262a', 0, .84), ('Tread', '303539', 0, .86),
        ('Leather', '453b31', 0, .56), ('LeatherLight', '635043', 0, .63), ('BlueCloth', '285a79', 0, .92), ('BlueDark', '203e57', 0, .92),
        ('RedCloth', 'a92932', 0, .93), ('RedDark', '7e2229', 0, .93), ('Skin', 'df9b7c', 0, .7), ('SkinWarm', 'da8870', 0, .67),
        ('SkinShadow', 'a86756', 0, .77), ('Hair', 'e5e6df', 0, .89), ('HairShadow', 'bfc8c7', 0, .94),
        ('EyeWhite', 'f5f0d8', 0, .32), ('Iris', '578d93', .05, .24), ('Crystal', '47e4ef', .1, .2, .6), ('Headlamp', 'ffe7ab', .05, .23, .45),
    ]: make_material(*params)
    root = empty('HeroBlockout')
    make_body(root)
    make_wheel(root, 'FrontLeft', -1, .78, .40, .34, True)
    make_wheel(root, 'FrontRight', 1, .78, .40, .34, True)
    make_wheel(root, 'RearLeft', -1, -.78, .43, .4, False)
    make_wheel(root, 'RearRight', 1, -.78, .43, .4, False)
    make_driver(root)
    make_steering(root)
    make_engine(root)
    bpy.context.view_layer.update()
    children = list(root.children_recursive)
    for obj in children:
        if obj.type != 'MESH':
            continue
        edit = bmesh.new()
        edit.from_mesh(obj.data)
        bmesh.ops.recalc_face_normals(edit, faces=list(edit.faces))
        edit.to_mesh(obj.data)
        edit.free()
    vertices = [obj.matrix_world @ vertex.co for obj in children if obj.type == 'MESH' for vertex in obj.data.vertices]
    bounds_min = [min(v[axis] for v in vertices) for axis in range(3)]
    bounds_max = [max(v[axis] for v in vertices) for axis in range(3)]
    # Tread contact can extend a few millimetres beyond the analytical tire radius.
    ground_offset = -bounds_min[2]
    for obj in list(root.children): obj.location.z += ground_offset
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    root.select_set(True)
    for obj in children: obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=str(runtime), export_format='GLB', use_selection=True, export_yup=True, export_apply=True, export_texcoords=False, export_normals=True, export_materials='EXPORT', export_animations=False, export_cameras=False, export_lights=False)
    cameras = stage()
    source_path = source / 'hero-blockout.blend'
    bpy.context.scene.camera = cameras[3]
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(source_path), compress=True)
    if source_path.stat().st_size + runtime.stat().st_size >= 10 * 1024 * 1024:
        raise RuntimeError('Source + runtime must remain below 10 MiB')
    for cam in cameras:
        bpy.context.scene.camera = cam
        bpy.context.scene.render.filepath = str(renders / (cam.name + '.png'))
        bpy.ops.render.render(write_still=True)
    print('HERO_BLOCKOUT_EXPORT ' + json.dumps({'sourceBytes': source_path.stat().st_size, 'glbBytes': runtime.stat().st_size, 'sha256': hashlib.sha256(runtime.read_bytes()).hexdigest(), 'meshCount': sum(obj.type == 'MESH' for obj in children), 'blenderBoundsMinBeforeGroundOffset': bounds_min, 'blenderBoundsMaxBeforeGroundOffset': bounds_max, 'groundOffset': ground_offset}))


main()
