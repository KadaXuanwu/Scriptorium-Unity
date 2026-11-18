# Contributing

This plugin follows the rules of the base. Read
[Scriptorium's CONTRIBUTING.md](https://github.com/KadaXuanwu/Scriptorium/blob/main/CONTRIBUTING.md) first.

What this repo adds:

1. Keep to the plugin contract, version 1 ([docs/PLUGINS.md](https://github.com/KadaXuanwu/Scriptorium/blob/main/docs/PLUGINS.md)).
2. `plugin.ps1` only defines functions when it loads. It starts nothing and changes nothing.
3. A change to a hook has a test in `plugin.test.ps1` and a line in `README.md` in the same pull request.
4. A change to how a run works in Unity goes into `PLAYBOOK.md`.
5. Run `powershell -NoProfile -ExecutionPolicy Bypass -File plugin.test.ps1` before you open the pull request.
