import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { buildCatalog } from '../tools/build-catalog.mjs';
import { luau, run, root } from '../tools/luau.mjs';

async function fixture(t, files) {
    const dir = await mkdtemp(path.join(tmpdir(), 'estyxq-catalog-'));
    t.after(async () => {
        if (path.dirname(dir) !== path.resolve(tmpdir())) throw Error('Unexpected fixture directory.');
        await rm(dir, {recursive:true, force:true});
    });
    for (const [name, value] of Object.entries(files)) {
        const target = path.join(dir, name);
        await mkdir(path.dirname(target), {recursive:true});
        await writeFile(target, value);
    }
    return dir;
}

test('catalog is deterministic and the committed output is current', async () => {
    const sourceRoot = path.join(root, 'src');
    const first = await buildCatalog(sourceRoot);
    assert.equal(await buildCatalog(sourceRoot), first);
    assert.equal(await readFile(path.join(sourceRoot, 'catalog.luau'), 'utf8'), first);
});

test('discovers game/tab/section metadata and escapes valid Luau without executing standalone downloads', async t => {
    const dir = await fixture(t, {
        'demo-[123]/game.json': JSON.stringify({Name:'Hero "One"', Subtitle:'Line\nControl\u0001', GameIds:[456], PlaceIds:[789]}),
        'demo-[123]/combat-[Combat]/feature-[Silent Aim].luau': 'return {}',
        'demo-[123]/combat-[Combat]/downloaded.luau': 'error("Must not execute")',
        'demo-[123]/standalone.luau': 'error("Must not execute")',
    });
    const catalog = await buildCatalog(dir);
    assert.match(catalog, /Title = "Combat"/);
    assert.match(catalog, /Title = "Silent Aim"/);
    for (const id of [123,456,789]) assert.ok(catalog.includes(String(id)));
    assert.ok(!catalog.includes('downloaded.luau') && !catalog.includes('standalone.luau'));
    const output = path.join(dir, 'catalog.luau');
    await writeFile(output, catalog);
    run(luau('luau-compile'), ['--null', output]);
});

for (const [name, files, error] of [
    ['invalid metadata shape', {'demo-[100]/game.json':'[]'}, /Expected a JSON object/],
    ['duplicate places', {'one-[100]/game.json':'{}', 'two-[200]/game.json':'{"PlaceIds":[100]}'}, /Duplicate PlaceId/],
    ['duplicate experiences', {'one-[100]/game.json':'{"GameIds":[1]}', 'two-[200]/game.json':'{"GameIds":[1]}'}, /Duplicate GameId/],
    ['reserved tabs', {'demo-[100]/settings-[Settings]/x-[X].luau':'return {}'}, /Invalid or duplicate tab title/],
    ['oversized IDs', {'demo-[999999999999999999999999]/game.json':'{}'}, /Invalid place ID/],
    ['duplicate section titles', {'demo-[100]/tab-[Tools]/a-[X].luau':'', 'demo-[100]/tab-[Tools]/b-[X].luau':''}, /Invalid or duplicate section/],
]) test('rejects ' + name, async t => assert.rejects(buildCatalog(await fixture(t, files)), error));

test('discovers universal sections and excludes archives from the catalog', async t => {
    const dir=await fixture(t,{
        'shared/misc-[Misc]/anti-afk-[Anti-AFK].luau':'return {}',
        'unused-scripts/esp.luau':'error("Do not load")',
        'unused-scripts/old-[999]/tab-[Old]/x-[X].luau':'error("Do not load")',
    });
    const catalog=await buildCatalog(dir);
    assert.match(catalog,/SharedTabs =/);
    assert.match(catalog,/shared\/misc-\[Misc\]\/anti-afk-\[Anti-AFK\]\.luau/);
    assert.ok(!catalog.includes('unused-scripts') && !catalog.includes('esp.luau'));
});
test('game tabs cannot collide with a shared tab', async t => {
    const dir=await fixture(t,{
        'shared/misc-[Misc]/a-[A].luau':'',
        'demo-[100]/misc-[Misc]/b-[B].luau':'',
    });
    await assert.rejects(buildCatalog(dir),/Invalid or duplicate tab title/);
});
