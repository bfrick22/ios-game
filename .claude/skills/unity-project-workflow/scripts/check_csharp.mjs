import { Parser, Language } from 'web-tree-sitter';
import fs from 'fs';
import path from 'path';
const here = path.dirname(new URL(import.meta.url).pathname);
await Parser.init();
const lang = await Language.load(here + '/node_modules/tree-sitter-c-sharp/tree-sitter-c_sharp.wasm');
const p = new Parser(); p.setLanguage(lang);
let bad = 0;
for (const f of process.argv.slice(2)) {
  const tree = p.parse(fs.readFileSync(f, 'utf8'));
  const errs = [];
  (function walk(n){ if (n.type === 'ERROR' || n.isMissing) errs.push(n); for (let i=0;i<n.childCount;i++) walk(n.child(i)); })(tree.rootNode);
  if (errs.length) { bad++; for (const e of errs.slice(0,3)) console.log(`${path.basename(f)}:${e.startPosition.row+1}:${e.startPosition.column+1} ${e.isMissing?'missing '+e.type:'syntax error'}`); }
}
console.log(bad ? `FAIL (${bad} files)` : `all ${process.argv.length-2} files parse`);
process.exit(bad ? 1 : 0);
