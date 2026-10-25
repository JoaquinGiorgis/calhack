// Exports every enclosure part to STL using the WASM build of OpenSCAD
// (works on macOS without the native OpenSCAD.app).
// Usage: node export-stl.mjs [part ...]
import { createOpenSCAD } from "openscad-wasm-prebuilt";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const encDir = join(here, "..", "enclosure");
const src = readFileSync(join(encDir, "fortwatch_case.scad"), "utf8");
const parts = process.argv.length > 2 ? process.argv.slice(2) : ["fit_test", "shell", "back", "pod", "pod_lid", "assembly"];
mkdirSync(join(encDir, "stl"), { recursive: true });

for (const part of parts) {
  const errs = [];
  const scad = await createOpenSCAD({ print: () => {}, printErr: (m) => errs.push(m) });
  const inst = scad.getInstance();
  inst.FS.writeFile("/in.scad", src);
  const code = inst.callMain(["/in.scad", "-D", `part="${part}"`, "-o", "/out.stl"]);
  if (code !== 0) {
    console.error(`✗ ${part}\n${errs.join("\n")}`);
    process.exitCode = 1;
    continue;
  }
  const out = join(encDir, "stl", `${part}.stl`);
  writeFileSync(out, inst.FS.readFile("/out.stl"));
  const warn = errs.filter((m) => /WARNING|ERROR/.test(m));
  console.log(`✓ ${part} -> ${out}${warn.length ? "\n  " + warn.join("\n  ") : ""}`);
}
