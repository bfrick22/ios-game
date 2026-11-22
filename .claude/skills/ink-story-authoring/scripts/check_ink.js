// Compile an .ink file with inkjs and smoke-run every top-level knot (always picks the first choice).
// Usage: node check_ink.js path/to/file.ink
const fs = require('fs');
const { Compiler } = require('inkjs/full');

const file = process.argv[2];
if (!file) { console.error('Usage: node check_ink.js file.ink'); process.exit(2); }

const compiler = new Compiler(fs.readFileSync(file, 'utf8'));
let story;
try { story = compiler.Compile(); }
catch (e) { console.error('COMPILE FAILED:', e.message, compiler.errors); process.exit(1); }
if (compiler.warnings.length) console.warn('Warnings:', compiler.warnings);
story.allowExternalFunctionFallbacks = true; // the game binds decided(); the checker uses the ink fallback

const source = fs.readFileSync(file, 'utf8');
const functions = new Set([...source.matchAll(/^\s*={2,}\s*function\s+(\w+)/gm)].map(m => m[1]));
const knots = [...story.mainContentContainer.namedContent.keys()].filter(k => !k.startsWith('global') && !functions.has(k));
for (const knot of knots) {
  try {
    story.ResetState();
    story.ChoosePathString(knot);
    while (true) {
      while (story.canContinue) {
        const line = story.Continue().trim();
        const tags = story.currentTags.length ? '   # ' + story.currentTags.join(' | ') : '';
        if (line || tags) console.log(`[${knot}] ${line}${tags}`);
      }
      if (!story.currentChoices.length) break;
      console.log(`[${knot}]   choices: ${story.currentChoices.map(c => c.text).join(' / ')}`);
      story.ChooseChoiceIndex(0);
    }
  } catch (e) { console.error(`[${knot}] RUNTIME ERROR: ${e.message}`); process.exitCode = 1; }
}
console.log('OK');
