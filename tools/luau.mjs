import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export function luau(tool = 'luau') {
    const override = tool === 'luau' ? process.env.LUAU_BIN : process.env.LUAU_COMPILE_BIN;
    return override || path.join(root, '.tools', 'luau', tool + (process.platform === 'win32' ? '.exe' : ''));
}
export function run(command, args, options = {}) {
    const result = spawnSync(command, args, {cwd:root, encoding:'utf8', ...options});
    if (result.error?.code === 'ENOENT') throw Error('Luau CLI is missing. Run npm run setup:luau (or set LUAU_BIN and LUAU_COMPILE_BIN).');
    if (result.error) throw result.error;
    if (result.status !== 0 || /SyntaxError:/.test(result.stderr || '')) throw Error((result.stdout || '') + (result.stderr || '') || command + ' failed');
    return result.stdout;
}
