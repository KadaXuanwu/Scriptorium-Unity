# Scriptorium for Unity

A [Scriptorium](https://github.com/KadaXuanwu/Scriptorium) plugin for Unity projects. Each worker copy gets its own
Unity editor, and each run drives that editor with the [Unity CLI](https://docs.unity.com/en-us/unity-cli), so it can
compile, test and play its work.

## What it needs

- Windows 10 or 11, with Scriptorium set up.
- Scriptorium of 2026-11-18 or later (`git pull` in its folder first): it gives a run the environment variables and
  the tool rules of this plugin.
- The project's Unity version, installed with Unity Hub.
- The Unity CLI (`unity`) on the PATH.
- Unity 6.0 or later for a live editor: the CLI reaches a running editor through the `com.unity.pipeline` package, and
  `Setup` adds it to the project. An older project gets no live editor: its runs use `unity test` and `unity run`,
  which start an editor of their own in batch mode.
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

## What each hook does

| Hook | What it does |
| ---- | ------------ |
| `Setup` | Checks that `unity` is on the PATH and that the project's Unity version is in `editors`. Copies `Assets/Scriptorium/Editor/RunEnd.cs` and its `.meta` files into the project. Adds the Smart Merge lines for Unity's YAML files to `.gitattributes` when it has none. Adds `com.unity.pipeline` to the project's `Packages/manifest.json` with `unity pipeline install`, on Unity 6.0 or later. Sets Smart Merge as a merge driver in the main checkout. Returns the files it added or changed |
| `PrepareCopy` | Copies the Asset Store packages that `AssetStore.json` at the project root lists from the main checkout, when that file is there. Sets Smart Merge in the copy |
| `Start` | Opens the copy's editor when it is closed, and waits until `unity status` says it is ready for commands: up to 90 minutes for a first import. Before it opens one, it deletes the copy's scene backup (`Temp/__Backupscenes`), which an editor that was ended by force leaves and which makes the next editor wait in a dialog. An editor that still starts counts as open, so the hook never opens a second one. An editor that waits in a dialog stops the hook with the dialog's title, and the worker's card shows it. Nothing for a project without `com.unity.pipeline` |
| `GetRun` | Gives the run the tool rules for the `unity` commands that drive its editor, `UNITY_PROJECT_PATH` in its environment set to the copy's project, and a sentence that names its editor. No rule lets a run install or remove an editor, sign in, or change the PC |
| `EndRun` | Writes `Temp/ScriptoriumRunEnded`. The editor script reads it and leaves play mode |

A repo with no Unity project gets nothing from any hook.

With several editors open, a `unity` command that names no project takes the only editor that answers, also another
copy's. `UNITY_PROJECT_PATH` is what keeps each run on its own editor.

`AssetStore.json` lists the packages that are not in git:

```json
{ "Packages": [{ "Root": "Assets/SomePack", "Probe": "Assets/SomePack/Scripts/Main.cs" }] }
```

A copy that already has the `Probe` file gets nothing.

## Limits

- An editor that a run of another repo opened stays open beside the copy's own. Close it by hand if memory gets tight.
- A disabled worker's editors stay open.
- After the project moves to another Unity version, close each worker's editor and bring its copy to the new main before
  the worker goes on: an open editor of the old version does not change by itself.

## Test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugin.test.ps1
```

## Licence

MIT. See [LICENSE](LICENSE).
