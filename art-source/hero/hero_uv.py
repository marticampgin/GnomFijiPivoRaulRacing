"""Bounded, geometry-preserving UV fold repair and analytic overlap evidence."""

from collections import defaultdict
import math

import bpy


UV_NAME = 'HeroAtlasUV'
GRID_SIZE = 256
AREA_TOLERANCE = 1e-12
LINE_TOLERANCE = 1e-12
COLLAPSED_UV_TOLERANCE = 1e-18
GEOMETRY_AREA_TOLERANCE = 1e-12


def _cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _area(points):
    if len(points) < 3:
        return 0.0
    return abs(sum(_cross(points[0], points[index], points[index + 1]) for index in range(1, len(points) - 1))) * 0.5


def _intersection_area(first, second):
    polygon = list(first)
    clip = second if _cross(*second) >= 0.0 else tuple(reversed(second))
    for index in range(3):
        edge_a, edge_b = clip[index], clip[(index + 1) % 3]
        if not polygon:
            return 0.0
        result = []
        previous = polygon[-1]
        previous_distance = _cross(edge_a, edge_b, previous)
        for current in polygon:
            current_distance = _cross(edge_a, edge_b, current)
            previous_inside = previous_distance >= -LINE_TOLERANCE
            current_inside = current_distance >= -LINE_TOLERANCE
            if previous_inside != current_inside:
                divisor = previous_distance - current_distance
                if abs(divisor) > 1e-30:
                    fraction = previous_distance / divisor
                    result.append((previous[0] + fraction * (current[0] - previous[0]), previous[1] + fraction * (current[1] - previous[1])))
            if current_inside:
                result.append(current)
            previous, previous_distance = current, current_distance
        polygon = result
    return _area(polygon)


def _verify_clipper():
    first = ((0.0, 0.0), (1.0, 0.0), (0.0, 1.0))
    controls = [
        (first, 0.5),
        (((1.0, 0.0), (1.0, 1.0), (0.0, 1.0)), 0.0),
        (((1.0, 0.0), (2.0, 0.0), (1.0, 1.0)), 0.0),
        (((0.0, 0.0), (0.5, 0.0), (0.0, 0.5)), 0.125),
        (((2.0, 2.0), (3.0, 2.0), (2.0, 3.0)), 0.0),
    ]
    for second, expected in controls:
        if abs(_intersection_area(first, second) - expected) > AREA_TOLERANCE:
            raise AssertionError('UV intersection control failed')


def _scan(objects):
    triangles, buckets = [], defaultdict(list)
    bad_faces = defaultdict(set)
    collapsed = degenerate_geometry = tiny_valid = total = 0
    for object_index, obj in enumerate(objects):
        mesh = obj.data
        layer = mesh.uv_layers.get(UV_NAME)
        if layer is None or len(layer.data) != len(mesh.loops):
            raise AssertionError(f'{obj.name}: complete {UV_NAME} required')
        mesh.calc_loop_triangles()
        total += len(mesh.loop_triangles)
        for triangle in mesh.loop_triangles:
            points = tuple((float(layer.data[index].uv.x), float(layer.data[index].uv.y)) for index in triangle.loops)
            if not all(math.isfinite(value) and -0.0001 <= value <= 1.0001 for point in points for value in point):
                raise AssertionError(f'{obj.name}: UV coordinate outside finite atlas bounds')
            uv_area = _area(points)
            if uv_area <= AREA_TOLERANCE:
                if triangle.area <= GEOMETRY_AREA_TOLERANCE:
                    degenerate_geometry += 1
                elif uv_area <= COLLAPSED_UV_TOLERANCE:
                    bad_faces[object_index].add(triangle.polygon_index)
                    collapsed += 1
                else:
                    tiny_valid += 1
                continue
            bounds = (min(point[0] for point in points), min(point[1] for point in points), max(point[0] for point in points), max(point[1] for point in points))
            index = len(triangles)
            triangles.append((object_index, triangle.polygon_index, points, bounds))
            grid_bounds = [max(0, min(GRID_SIZE - 1, int(math.floor(value * GRID_SIZE)))) for value in bounds]
            for x in range(grid_bounds[0], grid_bounds[2] + 1):
                for y in range(grid_bounds[1], grid_bounds[3] + 1):
                    buckets[(x, y)].append(index)
    seen = set()
    inter_object = same_object = analytic_tests = 0
    overlap_area = maximum_area = 0.0
    for bucket in buckets.values():
        for offset, index_a in enumerate(bucket):
            a = triangles[index_a]
            for index_b in bucket[offset + 1:]:
                pair = (index_a, index_b)
                if pair in seen:
                    continue
                seen.add(pair)
                b = triangles[index_b]
                aa, bb = a[3], b[3]
                if min(aa[2], bb[2]) <= max(aa[0], bb[0]) + LINE_TOLERANCE or min(aa[3], bb[3]) <= max(aa[1], bb[1]) + LINE_TOLERANCE:
                    continue
                analytic_tests += 1
                overlap = _intersection_area(a[2], b[2])
                if overlap <= AREA_TOLERANCE:
                    continue
                if a[0] == b[0]:
                    same_object += 1
                else:
                    inter_object += 1
                overlap_area += overlap
                maximum_area = max(maximum_area, overlap)
                bad_faces[a[0]].add(a[1])
                bad_faces[b[0]].add(b[1])
    return bad_faces, {
        'triangles': total,
        'positiveAreaTrianglesChecked': len(triangles),
        'uniqueBroadPhasePairs': len(seen),
        'analyticTriangleIntersections': analytic_tests,
        'interObjectOverlapPairs': inter_object,
        'sameObjectOverlapPairs': same_object,
        'summedPairwiseIntersectionArea': overlap_area,
        'maxIntersectionArea': maximum_area,
        'collapsedNonzeroGeometryUvTriangles': collapsed,
        'degenerateGeometryTriangles': degenerate_geometry,
        'tinyValidUvTrianglesBelowOverlapTolerance': tiny_valid,
        'offendingPolygons': sum(len(faces) for faces in bad_faces.values()),
    }


def audit_uv_overlaps(mesh_objects):
    """Exhaustive positive-area candidate clipping, not texture/raster sampling."""
    _verify_clipper()
    objects = sorted(mesh_objects, key=lambda obj: obj.name)
    return _scan(objects)[1]


def _isolate_convex_faces(objects, bad_faces):
    counter = 0
    for object_index, faces in sorted(bad_faces.items()):
        mesh = objects[object_index].data
        layer = mesh.uv_layers[UV_NAME]
        for face_index in sorted(faces):
            polygon = mesh.polygons[face_index]
            count = polygon.loop_total
            # A convex loop mapping unfolds projected quads without retriangulating them.
            radius = max(0.002, math.sqrt(max(polygon.area, 1e-12) / (count * math.sin(2.0 * math.pi / count) * 0.5)))
            center_x, center_y = 10.0 + (counter % 128) * 4.0, 10.0 + (counter // 128) * 4.0
            for corner, loop_index in enumerate(polygon.loop_indices):
                angle = 2.0 * math.pi * corner / count
                layer.data[loop_index].uv = (center_x + radius * math.cos(angle), center_y + radius * math.sin(angle))
            counter += 1
    return counter


def _repack(objects, atlas_size):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
        obj.data.uv_layers.active = obj.data.uv_layers[UV_NAME]
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.mode_set(mode='EDIT')
    try:
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.uv.select_all(action='SELECT')
        bpy.ops.uv.average_islands_scale()
        bpy.ops.uv.pack_islands(rotate=True, scale=True, margin_method='FRACTION', margin=8.0 / atlas_size, shape_method='AABB')
    finally:
        bpy.ops.object.mode_set(mode='OBJECT')


def repair_uv_overlaps(mesh_objects, atlas_size, max_repairs=5):
    """Detach only faulty polygon UVs, repack, and refuse an unresolved bake.

    Existing geometrically degenerate triangles are counted, not altered or
    mislabeled as clean geometry. Pure edge contact does not count as overlap.
    """
    _verify_clipper()
    objects = sorted(mesh_objects, key=lambda obj: obj.name)
    history = []
    repaired_faces = 0
    for iteration in range(max_repairs + 1):
        bad_faces, stats = _scan(objects)
        history.append(stats)
        print(f'HERO_UV_AUDIT {iteration}: inter={stats["interObjectOverlapPairs"]} self={stats["sameObjectOverlapPairs"]} collapsed={stats["collapsedNonzeroGeometryUvTriangles"]}', flush=True)
        if not bad_faces:
            return {
                'method': 'Analytic triangle clipping with a 256x256 spatial broad phase; convex UV islands only for offending polygons',
                'positiveAreaTolerance': AREA_TOLERANCE,
                'edgeLineTolerance': LINE_TOLERANCE,
                'collapsedUvTolerance': COLLAPSED_UV_TOLERANCE,
                'geometryAreaTolerance': GEOMETRY_AREA_TOLERANCE,
                'analyticControlsPassed': 5,
                'maxRepairPasses': max_repairs,
                'repairPasses': iteration,
                'polygonRepairOperations': repaired_faces,
                'before': history[0],
                'after': stats,
                'history': history,
                'topologyAltered': False,
                'limitations': ['Existing zero-area geometry remains counted and unchanged', 'Does not assess artistic seams or mip-filtering quality', 'Summed pairwise overlap area is not a union area'],
            }
        if iteration == max_repairs:
            raise AssertionError(f'UV repair unresolved after {max_repairs} passes: {stats}')
        repaired_faces += _isolate_convex_faces(objects, bad_faces)
        _repack(objects, atlas_size)
    raise AssertionError('Unreachable UV repair state')
