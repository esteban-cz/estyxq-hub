import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { root, luau, run } from './luau.mjs';
const files = ['main.luau','loader.luau','dev-loader.luau','menu.luau','catalog.luau','core/runtime.luau',
    'shared/misc-[Misc]/anti-afk-[Anti-AFK].luau',
    'shared/misc-[Misc]/anti-kick-[Anti-Kick].luau',
    'urban-reloaded-[84448037861644]/combat-[Combat]/silent-aim-[Silent Aim].luau',
    'urban-reloaded-[84448037861644]/visual-[Visuals]/esp-[ESP].luau'];
const sources = Object.fromEntries(await Promise.all(files.map(async file => [file, (await readFile(path.join(root,'src',file),'utf8')).replaceAll('\r\n','\n')])));
function quote(value) {
    let equals = '=';
    while (value.includes(']' + equals + ']')) equals += '=';
    return '[' + equals + '[\n' + value + ']' + equals + ']';
}
const header = 'local sources = {\n' + Object.entries(sources).map(([file,source]) => `[ ${quote(file)} ] = ${quote(source)},`).join('\n') + '\n}\n';
const mock = await readFile(path.join(root,'tests/roblox-mock.luau'),'utf8');
const tests = (await Promise.all(['anti-afk','silent-aim','esp','runtime'].map(name=>readFile(path.join(root,'tests',name+'.luau'),'utf8')))).join('\n');
const temp = await mkdtemp(path.join(tmpdir(), 'estyxq-tests-'));
try {
    const entry = path.join(temp,'run.luau');
    await writeFile(entry, header + mock + '\n' + tests);
    process.stdout.write(run(luau(), [entry]));
} finally {
    if (path.dirname(temp) !== path.resolve(tmpdir())) throw Error('Unexpected test directory.');
    await rm(temp,{recursive:true,force:true});
}
