# Playbook: Unity

What a run adds in a Unity project, after the base's playbook. The project's own playbook comes after this one and
wins where the two differ.

## Your editor

Each worker copy has its own Unity editor. The worker script opens it before the run. You drive it with the Unity CLI
(`unity`), which reaches a running editor through the project's `com.unity.pipeline` package.

1. `UNITY_PROJECT_PATH` in your environment names your copy's project, and each `unity` command takes its editor from
   it. Never pass `--project-path`, `--port` or `--pid` of another editor, and never unset the variable. A command that
   names no project takes any editor that answers, also another worker's.
2. `unity status` shows your editor: `ready`, or what stops it. The editor may still import the project:
   `unity status --until-ready` waits for it.
3. The commands come from the project's package, so read them from your editor and not from memory.
   `unity command --detail compact` lists them, `unity command --query <word>` finds one, and
   `unity command <group> <name> --help` gives its parameters.
   `unity skill show` prints Unity's own guide; `unity skill show --list` names its other files, and
   `unity skill show --path references/<file>` prints one. Where that guide names a command that your editor does not
   list, your editor is right.
4. A command's own flags go after `--`: `unity command console get -- --level error --tail 20`. Before the `--`, the
   CLI takes a flag of the same name for itself (`--timeout` is one).
5. Add `--result-only` to get only the command's answer as JSON. Exit code 0 is success. A failed command also writes
   an error to the editor's console, so expect that entry there.
6. If the job's message says the project has no `com.unity.pipeline` package, no command reaches an editor. Use
   `unity test` and `unity run`: each starts an editor of its own in batch mode.

## Before git changes a file

Git that changes the open scene's file (checkout, rebase, reset) makes Unity ask "reload scene?" in a dialog. Before
each of these, open an empty unsaved scene:

```bash
unity command script eval 'UnityEditor.SceneManagement.EditorSceneManager.NewScene(UnityEditor.SceneManagement.NewSceneSetup.EmptyScene, UnityEditor.SceneManagement.NewSceneMode.Single);'
```

## The checks

Climb only as far as the change needs. A change to docs alone needs none.

| # | Check | How | Catches |
| - | ----- | --- | ------- |
| 1 | Editor compile | `unity recompile`: it prints each error with its file and line, and exits with 6 when one is there | syntax, types, asset import errors |
| 2 | Tests | `unity command test run --detach`, then `unity job wait <job id>` (the default mode is `editor`); some only: `unity command test run -- --filter <part of a name>` | logic |
| 3 | Play it | below | wiring, scene setup |

- `unity command console status` gives the counts, the compile flag and a `cursor`, with no entries. Note the cursor
  before a step, and read with `unity command console get -- --level error --since <cursor>` after it: the console
  keeps the entries of earlier work.
- A test run right after a compile error runs the last assembly that built.
- Play a check when the view or the wiring changed. Name the checks you ran in the PR's **Verified** line.

**Play it.** An unfocused editor does not tick play mode by itself, and a screenshot of a frozen game looks like a
live one. So:

```bash
unity command editor set_auto_tick
unity command editor.playmode start
unity status --until-ready
unity command job wait -- --condition '{"member":"UnityEngine.Time.frameCount","op":"changed"}' --timeout 10
```

The last answer must say `"met": true`: the frames advance. Read the game's state and take the pictures, then put it
all back:

```bash
unity command editor.playmode stop
unity command editor set_auto_tick -- --enabled false
```

**Read and change state** with `unity command script eval '<C#>'`, in edit mode and in play mode. The code is a
script: statements, with a `return` for the value that comes back. It reaches the project's own types and takes
modern C#. For more than a line, write a `.cs` file in a folder that git ignores (`Temp/`) and pass
`-- --file Temp/<name>.cs`: the path is from the project folder.

**Pictures.** The path is from the project folder: write under `Temp/`, never under `Assets/` unless the project's
playbook names a folder there.

- The game: `unity command capture game_view -- --output-path Temp/Screenshots/<name>.png`. It shows the HUD too, and
  it needs no focus.
- From a spot of your choice: add a camera of your own with `script eval` (a new `GameObject` with
  `hideFlags = HideFlags.DontSave` and an enabled `Camera`, placed and aimed), capture with
  `-- --camera <its name> --output-path ...`, and destroy it. A disabled camera is not found.
- An editor window: `unity command capture editor_window -- --window "<its title>" --output-path ...`.
- A menu item opens a window or runs a tool: `unity command editor invoke_menu -- --path "<menu path>"`.

A test tweak can leak into `ProjectSettings` (`Time.timeScale`): put it back, and check `git diff` of
`ProjectSettings` before you commit.

## Traps

- **A `script eval` waits 30 s.** Then the command ends with exit code 14, and the code may still run in the editor.
  For longer code, raise the wait before the `--`: `unity command script eval --timeout 120 -- --file Temp/<name>.cs`.
  After a timeout, run `unity status --until-ready` before you send anything else, and never send the same code again
  without a check of what it did.
- **A dialog blocks the editor.** `unity status` then shows `blockedBy` with the dialog's title, and each command
  waits until its timeout. Do not open one: no `EditorUtility.DisplayDialog`, no unsigned `.unitypackage`, no git
  change to the open scene. With CLI 1.0.0 and package 1.0.0 no command answers a dialog. Look for one in your
  editor's list (`unity command --query dialog`); if it has none, do the work that needs no editor, and say in the PR
  which dialog a person must answer.
- **After play mode starts or code compiles**, the editor does not answer for a few seconds.
  `unity status --until-ready` waits for it.
- **A string in inline code needs a shell that keeps its quotes.** Bash keeps `"..."` inside `'...'`. Windows
  PowerShell 5.1 drops them: use `-- --file` there.
- **Never run `console clear`** on an editor that a person uses too: it empties their Console window.

## Crashes

The editor crashed or does not answer: `unity status` then finds no editor for your project. Open it again with
`unity open "$UNITY_PROJECT_PATH" --until-ready`, and try again. Between runs the worker script opens a closed editor
itself. If it stays down, carry on with the work that does not need it, and come back to the checks.
