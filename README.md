# estyxq Hub

One loader, one interface, reusable shared sections, and separate game features. Runtime files are plain Luau; Node is only used by contributors to build the catalog and run checks.

## Project layout

```text
src/
  loader.luau                       # Public GitHub entry point
  main.luau                         # Shared window, settings, section mounting, lifecycle
  menu.luau                         # NextUI library fork
  catalog.luau                      # Generated game and shared-section catalog
  dev-loader.luau                   # Local executor-workspace entry point
  core/runtime.luau                 # Cleanup scopes and section error boundaries
  shared/
    misc-[Misc]/
      tab.json
      anti-afk-[Anti-AFK].luau      # Controller + shared Misc section
      anti-kick-[Anti-Kick].luau    # Client-side kick-call toggle
      position-tools-[Position Tools].luau # Coordinates, save/copy, teleport, and reset
    movement-[Movement]/
      tab.json
      fly-[Flight].luau             # Flight modes, speed, and smoothing
      noclip-[Noclip].luau          # Owned collision changes
      jump-[Jump].luau              # Always / Multi / Hold jump modes
  urban-reloaded-[84448037861644]/
    game.json
    combat-[Combat]/
      tab.json
      silent-aim-[Silent Aim].luau  # Controller + Urban Reload Combat section
    visual-[Visuals]/
      tab.json
      esp-[ESP].luau                # Controller + Urban Reload Visuals section
README.md                           # Project documentation stays at the root
tests/                              # Tests stay at the root
tools/                              # Build and validation tools stay at the root
```

`main.luau` has no built-in ESP, Anti-AFK, or game targeting code. Shared and game sections use the same loading, retry, and cleanup API. Feature cards are collapsible and start folded; loading and retry cards remain visible. Overview shows the selected game or loaded script, its version, and quick switches for toggleable sections. Action-only sections get navigation buttons. Controls appear after their section mounts successfully; unavailable sections cannot be enabled from Overview. Feature settings remain in their specific tabs. The menu also has shared Misc and Movement, Settings, and Combat/Visuals when Urban Reload matches.

## Run from GitHub

Upload the runtime files and keep their folder structure. Run:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/esteban-cz/estyxq-hub/main/src/loader.luau"))()
```

Set `ScriptBaseURL` in `src/loader.luau` if the repository, branch, or source folder changes. The loader reads `src/catalog.luau`, selects the game, and passes its metadata and the shared tabs to main. A success message appears in the executor console.

GitHub raw URLs serve pushed files. Uncommitted local edits are available through the local loader below.

## Test local edits before committing

For an executor with `readfile` support:

1. Copy the project into the executor's `workspace/estyxq-hub/` folder, preserving the subfolders. Tests, tools, `.git`, and `.tools` are not needed there.
2. Run:

```lua
loadstring(readfile("estyxq-hub/src/dev-loader.luau"))()
```

`src/dev-loader.luau` reads the current project files through the same loader and application code. Update the copied files and run it again after each edit. Change `ROOT` inside the local loader if your folder has another name. Local mode changes hub source loading; the UI library's upstream icons/notification dependencies can still use HTTP.

For the first Urban Reload smoke test:

1. Open the place `84448037861644` and launch the local loader.
2. Confirm **Combat / Silent Aim**, **Visuals / ESP**, **Movement**, **Misc**, and **Settings** appear. Game and movement features start off; Anti-Kick starts on when supported.
3. Enable Silent Aim and verify the FOV circle; adjust its radius, color, and visibility. Check targeting with the game's weapons.
4. Check team filtering, wall filtering, aim part, distance, and hit chance against the actual game. In Visuals, enable ESP and check upright head rings, flat ground rings, names, distance, and health bars. Try the presets, optional boxes, and a respawn.
5. Enable Anti-AFK and use **Test keepalive**. Minimize and reopen the hub; enabled features should stay active.
6. Rerun the loader, retry a section, and unload the hub. Circles, targeting, and owned listeners should stop without duplicate windows.

The old standalone Silent Aim file had no unload method. If it was already executed in this session, rejoin before testing the replacement.

## Feature behavior and limits

Urban Reload's section keeps the original camera-ray interception approach, with a cached target selection loop, dynamic camera handling, R6/R15 aim parts, team and wall checks, distance limits, hit chance, and an optional FOV circle. Camera ray origin/depth and direction length are preserved. Actual weapon compatibility must be tested in the game; a weapon implementation that does not use these camera methods will not be affected.

Metamethod hooks require executor support. The circle also requires `Drawing.Circle`; missing circle support leaves targeting available and shows a notification. An executor without the required hooks gets a clear enable error.

The dispatcher installs on first enable and is reused across disables, retries, and reloads. Cleanup clears its active controller, disconnects its update listener, and removes its drawing. One inert pass-through dispatcher remains in the session, so cleanup does not overwrite another script's later metamethod hook. Rejoining resets the session entirely.

Anti-AFK owns its input/idle/heartbeat listeners and releases paired simulated input when disabled or unloaded. It does not disable other scripts' idle listeners. Keepalive input depends on VirtualUser support in the executor.

Urban Reload has an owned **Visuals / ESP** section. It starts disabled, uses a 600-stud range and 30 Hz updates, and offers Balanced, Minimal, and Detailed presets. Visibility, Style, Rings, and Performance inline pages contain the controls. Names, distance, health bars, corner boxes, team colors, visibility checks, and outlines are independently configurable.

Head rings stand upright in a camera-facing plane; ground rings remain horizontal. Automatic offsets follow the character's feet and head size, with manual controls available. Labels and boxes use model bounds, and health bars read Humanoid health/max health. Geometry occlusion is optional. This uses normal player/character/team data; it does not assume unverified Urban Reload attributes for armor, crews, or downed states.

ESP needs Drawing.Line. If Drawing.Text is missing, it reports the limitation once and keeps the supported visuals running. Disabling, section retry, reload, or unload releases all owned drawings and listeners. Ring detail and update rate can be lowered independently. Actual executor rendering still needs a live check.

The active game ESP section uses its own controller and does not register the old universal ESP globals.

The original ESP's reported editor errors were on Luau compound assignments and `continue`, which compile in Luau but can be flagged by a standard Lua parser. The active ESP uses ordinary assignments and branches instead.

## Shared tools and Movement

The shared tools adapt AnyCat.Dev's standalone controls into owned hub sections. The standalone GUI and archived source copies have been removed after integration. Syntax checks cover `src/` and `tests/`.

**Movement** is universal and available in unsupported games as well as Urban Reload:

- **Flight**: Velocity and Hybrid modes, speed 10–300, and Low/Medium/High smoothing. Use WASD, Space to rise, and Ctrl to descend. Horizontal character movement can also supply direction. Typing pauses flight input. Flight stops on death or a character change. Disable, retry, or unload destroys its constraints and attachment, restores the humanoid flags/state it changed, and clears flight momentum. Hybrid mode respects external saved-position teleports.
- **Noclip**: follows the current character and newly added parts while enabled. Each part's original collision value is restored when it leaves the character, the character changes, or the feature stops. It starts disabled.
- **Jump**: Always allows repeated jump presses; Multi limits extra airborne jumps and resets the allowance on landing; Hold keeps upward movement while jump is held. Extra-jump count and upward speed are configurable. Typing and flight pause jump modifications. It starts disabled.

Flight uses owned [LinearVelocity](https://create.roblox.com/docs/reference/engine/classes/LinearVelocity) and [AlignOrientation](https://create.roblox.com/docs/reference/engine/classes/AlignOrientation) constraints. All movement is client-side; individual games can correct movement or apply their own rules. Live physics behavior must be checked in the target game.

**Misc / Position Tools** displays coordinates, saves one position and orientation for this session, copies coordinates, teleports to the saved pose with an adjustable height offset, clears the saved pose, and offers a held Reset character button. The default teleport offset is three studs, matching the reference tool. Saved poses are cleared on section retry/unload. It has an Open button on Overview rather than an on/off switch.

**Anti-Kick** preserves the current default of enabling on startup when supported. Disabling or unloading clears the active hook owner. Reloads and retries reuse one dispatcher pair, and partial installation retries do not add another namecall hook. The inert dispatchers are retained so another script's later hooks are preserved. Legacy wrappers from the previous implementation cannot be removed retroactively; rejoin once before testing hook lifetime. This only intercepts client Kick calls and cannot prevent server disconnections.

Suggested smoke test: enable Flight, change its speed/mode, type into a textbox, and disable it; verify normal humanoid movement returns. Enable Noclip, add/equip an accessory, respawn, and disable it; verify collisions return. Try each jump mode, land to refill Multi jumps, and verify disabling removes input effects. Save and teleport to a position, then rerun/unload the loader while movement is active and verify no physics objects or active movement remain.

## Adding games, shared tabs, and sections

A folder under `src/` named `readable-name-[PlaceId]` identifies a game. Add `game.json`:

```json
{
  "Id": "urban-reload",
  "Name": "Urban Reload",
  "Version": "0.2.0",
  "Subtitle": "Urban Reload tools.",
  "GameIds": [10769552054]
}
```

The folder's bracketed number is a PlaceId. Optional `PlaceIds` adds exact places, and `GameIds` registers an entire experience. Exact place matches take priority. `Name`, `Version`, and `Subtitle` set the game script identity; `Id` separates its settings folder. Runtime settings are currently session-only.

Within a game folder, `readable-name-[Tab title]/` becomes a tab. Inside it, `readable-name-[Section title].luau` becomes a section. Optional `tab.json` sets its icon, for example `{"Icon":"swords"}`.

Use the same tab/section naming under `src/shared/` for tools available in every game. Overview and Settings are reserved titles; a game's tab titles must also avoid shared tab titles. Unmatched helper files are ignored by discovery.

After adding, renaming, or changing metadata, run `npm run build` and include the updated `src/catalog.luau` with the sources. Implementation-only edits at an existing section path do not require a rebuild.

## Writing a section

Each section returns a definition with `Mount(context)`. File loading should only define the module. Create controllers and other resources inside Mount, and register cleanup as soon as each resource exists.

```lua
return {
    Icon = "sliders-horizontal",
    Side = "Full", -- Optional: Left, Right, or Full
    Mount = function(context)
        local controller = Feature.new()
        context.AddCleanup(function() controller:Destroy() end)
        context.Controls.Enabled = context.Section:AddToggle({
            Title = "Enable feature", Style = "Switch", Default = false,
            Callback = function(enabled)
                controller:SetEnabled(enabled)
                context.State.Enabled = enabled
            end,
        })
    end,
}
```

| Context field/function | Purpose |
| --- | --- |
| `Section` | Add controls with guarded callbacks. Group controls with `AddTitle` and `AddDivider`; `AddSection` belongs to the tab, not this card. |
| `State`, `Controls` | Fresh tables for this attempt's settings and UI handles. |
| `Area`, `Source` | `Game` or `Shared`, and this section's repository path. |
| `Game`, `PlaceId`, `GameId` | Selected game metadata and current Roblox IDs. `Game` can be nil in the universal hub. |
| `GameState`, `SharedState` | Shared state within the current hub session. |
| `Connect(signal, callback)` | Own a guarded event connection. |
| `Spawn`, `Defer`, `Delay` | Own and cancel background tasks. Delay takes seconds before the callback. |
| `Guard(callback)` | Guard a callback given to an external API. |
| `AddCleanup(callback)` | Register cleanup in reverse order; one error does not prevent other cleanups. |
| `LoadModule(path)` | Load a helper from the same GitHub/local source, with ownership checks after yielding. |
| `IsActive()` | Check whether this attempt is still current after yielding. |
| `Notify(title, content, kind)` | Show a hub notification. |
| `Hub`, `Window`, `Tab`, `Library`, `Scope` | Advanced access to the hub, native UI, and lifecycle. |

Mount may return a cleanup function, register several, or do both. Cleanup should finish without yielding. Independent hooks, listeners, or tasks must be explicitly registered; the framework cannot infer their lifetime. Native calls through Tab, Window, or Library do not automatically gain section ownership.

Set `Overview = false` on a section definition to omit it from quick controls. Otherwise a boolean `State.Enabled` and `Controls.Enabled:Set(...)` make it toggleable; action-only sections get an Open button. Loading/error cards are always expanded, while successfully mounted cards keep their configured collapse defaults.

Section download, compile, evaluation, mount, and guarded callback errors affect that section. Its resources are released, the console shows details, and its card offers Retry. A retry refetches the source and creates fresh State/Controls. Other sections keep working.

Inspect `Hub.Sections[tabTitle][sectionTitle]` for Status, Error, Attempts, Retry(), and Destroy(). State and controls live under `Hub.State.Game` / `Hub.Controls.Game` or `Hub.State.Shared` / `Hub.Controls.Shared`.

RightShift hides/shows the window; minimizing leaves a draggable reopen pill. Closing, unloading, or reloading releases owned features. Required UI/runtime files download and compile before the previous hub retires; execution errors in the new UI library can still fail after replacement.

## Contributor checks

Node.js 22+; no npm dependencies. On Windows/Linux x64:

```sh
npm run setup:luau
npm run build
npm run check
```

Setup downloads the pinned official [Luau 0.746 CLI](https://github.com/luau-lang/luau/releases/tag/0.746), verifies the archive checksum, and stores ignored binaries under `.tools/luau/`. Other platforms can supply `LUAU_BIN` and `LUAU_COMPILE_BIN`.

- `npm run build`: regenerate `src/catalog.luau`.
- `npm test`: catalog validation, controller tests, section lifetimes, reloads, and local/remote loading.
- `npm run check`: ensure the catalog is current, compile active Luau sources, and run tests. Archives are excluded.

GitHub Actions runs these checks on pushes and pull requests. Runtime tests use Roblox/NextUI doubles and cover shared movement, hook ownership, character restoration, and teleport/reset actions. They do not verify live rendering, physics replication, weapon compatibility, or executor behavior.

The NextUI fork retains its MIT header. [NextUI documentation](https://diser.me/nextui/).
