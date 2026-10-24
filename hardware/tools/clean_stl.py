"""Rebuild every STL in hardware/enclosure/stl with manifold3d and save it as BINARY STL.

OpenSCAD (WASM) writes ASCII STL and can leave zero-area triangles, which some slicers
reject with "file error". Run this after export-stl.mjs:
    python clean_stl.py      (needs: pip install trimesh manifold3d numpy)
"""
from pathlib import Path
import numpy as np
import trimesh
import manifold3d as mf

STL = Path(__file__).resolve().parent.parent / "enclosure" / "stl"
for path in sorted(STL.glob("*.stl")):
    m = trimesh.load(path, force="mesh")
    m.merge_vertices()
    man = mf.Manifold(mf.Mesh(vert_properties=np.asarray(m.vertices, np.float32),
                              tri_verts=np.asarray(m.faces, np.uint32)))
    assert man.status() == mf.Error.NoError, f"{path.name}: {man.status()}"
    out = man.to_mesh()
    t = trimesh.Trimesh(vertices=out.vert_properties[:, :3], faces=out.tri_verts, process=True)
    t.export(path, file_type="stl")  # binary
    print(f"{path.name}: {len(t.faces)} tris, watertight={t.is_watertight}, "
          f"zero-area={int((t.area_faces < 1e-9).sum())}")
