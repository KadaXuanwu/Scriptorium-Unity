# Scriptorium for Unity (README.md): the hooks of the Scriptorium plugin contract, version 1. Loading this file only
# defines functions; the base calls the hooks in the hashtable at its end. A run drives its copy's editor with the Unity
# CLI (`unity`), which reaches the editor through the project's com.unity.pipeline package. Setting: `editors` (the
# folder that holds one folder per Unity version, Unity Hub's default).
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

# What a run may call without a question: the commands that drive or start its own editor, never the ones that install
# or remove an editor, sign in or change the PC.
$RunTools = @('Bash(unity command:*)', 'Bash(unity recompile:*)', 'Bash(unity status:*)', 'Bash(unity job:*)',
    'Bash(unity test:*)', 'Bash(unity run:*)', 'Bash(unity open:*)', 'Bash(unity close:*)', 'Bash(unity skill show:*)')

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
    return (@(Get-Content (Join-Path $project 'ProjectSettings\ProjectVersion.txt'))[0] -split ' ')[1]
}

# Whether the project holds the package through which the Unity CLI reaches a running editor (Unity 6.0 and later).
# Without it no command reaches an editor, so this plugin opens none: a run then uses `unity test` and `unity run`,
# which start an editor of their own in batch mode.
function Test-Pipeline([string] $project) {
    $manifest = "$project/Packages/manifest.json"
    return (Test-Path $manifest) -and (Select-String -Path $manifest -Pattern '"com.unity.pipeline"' -SimpleMatch -Quiet)
}

# The project's editor as the Unity CLI sees it (`state`, and `blockedBy` while a dialog stops it); $null when the CLI
# sees none.
function Get-EditorStatus([string] $project) {
    $text = (& unity status --project-path $project.Replace('/', '\') --format json --non-interactive 2>$null | Out-String)
    try {
        return @(($text | ConvertFrom-Json).data.instances)[0]
    } catch {
        return $null
    }
}

# An open editor holds Temp/UnityLockfile alone; Unity's own "another instance" check reads the same lock. The process
# list missed an open editor now and then, and each miss opened a second one. An editor that still starts, or that
# waits in a dialog before it opens the project, holds no lock yet: the process this plugin started counts too.
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

# Opens the project's editor when none is open.
# shortcut: an editor of another repo's job stays open beside the copy's own until the worker is disabled.
function Start-UnityIfClosed([string] $project, $ctx) {
    if (Test-ProjectOpen $project) {
        return
    }
    $version = Get-UnityVersion $project
    $editor = Join-Path (Get-Editors $ctx.Settings) "$version\Editor\Unity.exe"
    if (-not (Test-Path $editor)) {
        throw "Unity $version is not in $(Get-Editors $ctx.Settings): install it with Unity Hub, or set the plugin's editors setting"
    }
    # An editor that was ended by force leaves a scene backup. It makes the next editor ask in a dialog before it opens
    # the project, and nobody is there to click.
    Remove-Item "$project/Temp/__Backupscenes" -Recurse -Force -ErrorAction SilentlyContinue
    & $ctx.Log "starting Unity $version on $project"
    Start-Process $editor -ArgumentList "-projectPath `"$project`""
}

# Opens the project's editor and waits until the Unity CLI says it is ready for commands: a first open imports
# everything, so up to 90 minutes. Reports every 30 seconds. An editor that closes during the wait opens again. A dialog
# never closes with nobody there, so it throws with the dialog's title: the worker shows that on its card and looks
# again later.
function Wait-UnityReady([string] $project, $ctx) {
    for ($i = 0; $i -lt 180; $i++) {
        $status = Get-EditorStatus $project
        if ($status -and $status.state -eq 'ready') {
            return
        }
        $dialogs = @($status.blockedBy.dialogs | ForEach-Object { $_.title } | Where-Object { $_ })
        if ($dialogs) {
            throw "its Unity editor waits in a dialog that a person must answer: $($dialogs -join ', ')"
        }
        Start-UnityIfClosed $project $ctx
        & $ctx.Report 'Opening its Unity editor'
        Start-Sleep 30
    }
    throw 'its Unity editor was not ready for commands after 90 minutes'
}

# Unity's Smart Merge as the checkout's merge driver for the YAML files .gitattributes routes to it. Per checkout.
function Set-YamlMerge([string] $checkout, [string] $version, $settings) {
    $tool = (Join-Path (Get-Editors $settings) "$version\Editor\Data\Tools\UnityYAMLMerge.exe").Replace('\', '/')
    & git -C $checkout config merge.unityyamlmerge.name 'Unity SmartMerge'
    & git -C $checkout config merge.unityyamlmerge.driver "'$tool' merge -h -p --force %O %B %A %A"
    & git -C $checkout config merge.unityyamlmerge.recursive binary
}

# The Asset Store packages a copy lacks, when its project lists them in AssetStore.json at its root
# (`{ "Packages": [{ "Root": "Assets/Pack", "Probe": "Assets/Pack/a.cs" }] }`): they are not in git, and a copy cannot
# import them alone. Copied from the main checkout, root folder and its .meta; then the files git holds go back to what
# git has. The copy's own list, not the main checkout's: a package can need Unity packages that only a manifest of the
# same commit names, and on an older branch it would not compile. Nothing without the file.
function Copy-AssetStorePackages([string] $mainProject, [string] $copyProject, [string] $copy, [string] $relative) {
    $list = Join-Path $copyProject 'AssetStore.json'
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

# Copy-AssetStorePackages from the main checkout's project into the same folder of $ctx.Copy.
function Update-AssetStorePackages($ctx, [string] $mainProject) {
    $relative = Get-RelativeProject $ctx.Project $mainProject
    $copyProject = if ($relative) { Join-Path $ctx.Copy $relative } else { $ctx.Copy }
    Copy-AssetStorePackages $mainProject $copyProject $ctx.Copy $relative
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

# The package through which the Unity CLI reaches a running editor, added to the project's manifest when it is not
# there. Unity 6.0 and later only. Returns the manifest when it changed, as a path from the repo root.
function Add-Pipeline([string] $checkout, [string] $project, $ctx) {
    if (Test-Pipeline $project) {
        return @()
    }
    if ([int]((Get-UnityVersion $project) -split '\.')[0] -lt 6000) {
        & $ctx.Log 'the Unity CLI reaches a running editor from Unity 6.0 on: runs here get unity test and unity run only'
        return @()
    }
    & unity pipeline install --project-path $project.Replace('/', '\') --non-interactive | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Pipeline $project)) {
        throw "unity pipeline install did not add com.unity.pipeline to $project"
    }
    $relative = Get-RelativeProject $checkout $project
    return @("$(if ($relative) { "$relative/" })Packages/manifest.json")
}

@{
    # Checks the editor of the project's Unity version, adds the editor script, the YAML merge lines and the Pipeline
    # package, and sets Smart Merge in the main checkout. Returns the files it added or changed.
    Setup = {
        param($ctx)
        if (-not (Get-Command unity -ErrorAction SilentlyContinue)) {
            throw 'the Unity CLI (unity) is not on the PATH: README.md says where to get it'
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
        return @(Add-EditorScript $ctx.Project $project) + @(Add-YamlAttributes $ctx.Project) + @(Add-Pipeline $ctx.Project $project $ctx)
    }
    # Copies the Asset Store packages the copy lacks and sets Smart Merge in it.
    PrepareCopy = {
        param($ctx)
        $project = Get-UnityProject $ctx.Project
        if (-not $project) {
            return
        }
        Update-AssetStorePackages $ctx $project
        Set-YamlMerge $ctx.Copy (Get-UnityVersion $project) $ctx.Settings
    }
    # Copies the Asset Store packages the copy lacks, as PrepareCopy does: a package added after the copy was made comes
    # with a later branch, and the editor's own import of it would wait in a dialog. Then opens the checkout's editor
    # when it is closed and waits until it is ready for commands. Not for a project without the Pipeline package: no
    # command reaches its editor, and an open editor stops the batch mode runs.
    Start = {
        param($ctx)
        $main = Get-UnityProject $ctx.Project
        if ($main) {
            Update-AssetStorePackages $ctx $main
        }
        $project = Get-UnityProject $ctx.Copy
        if ($project -and (Test-Pipeline $project)) {
            Wait-UnityReady $project $ctx
        }
    }
    # The Unity CLI, aimed at the checkout's own editor. With several editors open, a command with no project takes the
    # only editor that answers, also another copy's: UNITY_PROJECT_PATH in the run's environment names this one.
    GetRun = {
        param($ctx)
        $project = Get-UnityProject $ctx.Copy
        if (-not $project) {
            return @{}
        }
        $path = $project.Replace('/', '\')
        $run = @{
            AllowedTools = $RunTools
            Env = @{ UNITY_PROJECT_PATH = $path; UNITY_NO_BANNER = '1'; UNITY_NO_PAGER = '1'; UNITY_NON_INTERACTIVE = '1' }
        }
        $run.Prompt = if (Test-Pipeline $project) {
            "Your Unity editor is the one that has $path open. UNITY_PROJECT_PATH names it for every unity command: " +
                'never pass another project to one.'
        } else {
            "The Unity project $path has no com.unity.pipeline package, so no unity command reaches an editor: use " +
                'unity test and unity run, which start an editor in batch mode.'
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
    # Closes the checkout's editor, the one Start opens. It exits without saving: a run pushes its work at each
    # checkpoint, and the worker calls this only after its run has ended.
    Close = {
        param($ctx)
        $project = Get-UnityProject $ctx.Copy
        if ($project -and (Test-Pipeline $project) -and (Test-ProjectOpen $project)) {
            & $ctx.Log "closing the Unity editor of $project"
            & unity close $project.Replace('/', '\') --force --non-interactive | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "unity close did not close the editor of $project"
            }
        }
    }
}
