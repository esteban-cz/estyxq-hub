# estyxq Hub

A NextUI hub with Overview, Playground, ESP, and Settings tabs.

| File | Role |
| --- | --- |
| `loader.luau` | Executor entry point. Fetches `main.luau` and supplies the source URLs. |
| `main.luau` | Hub branding, window setup, tabs, settings, and feature controls. |
| `menu.luau` | Your hosted NextUI library source, with the branded startup splash disabled by default. |
| `esp.luau` | R6/R15 skeleton and ring ESP module, fetched when you enable ESP. |

## Run from GitHub

Upload all four `.luau` files together. The loader is configured for:

```lua
ScriptBaseURL = "https://raw.githubusercontent.com/esteban-cz/estyxqHub/main/",
```

Run this in the executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/esteban-cz/estyxqHub/main/loader.luau"))()
```

The loader fetches `main.luau`. Main loads your hosted `menu.luau` UI library, builds the hub, and downloads `esp.luau` when you enable ESP. Launching the loader is enough.

If you change the repository, branch, or folder, update `ScriptBaseURL` in the loader. `MainFile`, `LibraryFile`, and `ESPFile` accept paths beneath that base URL. The loader passes those URLs directly to main.

A file's GitHub **Raw** button shows its source URL. This loader uses public URLs without authentication. A branch such as `main` follows your uploaded changes; a tag or commit selects a specific version.

## Customize the hub

Edit `main.luau` for branding, versions, theme, tabs, and feature settings. Edit `menu.luau` for changes to the UI library itself. Its original MIT license and attribution remain at the top of the file.

The library's startup splash is opt-in through `CreateWindow({ Intro = true })`. Main explicitly sets `Intro = false`, so the hub opens without the splash or its icon-wait delay. Icons still load asynchronously. The library retains its upstream icon assets and NextNotify dependency.

Main can run directly using its own `CONFIG.ScriptBaseURL`. `LibraryURL` and `ESPSourceURL` are optional full-URL overrides; blank or missing values fall back to `menu.luau` and `esp.luau` under the base URL. With no ESP URL, execute `esp.luau` first to register its module before enabling it in the hub.

Main also accepts URL arguments:

```lua
local hub = loadstring(game:HttpGet("YOUR_RAW_MAIN_URL"))({
    ScriptBaseURL = "YOUR_RAW_FOLDER_URL/",
    LibraryURL = "YOUR_RAW_UI_LIBRARY_URL",
    ESPSourceURL = "YOUR_RAW_ESP_URL",
})
```

## Menu behavior

- **RightShift** shows or hides the hub. Settings can change the shortcut.
- Minimizing shows the draggable **estyxq Hub** pill on desktop and touch devices.
- Minimizing keeps ESP active.
- Closing, unloading, or reloading the hub stops its ESP and cleans up the interface.
- Appearance and ESP values are session-only.
- Repeated loader runs replace the previous hub; an older download cannot open a second menu after a newer run.
- Failed main downloads leave an existing hub running.

NextUI documentation: https://diser.me/nextui/