"""Render saved original STLs and V2 at equal scale; no physical-fit claim."""
from pathlib import Path
import json
import numpy as np
import trimesh as tm
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.colors import to_rgb
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

here=Path(__file__).resolve().parent
old=here.parents[1]/'enclosure'/'stl'
shell=tm.load_mesh(old/'shell.stl')
shell.apply_transform(np.diag([1,1,-1,1]))
shell.apply_translation([0,0,32.9]);shell.fix_normals()
back=tm.load_mesh(old/'back.stl')
old_case=tm.util.concatenate([shell,back])
new_base=tm.load_mesh(here/'stl'/'base.stl')
new_lid=tm.load_mesh(here/'stl'/'lid.stl');new_lid.apply_translation([0,0,22])
new_case=tm.util.concatenate([new_base,new_lid])
report={'original_source':'hardware/enclosure/stl/shell.stl + back.stl; print flip undone at z=32.9 mm',
 'original_printed_assembly_mm':old_case.extents.tolist(),
 'original_body_mm':[float(shell.extents[0]),float(shell.extents[1]),32.9],
 'v2_printed_assembly_mm':new_case.extents.tolist(),
 'v2_body_mm':[52,50,24],
 'limits':['Printed-envelope bounds, not material volume or weight.',
           'Original power bank shown as an approximate 74x38x25 mm box from the old viewer.',
           'The stored original STL differs from some current SCAD parameters; render uses the stored STL.',
           'V2 physical fit and comfort remain unverified.']}
(here/'size-comparison.json').write_text(json.dumps(report,indent=2)+'\n')
def box(x,y,z,w,l,h):
 m=tm.creation.box(extents=[w,l,h]);m.apply_translation([x,y,z]);return m
def draw(ax,m,c,dy=0):
 vertices,faces=tm.remesh.subdivide_to_size(m.vertices,m.faces,max_edge=4.0,max_iter=8)
 mesh=tm.Trimesh(vertices=vertices,faces=faces,process=False);mesh.apply_translation([0,dy,0])
 light=np.array([-.4,-.6,1.0]);light/=np.linalg.norm(light)
 colors=np.array(to_rgb(c))[None,:]*(.48+.52*np.maximum(0,mesh.face_normals@light))[:,None]
 ax._fort_triangles.append(mesh.triangles)
 ax._fort_colors.append(colors)

fig=plt.figure(figsize=(12,7),facecolor='#f5f6f8')
for i,title in enumerate(['Original saved design','Amazon V2 · first-fit design']):
 ax=fig.add_subplot(1,2,i+1,projection='3d')
 ax._fort_triangles=[];ax._fort_colors=[]
 ax.set_title(title,fontsize=15,fontweight='bold',pad=15)
 ax.set(xlim=(-45,45),ylim=(-74,74),zlim=(0,42))
 ax.set_box_aspect([90,148,42]);ax.view_init(42,-60);ax.set_axis_off()
 if i==0:
  dy=-float(old_case.bounds[:,1].mean())
  draw(ax,back,'#5c7184',dy);draw(ax,shell,'#5c7184',dy)
  draw(ax,box(0,0,31.15,37.1,58.8,1.1),'#202b34',dy)
  draw(ax,box(0,1.49,31.8,31,41.2,.15),'#2c9ba8',dy)
  draw(ax,box(0,-48.4,22.9,74,38,25),'#454b53',dy)
  ax.text2D(.5,-.01,'78 × 135 × 33 mm printed assembly\nSide-plugged power bank shown schematically',transform=ax.transAxes,ha='center',fontsize=10)
 else:
  draw(ax,new_base,'#5c7184');draw(ax,new_lid,'#5c7184')
  draw(ax,box(-7.5,2.91,21.2,23.4,23.4,.4),'#2c9ba8')
  cap=tm.load_mesh(here/'stl'/'button.stl');cap.apply_translation([17,-10,21.35]);draw(ax,cap,'#dfab54')
  ax.text2D(.5,-.01,'52 × 67 × 24 mm including strap ears\nBattery and microphone inside',transform=ax.transAxes,ha='center',fontsize=10)
 ax.add_collection3d(Poly3DCollection(np.concatenate(ax._fort_triangles),facecolors=np.concatenate(ax._fort_colors),edgecolors='none'))
fig.suptitle('FORTWATCH · ORIGINAL vs V2 · SAME SCALE',fontsize=17,fontweight='bold',y=.96)
fig.text(.5,.035,'CAD preview, not a photograph. Dimensions exclude fabric straps; original bank may project above its case.',ha='center',fontsize=9,color='#56606a')
fig.subplots_adjust(left=.02,right=.98,bottom=.12,top=.86,wspace=.02)
fig.savefig(here/'original-vs-v2.png',dpi=160)
print(json.dumps(report,indent=2))
