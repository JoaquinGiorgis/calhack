import {createOpenSCAD} from '../../tools/node_modules/openscad-wasm-prebuilt/dist/openscad.js';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname,join} from 'node:path';
const here=dirname(fileURLToPath(import.meta.url));
const src=readFileSync(join(here,'fortwatch_v2.scad'),'utf8');
mkdirSync(join(here,'stl'),{recursive:true});
for(const part of process.argv.slice(2).length?process.argv.slice(2):['base','lid','tray','button','fit_test','plate']){
 const errors=[];const scad=await createOpenSCAD({print:()=>{},printErr:x=>errors.push(x)});
 const inst=scad.getInstance();inst.FS.writeFile('/case.scad',src);
 const code=inst.callMain(['/case.scad','-D',`part="${part}"`,'-o','/part.stl']);
 if(code!==0||errors.some(x=>/ERROR:/.test(x)))throw Error(errors.join('\n'));
 writeFileSync(join(here,'stl',`${part}.stl`),inst.FS.readFile('/part.stl'));
 console.log(part,errors.filter(x=>/WARNING/.test(x)).join('\n'));
}
