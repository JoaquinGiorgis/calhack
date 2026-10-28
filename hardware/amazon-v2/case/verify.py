"""Mesh integrity and nominal assembly clearance checks; not physical-fit proof."""
from pathlib import Path
import json
import numpy as np
import trimesh as tm
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import to_rgb
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

root=Path(__file__).resolve().parent
meshes={name:tm.load_mesh(root/'stl'/f'{name}.stl')
        for name in ['base','lid','tray','button','fit_test','plate']}
report={'limits':['Nominal dimensions only; no physical fit or printed part tested.',
                  'Generic breakout, switch, USB and microphone alignment require received-part checks.',
                  'No acoustics, battery power, thermal or firmware validation.'], 'parts':{}}
for name,m in meshes.items():
    bodies=len(m.split(only_watertight=False))
    report['parts'][name]={'watertight':bool(m.is_watertight),
      'consistent_winding':bool(m.is_winding_consistent),'bodies':bodies,
      'volume_mm3':float(m.volume),'bounds_mm':m.bounds.tolist(),
      'dimensions_mm':m.extents.tolist()}
    assert m.is_watertight and m.is_winding_consistent and m.volume>0, name
    assert bodies==(5 if name=='plate' else 1),(name,bodies)
    assert abs(m.bounds[0,2])<0.001,(name,'not on print bed')
assert max(meshes['plate'].extents[:2])<180

def shifted(m,xyz):
    out=m.copy();out.apply_translation(xyz);return out
def box(name,centre,size):
    return name,shifted(tm.creation.box(extents=size),centre)
base=meshes['base'];tray=shifted(meshes['tray'],[0,0,8.4])
lid=shifted(meshes['lid'],[0,0,22])
nominal=dict([
 box('battery',[-6,0,4.8],[35,30,5]),
 box('module_upper',[-7.5,0,18.2],[26.25,29.22,6.4]),
 box('haptic_with_wiring',[-7.5,0,12.2],[18,17,4]),
 box('mic',[9.5,20,14.8],[16.7,1.8,12.7]),
 box('tactile',[17,-10,18.95],[6,6,4.3]),
 box('switch_body',[-7.5,-20,16.75],[20,5.5,5.5]),
 box('usb_plug_access',[17.8125,0.5,14.7],[24.375,12,6]),
])
nominal['motor']=shifted(tm.creation.cylinder(radius=5,height=3,sections=48),[18,-11,3.8])
for sx in [-1,1]:
    for sy in [-1,1]:
        nominal[f'standoff_{sx}_{sy}']=shifted(
          tm.creation.cylinder(radius=1.75,height=5,sections=32),
          [-7.5+sx*22.55/2,sy*25.44/2,12.5])
report['nominal_clearance_intersections_mm3']={}
for name,component in nominal.items():
    for shell_name,shell in [('base',base),('tray',tray),('lid',lid)]:
        overlap=tm.boolean.intersection([component,shell],engine='manifold')
        volume=0.0 if overlap.is_empty else float(abs(overlap.volume))
        report['nominal_clearance_intersections_mm3'][f'{name}/{shell_name}']=volume
        assert volume<0.05,(name,shell_name,volume)
# Prevent a visually plausible but overlapping layer stack.
items=list(nominal.items())
for i,(a,ma) in enumerate(items):
    for b,mb in items[i+1:]:
        overlap=tm.boolean.intersection([ma,mb],engine='manifold')
        volume=0 if overlap.is_empty else float(abs(overlap.volume))
        assert volume<0.05,(a,b,volume)

def draw(ax,m,color,alpha=1):
    light=np.array([-.4,-.6,1.0]);light/=np.linalg.norm(light)
    shade=.50+.50*np.maximum(0,m.face_normals@light)
    colours=np.array(to_rgb(color))[None,:]*shade[:,None]
    coll=Poly3DCollection(m.triangles,facecolor=colours,edgecolor='none',alpha=alpha)
    ax.add_collection3d(coll)
fig=plt.figure(figsize=(13,6.5),facecolor='#f6f7f9')
ax=fig.add_subplot(121,projection='3d');ax.set_title('First-fit assembly · lid raised',pad=15)
draw(ax,base,'#4e677c',0.22);draw(ax,tray,'#ddd4b9',0.65)
colors={'battery':'#a9b2bc','module_upper':'#1f6c54','haptic_with_wiring':'#3175ae',
        'mic':'#3d9ab7','tactile':'#df9b37','switch_body':'#323841','motor':'#bb9565'}
for n,c in nominal.items():
    if n=='usb_plug_access' or n.startswith('standoff'): continue
    draw(ax,c,colors.get(n,'#aa9270'),0.9)
draw(ax,shifted(lid,[0,0,9]),'#4e677c',0.7)
draw(ax,shifted(meshes['button'],[17,-10,30.35]),'#e4a74e')
ax.set(xlim=(-30,30),ylim=(-35,35),zlim=(0,37));ax.set_box_aspect([60,70,37]);ax.view_init(28,-55)
ax.set_axis_off()
ax=fig.add_subplot(122,projection='3d');ax.set_title('Print plate · five separate parts',pad=15)
draw(ax,meshes['plate'],'#4e677c');bounds=meshes['plate'].bounds
ax.set(xlim=(-60,60),ylim=(-38,76),zlim=(0,28));ax.set_box_aspect([120,114,28]);ax.view_init(62,-75)
ax.set_axis_off()
fig.suptitle('FORTWATCH V2  |  52 × 50 × 24 mm body',fontsize=17,fontweight='bold')
fig.text(0.5,0.025,'Nominal engineering prototype — measure parts and print the fit coupon before final assembly.',ha='center',fontsize=10)
fig.subplots_adjust(left=0,right=1,bottom=.06,top=.86,wspace=0)
fig.savefig(root/'preview.png',dpi=150)
(root/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'parts':report['parts'],'nominal_clearance_checks':len(report['nominal_clearance_intersections_mm3'])},indent=2))
