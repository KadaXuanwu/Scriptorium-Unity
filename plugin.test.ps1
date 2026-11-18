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
    # A repo with the Unity project one folder down, an editors folder with its version, and uvx on the PATH.
    $repo = Join-Path $root 'Game'
    $editors = Join-Path $root 'Editors'
    New-Item -ItemType Directory -Force "$repo\Client\ProjectSettings", "$repo\Client\Temp", "$editors\6000.7.1f1\Editor", "$root\bin" | Out-Null
    Set-Content "$repo\Client\ProjectSettings\ProjectVersion.txt" "m_EditorVersion: 6000.7.1f1`nm_EditorVersionWithRevision: 6000.7.1f1 (abc)" -Encoding utf8
    Set-Content "$editors\6000.7.1f1\Editor\Unity.exe" '' -Encoding utf8
    Set-Content "$root\bin\uvx.cmd" '@echo off' -Encoding ascii
    $env:PATH = "$root\bin;$env:PATH"
    & git init -q $repo
    $settings = @{ editors = $editors }

    # Setup: the editor script under the project and the YAML lines at the repo root, once; Smart Merge in the checkout.
    $added = @(& $hooks.Setup (New-Context $repo $repo $settings))
    Assert-Equal ($added -join ',') 'Client/Assets/Scriptorium.meta,Client/Assets/Scriptorium/Editor.meta,Client/Assets/Scriptorium/Editor/RunEnd.cs,Client/Assets/Scriptorium/Editor/RunEnd.cs.meta,.gitattributes' 'the files Setup adds'
    Assert-Equal (Test-Path "$repo\Client\Assets\Scriptorium\Editor\RunEnd.cs") $true 'the editor script'
    Assert-Equal ((Get-Content "$repo\.gitattributes") -contains '*.unity merge=unityyamlmerge') $true 'the YAML lines'
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

    # GetRun: MCP for Unity pinned to the checkout's Assets, at the setting's version; nothing for a repo without Unity.
    $run = & $hooks.GetRun (New-Context $repo $repo @{ mcpVersion = '9.9.9' })
    Assert-Equal $run.McpServers.UnityMCP.env.UNITY_MCP_DEFAULT_INSTANCE "$($repo.Replace('\', '/'))/Client/Assets" 'the pinned project'
    Assert-Equal ($run.McpServers.UnityMCP.args -join ' ') '--from mcpforunityserver==9.9.9 mcp-for-unity' 'the server version'
    Assert-Equal ((& $hooks.GetRun (New-Context $repo $repo)).McpServers.UnityMCP.args[1]) 'mcpforunityserver==10.3.0' 'the default version'
    Assert-Equal "$($run.AllowedTools)" 'mcp__UnityMCP' 'the tools'
    $plain = Join-Path $root 'Tools'
    New-Item -ItemType Directory -Force $plain | Out-Null
    Assert-Equal (& $hooks.GetRun (New-Context $repo $plain)).Count 0 'a repo without a Unity project gets nothing'

    # Start: nothing for a repo without a Unity project. EndRun: the marker the editor script reads.
    & $hooks.Start (New-Context $repo $plain)
    & $hooks.EndRun (New-Context $repo $repo)
    Assert-Equal (Test-Path "$repo\Client\Temp\ScriptoriumRunEnded") $true 'the run-end marker'
    & $hooks.EndRun (New-Context $repo $plain)

    # A project at the repo root.
    New-Item -ItemType Directory -Force "$plain\ProjectSettings" | Out-Null
    Copy-Item "$repo\Client\ProjectSettings\ProjectVersion.txt" "$plain\ProjectSettings\"
    Assert-Equal (& $hooks.GetRun (New-Context $plain $plain)).McpServers.UnityMCP.env.UNITY_MCP_DEFAULT_INSTANCE "$($plain.Replace('\', '/'))/Assets" 'a project at the root'
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'ok'
