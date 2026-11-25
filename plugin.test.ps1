# Checks the hooks of plugin.ps1 on a fake project, with no editor and no network:
#   powershell -NoProfile -ExecutionPolicy Bypass -File plugin.test.ps1 (prints ok or throws).
$ErrorActionPreference = 'Stop'

function Assert-Equal($actual, $expected, [string] $what) {
    if ("$actual" -ne "$expected") {
        throw "${what}: expected '$expected', got '$actual'"
    }
}

# Loaded as the base loads a plugin (Scriptorium's docs/PLUGINS.md): in a module of its own.
$module = New-Module -ArgumentList (Join-Path $PSScriptRoot 'plugin.ps1') -ScriptBlock {
    param($file)
    $Hooks = . $file
    Export-ModuleMember -Variable Hooks
}
$hooks = & $module { $Hooks }

$root = Join-Path ([IO.Path]::GetTempPath()) "scriptorium-unity-test-$PID"
$said = New-Object System.Collections.ArrayList
function New-Context([string] $project, [string] $copy, $settings = @{}) {
    return @{ Api = 1; Project = $project; Copy = $copy; Worker = 1; QueueDir = "$copy\.queue"; Settings = $settings
        Report = { param($text) [void]$said.Add($text) }; Log = { param($text) [void]$said.Add($text) } }
}

try {
    # A repo with the Unity project one folder down, an editors folder with its version, and a stand-in for the Unity
    # CLI on the PATH: `pipeline install` writes the manifest, `status` prints the file the test names.
    $repo = Join-Path $root 'Game'
    $editors = Join-Path $root 'Editors'
    New-Item -ItemType Directory -Force "$repo\Client\ProjectSettings", "$repo\Client\Packages", "$repo\Client\Temp", "$editors\6000.7.1f1\Editor", "$root\bin" | Out-Null
    Set-Content "$repo\Client\ProjectSettings\ProjectVersion.txt" "m_EditorVersion: 6000.7.1f1`nm_EditorVersionWithRevision: 6000.7.1f1 (abc)" -Encoding utf8
    Set-Content "$editors\6000.7.1f1\Editor\Unity.exe" '' -Encoding utf8
    Set-Content "$root\bin\unity.cmd" @'
@echo off
if "%1"=="pipeline" echo { "dependencies": { "com.unity.pipeline": "1.0.0" } } > "%FAKE_MANIFEST%"
if "%1"=="status" type "%FAKE_STATUS%"
if "%1"=="close" echo %2> "%FAKE_CLOSED%"
'@ -Encoding ascii
    $env:PATH = "$root\bin;$env:PATH"
    $env:FAKE_MANIFEST = "$repo\Client\Packages\manifest.json"
    $env:FAKE_STATUS = "$root\status.json"
    $env:FAKE_CLOSED = "$root\closed.txt"
    & git init -q $repo
    $settings = @{ editors = $editors }
    $client = "$repo\Client".Replace('\', '/')

    # Setup: the editor script under the project, the YAML lines at the repo root and the Pipeline package in the
    # manifest, once; Smart Merge in the checkout.
    $added = @(& $hooks.Setup (New-Context $repo $repo $settings))
    Assert-Equal ($added -join ',') 'Client/Assets/Scriptorium.meta,Client/Assets/Scriptorium/Editor.meta,Client/Assets/Scriptorium/Editor/RunEnd.cs,Client/Assets/Scriptorium/Editor/RunEnd.cs.meta,.gitattributes,Client/Packages/manifest.json' 'the files Setup adds'
    Assert-Equal (Test-Path "$repo\Client\Assets\Scriptorium\Editor\RunEnd.cs") $true 'the editor script'
    Assert-Equal ((Get-Content "$repo\.gitattributes") -contains '*.unity merge=unityyamlmerge') $true 'the YAML lines'
    Assert-Equal (& $module { param($project) Test-Pipeline $project } $client) $true 'the Pipeline package in the manifest'
    Assert-Equal (& git -C $repo config merge.unityyamlmerge.recursive) 'binary' 'Smart Merge in the checkout'
    Assert-Equal @(& $hooks.Setup (New-Context $repo $repo $settings)).Count 0 'a second Setup adds nothing'
    $threw = ''
    try { & $hooks.Setup (New-Context $repo $repo @{ editors = "$root\none" }) } catch { $threw = "$_" }
    Assert-Equal ($threw -like 'Unity 6000.7.1f1 is not in *') $true 'an editors folder without the version'

    # PrepareCopy: a copy with no AssetStore.json gets Smart Merge and nothing else.
    $copy = Join-Path $root 'Game-w1'
    & git init -q $copy
    & $hooks.PrepareCopy (New-Context $repo $copy $settings)
    Assert-Equal (& git -C $copy config merge.unityyamlmerge.name) 'Unity SmartMerge' 'Smart Merge in the copy'

    # The packages the main checkout has: each copy gets the ones its own AssetStore.json lists, at PrepareCopy and at
    # each Start; one that only the main checkout's list names stays out (an older branch, whose manifest lacks what the
    # package needs).
    $list = '{ "Packages": [{ "Root": "Assets/Old", "Probe": "Assets/Old/a.txt" }, { "Root": "Assets/New", "Probe": "Assets/New/b.txt" }] }'
    New-Item -ItemType Directory -Force "$repo\Client\Assets\Old", "$repo\Client\Assets\New", "$copy\Client\Assets" | Out-Null
    Set-Content "$repo\Client\Assets\Old\a.txt", "$repo\Client\Assets\New\b.txt", "$repo\Client\Assets\New.meta" '' -Encoding ascii
    Set-Content "$repo\Client\AssetStore.json" $list -Encoding ascii
    Set-Content "$copy\Client\AssetStore.json" '{ "Packages": [{ "Root": "Assets/Old", "Probe": "Assets/Old/a.txt" }] }' -Encoding ascii
    & $hooks.PrepareCopy (New-Context $repo $copy $settings)
    Assert-Equal "$(Test-Path "$copy\Client\Assets\Old\a.txt")$(Test-Path "$copy\Client\Assets\New")" 'TrueFalse' 'PrepareCopy copies what the copy lists'
    Set-Content "$copy\Client\AssetStore.json" $list -Encoding ascii
    Set-Content $env:FAKE_STATUS '{ "data": { "instances": [{ "state": "ready" }] } }' -Encoding ascii
    & $hooks.Start (New-Context $repo $copy $settings)
    Assert-Equal "$(Test-Path "$copy\Client\Assets\New\b.txt")$(Test-Path "$copy\Client\Assets\New.meta")" 'TrueTrue' 'Start copies a package added later'

    # GetRun: the Unity CLI's commands, aimed at the checkout's own project; nothing for a repo without Unity.
    $run = & $hooks.GetRun (New-Context $repo $repo)
    Assert-Equal $run.Env.UNITY_PROJECT_PATH "$repo\Client" 'the run''s own project'
    Assert-Equal "$($run.Env.UNITY_NON_INTERACTIVE)$($run.Env.UNITY_NO_BANNER)$($run.Env.UNITY_NO_PAGER)" '111' 'no prompt, banner or pager'
    Assert-Equal ($run.AllowedTools -contains 'Bash(unity command:*)') $true 'the tool rule for editor commands'
    Assert-Equal @($run.AllowedTools | Where-Object { $_ -notlike 'Bash(unity ?*:`*)' }).Count 0 'each rule names one unity command'
    Assert-Equal ($run.Prompt -like "Your Unity editor is the one that has $repo\Client open.*") $true 'the prompt names the editor'
    Assert-Equal $run.ContainsKey('McpServers') $false 'no MCP server'
    $plain = Join-Path $root 'Tools'
    New-Item -ItemType Directory -Force $plain | Out-Null
    Assert-Equal (& $hooks.GetRun (New-Context $repo $plain)).Count 0 'a repo without a Unity project gets nothing'

    # The wait for the editor: ready returns, a dialog throws with its title.
    $said.Clear()
    Set-Content $env:FAKE_STATUS '{ "data": { "instances": [{ "state": "ready" }] } }' -Encoding ascii
    & $module { param($project, $ctx) Wait-UnityReady $project $ctx } $client (New-Context $repo $repo)
    Assert-Equal $said.Count 0 'a ready editor needs no report'
    Set-Content $env:FAKE_STATUS '{ "data": { "instances": [{ "state": "starting", "blockedBy": { "reason": "dialog", "dialogs": [{ "title": "Scene Backup Detected" }] } }] } }' -Encoding ascii
    $threw = ''
    try { & $module { param($project, $ctx) Wait-UnityReady $project $ctx } $client (New-Context $repo $repo) } catch { $threw = "$_" }
    Assert-Equal $threw 'its Unity editor waits in a dialog that a person must answer: Scene Backup Detected' 'an editor in a dialog'
    # No editor during the wait (it closed, or never opened): the wait opens it. Here the default editors folder has no
    # Unity 6000.7.1f1, so the open throws.
    Set-Content $env:FAKE_STATUS '{ "data": { "instances": [] } }' -Encoding ascii
    $threw = ''
    try { & $module { param($project, $ctx) Wait-UnityReady $project $ctx } $client (New-Context $repo $repo @{ editors = "$root\none" }) } catch { $threw = "$_" }
    Assert-Equal ($threw -like 'Unity 6000.7.1f1 is not in *') $true 'the wait opens a closed editor'

    # A project older than Unity 6.0: no Pipeline package, so no editor opens, and the run gets the batch mode commands.
    $old = Join-Path $root 'Old'
    New-Item -ItemType Directory -Force "$old\ProjectSettings", "$old\Packages", "$editors\2022.3.62f3\Editor" | Out-Null
    Set-Content "$old\ProjectSettings\ProjectVersion.txt" 'm_EditorVersion: 2022.3.62f3' -Encoding utf8
    Set-Content "$old\Packages\manifest.json" '{ "dependencies": { } }' -Encoding utf8
    Set-Content "$editors\2022.3.62f3\Editor\Unity.exe" '' -Encoding utf8
    & git init -q $old
    Assert-Equal (@(& $hooks.Setup (New-Context $old $old $settings)) -contains 'Packages/manifest.json') $false 'no Pipeline package before Unity 6.0'
    & $hooks.Start (New-Context $old $old $settings)
    Assert-Equal ((& $hooks.GetRun (New-Context $old $old)).Prompt -like '*no com.unity.pipeline package*unity test and unity run*') $true 'the batch mode prompt'

    # Start: nothing for a repo without a Unity project. EndRun: the marker the editor script reads.
    & $hooks.Start (New-Context $repo $plain)
    & $hooks.EndRun (New-Context $repo $repo)
    Assert-Equal (Test-Path "$repo\Client\Temp\ScriptoriumRunEnded") $true 'the run-end marker'
    & $hooks.EndRun (New-Context $repo $plain)

    # An editor is open while it holds the project's lock; with no lock held and no process, it is closed.
    Assert-Equal (& $module { param($project) Test-ProjectOpen $project } $client) $false 'no editor on the project'
    Set-Content "$repo\Client\Temp\UnityLockfile" '' -Encoding utf8
    $held = [System.IO.File]::Open("$repo\Client\Temp\UnityLockfile", 'Open', 'ReadWrite', 'None')
    try {
        Assert-Equal (& $module { param($project) Test-ProjectOpen $project } $client) $true 'an editor holds the lock'
        # Close: the copy's own editor, by its path.
        & $hooks.Close (New-Context $repo $repo)
        Assert-Equal (Get-Content $env:FAKE_CLOSED) "$repo\Client" 'Close closes the copy''s editor'
    } finally {
        $held.Dispose()
    }
    Remove-Item $env:FAKE_CLOSED
    & $hooks.Close (New-Context $repo $repo)
    & $hooks.Close (New-Context $repo $plain)
    Assert-Equal (Test-Path $env:FAKE_CLOSED) $false 'no Close with no editor open, or with no Unity project'

    # A project at the repo root.
    New-Item -ItemType Directory -Force "$plain\ProjectSettings" | Out-Null
    Copy-Item "$repo\Client\ProjectSettings\ProjectVersion.txt" "$plain\ProjectSettings\"
    Assert-Equal (& $hooks.GetRun (New-Context $plain $plain)).Env.UNITY_PROJECT_PATH $plain 'a project at the root'
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'ok'
