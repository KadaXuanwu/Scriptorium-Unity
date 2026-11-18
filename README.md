# Scriptorium for Unity

A [Scriptorium](https://github.com/KadaXuanwu/Scriptorium) plugin for Unity projects. Each worker copy gets its own
Unity editor, and each run gets [MCP for Unity](https://github.com/CoplayDev/unity-mcp) pinned to that editor, so it can
compile, test and play its work.

## What it needs

- Windows 10 or 11, with Scriptorium set up.
- The project's Unity version, installed with Unity Hub.
- [uv](https://docs.astral.sh/uv/): `uvx` starts the MCP for Unity server.
- The MCP for Unity package in the Unity project.
- Memory for one editor for each worker, and one for each other repo with a Unity project that a ticket names.

The Unity project is the repo root or a folder one level down.

## Use it

In the project's `scriptorium.json`:

```json
"plugins": { "unity": {} }
```

Then run Scriptorium's `setup.ps1` again. It clones this plugin, runs its `Setup` and lists the files to commit.

## Settings

Each key of the entry is a setting. A PC can set its own in `.queue/settings.json`, under `plugins.unity`.

| Setting | Default | What |
| ------- | ------- | ---- |
| `editors` | `C:\Program Files\Unity\Hub\Editor` | The folder that holds one folder for each Unity version |
| `mcpVersion` | `10.3.0` | The version of the MCP for Unity server (`mcpforunityserver` on PyPI) that runs use |

## What each hook does

| Hook | What it does |
| ---- | ------------ |
| `Setup` | Checks that the project's Unity version is in `editors`. Copies `Assets/Scriptorium/Editor/RunEnd.cs` and its `.meta` files into the project. Adds the Smart Merge lines for Unity's YAML files to `.gitattributes` when it has none. Sets Smart Merge as a merge driver in the main checkout. Returns the files it added |
| `PrepareCopy` | Copies the Asset Store packages that `AssetStore.json` at the project root lists from the main checkout, when that file is there. Sets Smart Merge in the copy |
| `Start` | Opens the copy's editor when it is closed, and waits until MCP for Unity says it is ready: up to 90 minutes for a first import |
| `GetRun` | Gives the run the `UnityMCP` server, pinned to the copy's `Assets`, the tool rule `mcp__UnityMCP`, and the name of its editor |
| `EndRun` | Writes `Temp/ScriptoriumRunEnded`. The editor script reads it and leaves play mode |

A repo with no Unity project gets nothing from any hook.

`AssetStore.json` lists the packages that are not in git:

```json
{ "Packages": [{ "Root": "Assets/SomePack", "Probe": "Assets/SomePack/Scripts/Main.cs" }] }
```

A copy that already has the `Probe` file gets nothing.

## Limits

- An editor that a run of another repo opened stays open beside the copy's own. Close it by hand if memory gets tight.
- A disabled worker's editors stay open.

## Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugin.test.ps1
```

## Licence

MIT. See [LICENSE](LICENSE).
