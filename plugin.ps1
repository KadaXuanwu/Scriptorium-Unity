# Scriptorium for Unity (README.md): the hooks of the Scriptorium plugin contract, version 1. Loading this file only
# defines functions; the base calls the hooks in the hashtable at its end. Settings: `editors` (the folder that holds
# one folder per Unity version, Unity Hub's default) and `mcpVersion` (a fixed version of the MCP for Unity server).
$ErrorActionPreference = 'Stop'

$DefaultEditors = 'C:\Program Files\Unity\Hub\Editor'
# This plugin's folder: unity/Assets holds the editor script.
$PluginRoot = $PSScriptRoot

# The editors folder from the plugin's settings, else the default.
function Get-Editors($settings) {
    if ($settings -and $settings.editors) {
        return [string]$settings.editors
    }
    return $DefaultEditors
}

# The uvx arguments that pick the MCP for Unity server. The server must be the release of the Unity package in the
# project, so no file holds a version number: the version of the installed package (embedded in Packages, else Unity's
# cache in Library), or the latest release for a project that Unity has not resolved yet. The `mcpVersion` setting fixes
# one instead.
function Get-McpSource([string] $project, $settings) {
    $version = if ($settings -and $settings.mcpVersion) { [string]$settings.mcpVersion } else { $null }
    if (-not $version) {
        $package = 'com.coplaydev.unity-mcp'
        $files = @(Get-Item "$project/Packages/$package/package.json" -ErrorAction SilentlyContinue) +
            @(Get-ChildItem "$project/Library/PackageCache/$package@*/package.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($files) {
            $version = [string](Get-Content $files[0].FullName -Raw | ConvertFrom-Json).version
        }
    }
    if (-not $version) {
        return @('--from', 'mcpforunityserver')
    }
    # A pre-release package (the beta branch) asks for the newest pre-release server.
    if ($version.Contains('-')) {
        return @('--prerelease', 'explicit', '--from', 'mcpforunityserver>=0.0.0a0')
    }
    return @('--from', "mcpforunityserver==$version")
}

# A checkout's Unity project: the checkout itself or a folder one level down; $null for a repo without one.
function Get-UnityProject([string] $dir) {
    if (-not $dir -or -not (Test-Path $dir)) {
        return $null
    }
    $folders = @(Get-Item $dir) + @(Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.git' } | Sort-Object Name)
    foreach ($folder in $folders) {
        if (Test-Path (Join-Path $folder.FullName 'ProjectSettings\ProjectVersion.txt')) {
            return $folder.FullName.Replace('\', '/')
        }
    }
    return $null
}

# The project's path from its checkout's root, '' when it is the root: the same in every copy of the repo.
function Get-RelativeProject([string] $checkout, [string] $project) {
    $root = (Resolve-Path $checkout).Path.TrimEnd('\').Replace('\', '/')
    return $project.Substring($root.Length).TrimStart('/')
}

function Get-UnityVersion([string] $project) {
    return ((Get-Content (Join-Path $project 'ProjectSettings\ProjectVersion.txt'))[0] -split ' ')[1]
}

# A project's editor as MCP for Unity names it (Unity@<hash>), from its status file.
function Get-UnityInstance([string] $assets) {
    foreach ($file in Get-ChildItem "$HOME\.unity-mcp\unity-mcp-status-*.json" -ErrorAction SilentlyContinue) {
        $status = Get-Content $file.FullName -Raw | ConvertFrom-Json
        if ($status.project_path -eq $assets) {
            return "Unity@$($file.BaseName.Substring('unity-mcp-status-'.Length))"
        }
    }
    return $null
}

function Test-UnityReady([string] $assets) {
    foreach ($file in Get-ChildItem "$HOME\.unity-mcp\unity-mcp-status-*.json" -ErrorAction SilentlyContinue) {
        $status = Get-Content $file.FullName -Raw | ConvertFrom-Json
        if ($status.project_path -eq $assets -and $status.reason -eq 'ready') {
            return $true
        }
    }
    return $false
}

# An open editor holds Temp/UnityLockfile alone; Unity's own "another instance" check reads the same lock. The process
# list missed an open editor now and then, and each miss opened a second one. An editor that still starts, or that
# waits in a dialog before it opens the project, holds no lock yet: the process this plugin started counts too.
# shortcut: an editor that waits in a dialog counts as open, so a later run can start on an editor that never answers;
# when one shows, wait for MCP for Unity's "ready" for such an editor too.
function Test-ProjectOpen([string] $project) {
    $started = "-projectPath `"$project`""
    if (Get-CimInstance Win32_Process -Filter "Name='Unity.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($started) }) {
        return $true
    }
    $lock = "$project/Temp/UnityLockfile"
    if (-not (Test-Path $lock)) {
        return $false
    }
    try {
        [System.IO.File]::Open($lock, 'Open', 'ReadWrite', 'None').Dispose()
        return $false
    } catch {
        return $true
    }
}

# Opens the project's editor when none is open, and waits until MCP for Unity says it is ready: a first open imports
# everything, so up to 90 minutes, then the run tries anyway. Reports every 30 seconds.
# shortcut: an editor of another repo's job stays open beside the copy's own; close it by hand if memory gets tight.
function Start-UnityIfClosed([string] $project, $ctx) {
    if (Test-ProjectOpen $project) {
        return
    }
    $version = Get-UnityVersion $project
    $editor = Join-Path (Get-Editors $ctx.Settings) "$version\Editor\Unity.exe"
    if (-not (Test-Path $editor)) {
        throw "Unity $version is not in $(Get-Editors $ctx.Settings): install it with Unity Hub, or set the plugin's editors setting"
    }
    # What an editor that was ended by force leaves behind. A scene backup makes the next editor ask in a dialog before it
    # opens the project, and nobody is there to click. The status file still says "ready", so the wait below would end.
    Remove-Item "$project/Temp/__Backupscenes" -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($file in Get-ChildItem "$HOME\.unity-mcp\unity-mcp-status-*.json" -ErrorAction SilentlyContinue) {
        if ((Get-Content $file.FullName -Raw | ConvertFrom-Json).project_path -eq "$project/Assets") {
            Remove-Item $file.FullName -Force
        }
    }
    & $ctx.Log "starting Unity $version on $project"
    Start-Process $editor -ArgumentList "-projectPath `"$project`""
    for ($i = 0; $i -lt 180 -and -not (Test-UnityReady "$project/Assets"); $i++) {
        & $ctx.Report 'Opening its Unity editor'
        Start-Sleep 30
    }
}

# Unity's Smart Merge as the checkout's merge driver for the YAML files .gitattributes routes to it. Per checkout.
function Set-YamlMerge([string] $checkout, [string] $version, $settings) {
    $tool = (Join-Path (Get-Editors $settings) "$version\Editor\Data\Tools\UnityYAMLMerge.exe").Replace('\', '/')
    & git -C $checkout config merge.unityyamlmerge.name 'Unity SmartMerge'
    & git -C $checkout config merge.unityyamlmerge.driver "'$tool' merge -h -p --force %O %B %A %A"
    & git -C $checkout config merge.unityyamlmerge.recursive binary
}

# The Asset Store packages a new copy lacks, when the project lists them in AssetStore.json at its root
# (`{ "Packages": [{ "Root": "Assets/Pack", "Probe": "Assets/Pack/a.cs" }] }`): they are not in git, and a fresh copy
# cannot import them alone. Copied from the main checkout, root folder and its .meta; then the files git holds go back
# to what git has. Nothing without the file.
function Copy-AssetStorePackages([string] $mainProject, [string] $copyProject, [string] $copy, [string] $relative) {
    $list = Join-Path $mainProject 'AssetStore.json'
    if (-not (Test-Path $list)) {
        return
    }
    $prefix = if ($relative) { "$relative/" } else { '' }
    foreach ($package in (Get-Content $list -Raw | ConvertFrom-Json).Packages) {
        $from = (Join-Path $mainProject $package.Root).Replace('/', '\')
        $to = (Join-Path $copyProject $package.Root).Replace('/', '\')
        if (-not (Test-Path $from) -or (Test-Path (Join-Path $copyProject $package.Probe))) {
            continue
        }
        & robocopy $from $to /E /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) {
            throw "copying $($package.Root) into $copyProject failed"
        }
        Copy-Item "$from.meta" "$to.meta" -ErrorAction SilentlyContinue
        # Only a root with tracked files: on none, git checkout writes an error.
        if (& git -C $copy ls-files -- "$prefix$($package.Root)") {
            & git -C $copy checkout -- "$prefix$($package.Root)"
        }
    }
}

# The editor script that leaves play mode when a run ends (unity/Assets/Scriptorium), copied into the project when it
# is not there. Returns the files it added, as paths from the repo root.
function Add-EditorScript([string] $checkout, [string] $project) {
    $relative = Get-RelativeProject $checkout $project
    $prefix = if ($relative) { "$relative/" } else { '' }
    $added = @()
    foreach ($file in @(Get-ChildItem (Join-Path $PluginRoot 'unity\Assets') -Recurse -File)) {
        $path = 'Assets/' + $file.FullName.Substring((Join-Path $PluginRoot 'unity\Assets').Length + 1).Replace('\', '/')
        $target = Join-Path $project $path
        if (Test-Path $target) {
            continue
        }
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item $file.FullName $target
        $added += "$prefix$path"
    }
    return $added
}

# The lines that route Unity's YAML files to Smart Merge, added to .gitattributes at the repo root when it routes none.
function Add-YamlAttributes([string] $checkout) {
    $file = Join-Path $checkout '.gitattributes'
    if ((Test-Path $file) -and (Select-String -Path $file -Pattern 'merge=unityyamlmerge' -SimpleMatch -Quiet)) {
        return @()
    }
    $lines = @('', '# Unity YAML through Smart Merge (Scriptorium for Unity sets the driver in each checkout).') +
        @('anim', 'asset', 'brush', 'controller', 'flare', 'fontsettings', 'giparams', 'guiskin', 'lighting', 'mask', 'mat',
        'meta', 'mixer', 'overrideController', 'physicMaterial', 'physicsMaterial2D', 'playable', 'prefab', 'preset',
        'renderTexture', 'scenetemplate', 'shadervariants', 'signal', 'spriteatlas', 'spriteatlasv2', 'terrainlayer',
        'unity' | ForEach-Object { "*.$_ merge=unityyamlmerge" })
    Add-Content $file $lines -Encoding utf8
    return @('.gitattributes')
}

@{
    # Checks uvx and the editor of the project's Unity version, adds the editor script and the YAML merge lines, and sets Smart
    # Merge in the main checkout. Returns the files it added.
    Setup = {
        param($ctx)
        if (-not (Get-Command uvx -ErrorAction SilentlyContinue)) {
            throw 'uvx is not on the PATH: install uv (https://docs.astral.sh/uv/)'
        }
        $project = Get-UnityProject $ctx.Project
        if (-not $project) {
            & $ctx.Log 'no Unity project in the repo root or one folder down: nothing to set up'
            return @()
        }
        $version = Get-UnityVersion $project
        if (-not (Test-Path (Join-Path (Get-Editors $ctx.Settings) "$version\Editor\Unity.exe"))) {
            throw "Unity $version is not in $(Get-Editors $ctx.Settings): install it with Unity Hub, or set the plugin's editors setting"
        }
        Set-YamlMerge $ctx.Project $version $ctx.Settings
        return @(Add-EditorScript $ctx.Project $project) + @(Add-YamlAttributes $ctx.Project)
    }
    # Copies the Asset Store packages the copy lacks and sets Smart Merge in it.
    PrepareCopy = {
        param($ctx)
        $project = Get-UnityProject $ctx.Project
        if (-not $project) {
            return
        }
        $relative = Get-RelativeProject $ctx.Project $project
        $copyProject = if ($relative) { Join-Path $ctx.Copy $relative } else { $ctx.Copy }
        Copy-AssetStorePackages $project $copyProject $ctx.Copy $relative
        Set-YamlMerge $ctx.Copy (Get-UnityVersion $project) $ctx.Settings
    }
    # Opens the checkout's editor when it is closed and waits until it is ready.
    Start = {
        param($ctx)
        $project = Get-UnityProject $ctx.Copy
        if ($project) {
            Start-UnityIfClosed $project $ctx
        }
    }
    # MCP for Unity pinned to the checkout's editor. The server pins by UNITY_MCP_DEFAULT_INSTANCE, but a session that
    # starts while only another editor answers selects that one for good: the prompt names this one first.
    GetRun = {
        param($ctx)
        $project = Get-UnityProject $ctx.Copy
        if (-not $project) {
            return @{}
        }
        $assets = "$project/Assets"
        $uvx = (Get-Command uvx).Source.Replace('\', '/')
        $run = @{
            McpServers = @{ UnityMCP = @{ type = 'stdio'; command = $uvx
                args = @(Get-McpSource $project $ctx.Settings) + @('mcp-for-unity')
                env = @{ UNITY_MCP_DEFAULT_INSTANCE = $assets } } }
            AllowedTools = @('mcp__UnityMCP')
        }
        $instance = Get-UnityInstance $assets
        if ($instance) {
            $run.Prompt = "Your Unity editor is $instance (project $assets): make set_active_instance('$instance') your " +
                'first Unity MCP call, again after any MCP reconnect.'
        }
        return $run
    }
    # The editor leaves play mode however the run ended (Assets/Scriptorium/Editor/RunEnd.cs reads the marker).
    EndRun = {
        param($ctx)
        $project = Get-UnityProject $ctx.Copy
        if ($project -and (Test-Path "$project/Temp")) {
            Set-Content "$project/Temp/ScriptoriumRunEnded" '' -Encoding utf8
        }
    }
}
