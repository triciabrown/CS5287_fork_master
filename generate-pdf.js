// generate-pdfs.js
// Usage:   node generate-pdfs.js [rootDir]
// Example: node generate-pdfs.js . 

const { readdir, stat } = require('fs').promises;
const { spawnSync } = require('child_process');
const { join, extname } = require('path');
const fs = require('fs');
const path = require('path');

fs.mkdirSync('.output', { recursive: true });

async function traverseAndConvert(dir) {
  const entries = await readdir(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = join(dir, entry.name);

    if (entry.isDirectory()) {
      await traverseAndConvert(fullPath);
    }
    else if (entry.isFile() && entry.name.endsWith('.marp.md')) {
      const outPdf = path.resolve('.output', fullPath.replace(/\.marp\.md$/, '.pptx'));
      console.log(`⏳  Generating PDF for ${fullPath}`);
        const result = spawnSync(
            'npx marp --pptx --theme ./doc/default.scss --allow-local-files ' +
            `-o "${outPdf}" "${fullPath}"`,
            { stdio: 'inherit', shell: true }
        );

      if (result.error) {
        console.error(`❌  Error processing ${fullPath}:`, result.error);
      }
      else {
        console.log(`✅  ${outPdf} created.`);
      }
    }
  }
}

(async () => {
  const root = process.argv[2] || '.';
  try {
    const stats = await stat(root);
    if (!stats.isDirectory()) {
      console.error(`Error: ${root} is not a directory`);
      process.exit(1);
    }
    await traverseAndConvert(root);
    console.log('All done!');
  }
  catch (err) {
    console.error('Unexpected error:', err);
    process.exit(1);
  }
})();
