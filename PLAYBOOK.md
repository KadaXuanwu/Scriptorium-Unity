# Playbook: Unity

What a run adds in a Unity project, after the base's playbook. The project's own playbook comes after this one and
wins where the two differ.

## Your editor

Each worker copy has its own Unity editor. The worker script opens it before the run, and MCP for Unity is pinned to
it.

1. The job's message names your editor (`Unity@<hash>`). Make `set_active_instance` to it your first MCP for Unity
   call, and call it again after any reconnect. Never select another editor. The server's pin alone is not enough: a
   session that starts while only another editor answers selects that one for good.
2. Read `mcpforunity://project/info`: it must show your copy. The editor may still import the project: read
   `mcpforunity://editor/state` and wait until it is ready.
3. A repo with no Unity project has no MCP for Unity. The job's message then names no editor.

## Before git changes a file

Git that changes the open scene's file (checkout, rebase, reset) makes Unity ask "reload scene?" in a dialog, and every
MCP call hangs until a human clicks it. Before each of these, open an empty unsaved scene with `execute_code`:

```csharp
UnityEditor.SceneManagement.EditorSceneManager.NewScene(
    UnityEditor.SceneManagement.NewSceneSetup.EmptyScene, UnityEditor.SceneManagement.NewSceneMode.Single);
```

## The checks

Climb only as far as the change needs. A change to docs alone needs none.

| # | Check | How | Catches |
| - | ----- | --- | ------- |
| 1 | Editor compile | `refresh_unity(compile="request")`, then `read_console(types=["error"])` | syntax, types, asset import errors |
| 2 | Tests | `run_tests(mode="EditMode")`, then `get_test_job` | logic |
| 3 | Play it | `manage_editor(action="play")`, read the state with `execute_code`, then `manage_editor(action="stop")` | wiring, scene setup |

- Clear the console before a refresh whose result matters (`read_console(action="clear")`): it keeps the errors of an
  earlier compile.
- A test run right after a compile error runs the last assembly that built.
- Play a check when the view or the wiring changed. Name the checks you ran in the PR's **Verified** line.
- An unfocused editor does not tick play mode unless `Application.runInBackground` is true. A test tweak can leak into
  `ProjectSettings` (`runInBackground`, `Time.timeScale`): put them back, and check `git diff` of `ProjectSettings`
  before you commit.

## Traps

- **The first MCP call after a package resolve or a domain reload fails** with a socket error. Send it once more.
- **An `execute_code` that times out may have stopped the editor.** Read `mcpforunity://editor/state` and wait until it
  answers before you send anything else. Keep each call short.
- **The bridge can go away for a few seconds after a test run.** Wait, then read `mcpforunity://instances` again.
- **An unsigned `.unitypackage` opens a dialog** for each package, and MCP hangs until a human clicks. Never import one.
- **Screenshots:** `manage_camera(action="screenshot")` writes only inside the project. Pass
  `output_folder="Temp/Screenshots"`, never a folder under `Assets/`.

## Crashes

The editor crashed, or MCP is gone: start it again with `Unity.exe -projectPath <your copy's project>` and try again.
Between runs the worker script opens a closed editor itself. If it stays down, carry on with the work that does not
need it, and come back to the checks.
