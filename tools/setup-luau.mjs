// Official Luau CLI release. Version and archive hashes are kept together.
import { mkdir, mkdtemp, writeFile, copyFile, chmod, rm } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { root } from './luau.mjs';
const version = '0.746';
const releases = {
    win32: ['windows', 'e149fdb4fe78a52ce457fbd40741484eaab1dbf9907e7f878c6d8a9a3dac2ddd'],
    linux: ['ubuntu', '30f11c9cde8be2dc0e3066d210705532aac3726a2db89a6c5078080b6faa6cf8'],
};
const release = releases[process.platform];
if (!release || process.arch !== 'x64') throw Error('Automatic Luau setup supports Windows/Linux x64. Set LUAU_BIN and LUAU_COMPILE_BIN for another platform.');
const temp = await mkdtemp(path.join(tmpdir(), 'estyxq-luau-'));
try {
    const url = `https://github.com/luau-lang/luau/releases/download/${version}/luau-${release[0]}.zip`;
    const response = await fetch(url);
    if (!response.ok) throw Error(`Luau download failed: HTTP ${response.status}`);
    const data = Buffer.from(await response.arrayBuffer());
    if (createHash('sha256').update(data).digest('hex') !== release[1]) throw Error('Luau archive checksum mismatch.');
    const archive = path.join(temp, 'luau.zip'), unpacked = path.join(temp, 'unpacked');
    await writeFile(archive, data);
    if (process.platform === 'win32') {
        execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', 'Expand-Archive -LiteralPath $env:ESTYXQ_LUAU_ARCHIVE -DestinationPath $env:ESTYXQ_LUAU_UNPACKED'], {
            env: {...process.env, ESTYXQ_LUAU_ARCHIVE:archive, ESTYXQ_LUAU_UNPACKED:unpacked}, stdio:'inherit', windowsHide:true,
        });
    } else execFileSync('unzip', ['-q', archive, '-d', unpacked], {stdio:'inherit'});
    const target = path.join(root, '.tools', 'luau');
    await mkdir(target, {recursive:true});
    for (const tool of ['luau', 'luau-compile']) {
        const name = tool + (process.platform === 'win32' ? '.exe' : '');
        await copyFile(path.join(unpacked, name), path.join(target, name));
        if (process.platform !== 'win32') await chmod(path.join(target, name), 0o755);
    }
    console.log(`Installed Luau ${version} in .tools/luau.`);
} finally {
    if (path.dirname(temp) !== path.resolve(tmpdir())) throw Error('Unexpected temporary directory.');
    await rm(temp, {recursive:true, force:true});
}
