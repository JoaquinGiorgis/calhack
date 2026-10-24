"""Pre-print checks for the SoundSense STLs.

Usage: python check_stl.py   (needs: pip install trimesh manifold3d numpy scipy)

Checks per part: watertight, consistent normals, positive volume, single body,
sits on the bed (min Z = 0), bed contact area, unsupported overhangs.
Then checks that the shell and back plate don't collide when assembled.
"""
from pathlib import Path
import numpy as np
import trimesh

STL = Path(__file__).resolve().parent.parent / "enclosure" / "stl"
Z_TOP = 2.5 + 1.5 + 18.0 + 9.7 + 1.2  # shell top in assembly coords (back_t + plug_h + gap_below + standoff_depth + lip)
ok = True


def report(name, cond, msg):
    global ok
    ok &= bool(cond)
    print(f"  {'✓' if cond else '✗'} {msg}")


def overhang_area(m, min_z=0.3, max_bridge_ok=True):
    # faces pointing down more than 45° that are not on the bed
    n = m.face_normals
    centers = m.triangles_center
    down = (n[:, 2] < -0.707) & (centers[:, 2] > min_z)
    return m.area_faces[down].sum()


for name in ["shell", "back", "weight", "fit_test", "plate"]:
    m = trimesh.load(STL / f"{name}.stl")
    print(f"\n{name}.stl  ({len(m.faces)} triangles)")
    report(name, m.is_watertight, "watertight (closed)")
    report(name, m.is_winding_consistent, "consistent normals")
    report(name, m.volume > 0, f"volume {m.volume/1000:.1f} cm³")
    bodies = len(m.split(only_watertight=False))
    expected = {"plate": 4}.get(name, 1)
    report(name, bodies == expected, f"{bodies} body(ies) (expected {expected})")
    report(name, abs(m.bounds[0][2]) < 1e-3, f"sits on bed (min Z = {m.bounds[0][2]:.3f})")
    ext = m.extents
    report(name, ext[0] <= 175 and ext[1] <= 175, f"size {ext[0]:.1f} × {ext[1]:.1f} × {ext[2]:.1f} mm (fits 180 mm beds)")
    bed = m.area_faces[(m.face_normals[:, 2] < -0.999) & (m.triangles_center[:, 2] < 1e-3)].sum()
    report(name, bed > 50 or name == "weight", f"bed contact {bed:.0f} mm²")
    oh = overhang_area(m)
    print(f"  · steep overhang area above bed: {oh:.0f} mm² (bridges/grooves; small is fine)")

print("\nassembly interference (shell vs back)")
shell = trimesh.load(STL / "shell.stl")
shell.apply_transform(np.diag([1, 1, -1, 1]))  # undo print flip
shell.apply_translation([0, 0, Z_TOP])
shell.fix_normals()
back = trimesh.load(STL / "back.stl")
inter = trimesh.boolean.intersection([shell, back], engine="manifold")
v = 0 if inter.is_empty else inter.volume
report("assembly", v < 1.0, f"overlap volume {v:.3f} mm³")

# ---- component fit: do the real parts fit inside the assembled case? ----
# Values mirror soundsense_case.scad (clr 0.4, side-plugged power bank, 130 motor).
print("\ncomponent fit (jumpers, USB plug, power bank, motor, spinning weight)")
in_w, in_l, back_t = 37.9, 59.6, 2.5
bay_y0 = in_l / 2 + 1.5
motor_yc = bay_y0 + 29.6 / 2
mx0 = -in_w / 2 + 0.4 + 3 + 0.3
zc = back_t + 15 / 2
z_usb = Z_TOP - 1.2 - 7.2 - 1.6
case = trimesh.boolean.union([shell, back], engine="manifold")


def box(x0, x1, y0, y1, z0, z1):
    b = trimesh.creation.box(extents=[x1 - x0, y1 - y0, z1 - z0])
    b.apply_translation([(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2])
    return b


def cyl_x(r, x0, x1, y, z):
    c = trimesh.creation.cylinder(radius=r, height=x1 - x0, sections=48)
    c.apply_transform(trimesh.transformations.rotation_matrix(np.pi / 2, [0, 1, 0]))
    c.apply_translation([(x0 + x1) / 2, y, z])
    return c


comps = {
    # side-plugged power bank resting against the glass edge (approx. 74 x 38 x 25, and the 28 mm worst case)
    "power bank 74x38x25": box(-37, 37, -29.4 - 38, -29.4 - 0.05, z_usb - 12.5, z_usb + 12.5),
    "power bank 74x38x28 (max)": box(-37, 37, -29.4 - 38, -29.4 - 0.05, z_usb - 14 + 0.05, z_usb + 14),
    # 2 rows of 14 female Dupont jumpers on the header pins (housing 14 mm below the standoffs)
    "Dupont jumpers L": box(-17.5 + 0.2, -17.5 + 2.8, -17.8, 17.8, Z_TOP - 1.2 - 9.7 - 14, Z_TOP - 1.2 - 9.7 - 0.05),
    "Dupont jumpers R": box(17.5 - 2.8, 17.5 - 0.2, -17.8, 17.8, Z_TOP - 1.2 - 9.7 - 14, Z_TOP - 1.2 - 9.7 - 0.05),
    # USB-C cable plugged in: overmold ~12 x 6.5 mm entering through the slot up to the receptacle mouth
    "USB-C plug overmold 12x6.5": box(-6, 6, -45, -25.6 - 6.5, (Z_TOP - 1.2 - 7.2 - 1.6) - 3.25, (Z_TOP - 1.2 - 7.2 - 1.6) + 3.25),
    # driver parts under the PCB, between the header rows: PN2222 + 1 kOhm + 1N4007 + their jumpers
    "driver parts under PCB (16x24x16)": box(-8, 8, -12, 12, back_t + 2, back_t + 18),
    "motor body 25x20.4x15": box(mx0, mx0 + 25, motor_yc - 10.2, motor_yc + 10.2, back_t + 0.05, back_t + 15),
    "motor rear nub": cyl_x(3, mx0 - 3, mx0, motor_yc, zc),
    "motor shaft 8 mm": cyl_x(1, mx0 + 25, mx0 + 33, motor_yc, zc),
    "weight spinning (r 5.5)": cyl_x(5.5, mx0 + 27, mx0 + 32, motor_yc, zc),
}
for n, c in comps.items():
    hit = trimesh.boolean.intersection([case, c], engine="manifold")
    v = 0 if hit.is_empty else hit.volume
    report(n, v < 0.5, f"{n}: collision {v:.2f} mm³")

# snap tab bending strain (PLA safe below ~2 %)
strain = 3 * 1.35 * 0.4 / (2 * 14.0 ** 2)
report("snap", strain < 0.012, f"snap tab bending strain {strain*100:.2f} % (PLA design max 1-1.5 %)")
report("snap", 14.0 / 1.35 >= 10, f"snap tab L:T = {14.0/1.35:.1f} (PLA min 10:1)")

print("\nRESULT:", "READY TO PRINT ✓" if ok else "FIX ISSUES ✗")
