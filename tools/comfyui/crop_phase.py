"""Optional immutable sampling footprint for locally extended native part layers.

origin is the reference texture's (0,0) in part axes, not a fractional offset.
Validation uses only the standard library so check_spec can reject bad records
before loading a model or an image-processing runtime.
"""
import math
import numbers
import struct


def _number(value):
    try:
        return isinstance(value, numbers.Real) and not isinstance(value, bool) and math.isfinite(value)
    except (OverflowError, TypeError):
        return False


def validate_crop_phase(config, part, joints, k, field="crop_phase", source_size=None):
    def fail(key, message):
        raise ValueError(f"{field}.{key}: {message}")

    if not isinstance(config, dict):
        fail("record", "must be an object")
    if set(config) != {"origin", "size", "affine", "k"}:
        fail("record", "requires exactly origin, size, affine and k")
    origin, size, matrix = config["origin"], config["size"], config["affine"]
    if not isinstance(origin, list) or len(origin) != 2 or not all(_number(v) for v in origin):
        fail("origin", "must be two finite coordinates in part axes")
    if not isinstance(size, list) or len(size) != 2 or not all(type(v) is int and v > 0 for v in size):
        fail("size", "must be two positive integer reference dimensions")
    if not _number(config["k"]) or config["k"] <= 0 or not _number(k) or config["k"] != k:
        fail("k", "must equal the current positive texture/source density")
    if (not isinstance(matrix, list) or len(matrix) != 2 or
            any(not isinstance(row, list) or len(row) != 3 or not all(_number(v) for v in row) for row in matrix)):
        fail("affine", "must be a finite 2x3 reference matrix")
    try:
        start, end = joints[part["from"]], joints[part["to"]]
        pivot = joints[part.get("pivot", part["from"])]
        if any(len(point) != 2 or not all(_number(v) for v in point) for point in (start, end, pivot)):
            raise ValueError()
    except (KeyError, TypeError, ValueError):
        fail("affine", "requires finite registered from/to/pivot joints")
    mode = part.get("mode")
    if mode == "upright":
        ex, ey = (1., 0.), (0., 1.)
    elif mode in ("bone", "hand"):
        dx, dy = end[0] - start[0], end[1] - start[1]
        length = math.hypot(dx, dy)
        if length < 1e-6:
            fail("affine", "cannot register a degenerate bone")
        direction = (dx / length, dy / length)
        ex, ey = (direction, (-direction[1], direction[0])) if mode == "hand" else ((direction[1], -direction[0]), direction)
    else:
        fail("affine", "requires a known part mode")
    expected = [[ex[i], ey[i], pivot[i] + origin[0] * ex[i] + origin[1] * ey[i]] for i in range(2)]
    f32 = lambda value: struct.unpack("f", struct.pack("f", value))[0]
    try:
        if any(matrix[i][j] != f32(expected[i][j]) for i in range(2) for j in range(3)):
            fail("affine", "does not match origin and the current registered joint frame on the reference float32 sampling grid")
    except (OverflowError, struct.error):
        fail("affine", "is outside the supported float32 grid")
    if source_size is not None:
        bound = math.ceil(math.hypot(*source_size) * k) + 8
        if max(size) > bound or max(abs(v) for v in origin) > bound:
            fail("size", "reference footprint exceeds the native source canvas")
    return config


def freeze_crop_phase(transform, k):
    matrix, width, height, pivot = transform
    return {"origin": [-float(v) for v in pivot], "size": [int(width), int(height)],
            "affine": matrix.tolist(), "k": float(k)}


def snap_integer(value):
    nearest = round(float(value))
    return float(nearest) if abs(value - nearest) < 1e-8 else float(value)
