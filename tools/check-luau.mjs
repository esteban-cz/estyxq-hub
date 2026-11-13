import { readdir } from 'node:fs/promises';
import path from 'node:path';
import { root, luau, run } from './luau.mjs';
async function files(dir) {
    const result = [];
    for (const entry of await readdir(dir, {withFileTypes:true})) {
        if (entry.name.startsWith('.') || entry.name === 'node_modules' || entry.name === 'unused-scripts') continue;
        const file = path.join(dir, entry.name);
        if (entry.isDirectory()) result.push(...await files(file));
        else if (entry.name.endsWith('.luau')) result.push(file);
    }
    return result;
}
const sources = (await Promise.all(['src','tests'].map(dir => files(path.join(root,dir))))).flat();
for (const file of sources) run(luau('luau-compile'), ['--null', file]);
console.log('Luau syntax OK: ' + sources.length + ' files.');
