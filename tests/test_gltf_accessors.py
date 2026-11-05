"""Checks for the glTF accessor, transform, image and writer bindings.
Builds a tiny GLB in memory (positions float32, COLOR_0 normalized u8 VEC3,
a node with a translation) and exercises: AccessorView on u8 vectors,
accessor_to_numpy normalization, for_each_primitive_in_scene transform,
ImageAsset.pixels, write_glb multi-buffer error, content types registered."""
import json
import struct
import sys

import numpy as np

import cesium
from cesium.gltf import AccessorView, Model, ImageAsset, accessor_to_numpy
from cesium.gltf.reader import GltfReader
from cesium.gltf.writer import GltfWriter


def tiny_glb():
    pos = np.array([[0, 0, 0], [1, 0, 0], [0, 1, 0]], np.float32)
    col = np.array([[255, 0, 0], [0, 255, 0], [0, 0, 255]], np.uint8)
    col_bytes = col.tobytes() + b"\0" * ((4 - (col.nbytes % 4)) % 4)
    bin_ = pos.tobytes() + col_bytes
    j = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "translation": [10.0, 20.0, 30.0]}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "COLOR_0": 1}, "mode": 0}]}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
             "min": [0, 0, 0], "max": [1, 1, 0]},
            {"bufferView": 1, "componentType": 5121, "count": 3, "type": "VEC3", "normalized": True},
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": pos.nbytes},
            {"buffer": 0, "byteOffset": pos.nbytes, "byteLength": col.nbytes},
        ],
        "buffers": [{"byteLength": len(bin_)}],
    }
    js = json.dumps(j).encode()
    js += b" " * ((4 - (len(js) % 4)) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_)
    return (struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js
            + struct.pack("<I4s", len(bin_), b"BIN\0") + bin_)


res = GltfReader().read_gltf(tiny_glb())
assert res.model is not None, res.errors
model = res.model

# C2: u8 vector view + normalized decoding
v = AccessorView(model, 1)
a = np.asarray(v)
assert a.dtype == np.uint8 and a.shape == (3, 3) and a[1, 1] == 255, (a.dtype, a.shape)
f = accessor_to_numpy(model, 1)
assert f.dtype == np.float32 and abs(float(f[0, 0]) - 1.0) < 1e-6 and f[0, 1] == 0.0, f
p = accessor_to_numpy(model, 0)
assert p.dtype == np.float32 and p.shape == (3, 3)
print("C2 ok:", type(v).__name__, a.tolist()[0], f.tolist()[0])

# C3: transform arrives as a (4, 4) float64 array, translation in arr[3][:3]
seen = []
model.for_each_primitive_in_scene(0, lambda m, n, me, pr, t: seen.append(t))
assert len(seen) == 1, seen
t = seen[0]
assert isinstance(t, np.ndarray) and t.shape == (4, 4) and t.dtype == np.float64, (type(t), getattr(t, "shape", None))
assert np.allclose(t[3][:3], [10, 20, 30]), t
print("C3 ok: translation", t[3][:3].tolist())

# C8: ImageAsset.pixels
img = ImageAsset()
img.width, img.height, img.channels, img.bytes_per_channel = 4, 2, 3, 1
img.pixel_data = np.arange(24, dtype=np.uint8)
px = img.pixels
assert px.shape == (2, 4, 3) and px.dtype == np.uint8 and int(px[1, 3, 2]) == 23, (px.shape, px.dtype)
print("C8 ok:", px.shape, px.dtype)

# C9: write_glb refuses a model with two buffers
from cesium.gltf import Buffer  # noqa: E402
bufs = model.buffers          # pybind11 hands out a copy of the list
bufs.append(Buffer())
model.buffers = bufs
assert len(model.buffers) == 2
try:
    GltfWriter().write_glb(model, b"")
    raise SystemExit("C9 FAILED: no error for a 2-buffer model")
except ValueError as e:
    assert "collapse_to_single_buffer" in str(e), e
    print("C9 ok:", str(e)[:60])

# C1: content types registered at import: the converters resolve without an
# explicit register_all_tile_content_types() call (cesium-native registers
# b3dm / pnts / i3dm / cmpt by magic and glTF / GLB by extension and magic)
from cesium.tiles import content  # noqa: E402
assert content.GltfConverters.converter_by_magic(b"b3dm" + bytes(24)) == "b3dm"
assert content.GltfConverters.converter_by_magic(b"glTF" + bytes(24)) == "binary"
assert content.GltfConverters.converter_by_file_extension("tile.glb") == "binary"
print("C1 ok: converters registered at import")
print("ALL OK", cesium.__file__)
