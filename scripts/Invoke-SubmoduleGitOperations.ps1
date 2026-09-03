param([string]$ProjectRoot = (Get-Location).Path)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$root = (& git -C $ProjectRoot rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
    Write-Host 'Error: This tool must be run inside a Git repository.' -ForegroundColor Red
    exit 1
}

Set-Location -LiteralPath $root

function Get-SubmodulePaths {
    $paths = @(& git -C $root submodule foreach --recursive --quiet 'pwd -W')
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not enumerate the repository submodules.'
    }

    return @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Attach-SubmoduleHead([string] $path) {
    & git -C $path symbolic-ref --quiet HEAD *> $null
    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    Write-Host "--- $path (detached HEAD detected)" -ForegroundColor Yellow
    $localBranches = @(& git -C $path for-each-ref '--format=%(refname:short)' --points-at HEAD refs/heads)
    $branch = $localBranches |
        Sort-Object @{ Expression = { if ($_ -eq 'main') { 0 } elseif ($_ -eq 'master') { 1 } else { 2 } } }, @{ Expression = { $_ } } |
        Select-Object -First 1

    if ($branch) {
        & git -C $path switch $branch *> $null
        return ($LASTEXITCODE -eq 0)
    }

    $remoteHead = & git -C $path symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $remoteHead) {
        $currentCommit = & git -C $path rev-parse HEAD
        $remoteCommit = & git -C $path rev-parse $remoteHead
        if ($currentCommit -eq $remoteCommit) {
            $branch = $remoteHead.Substring($remoteHead.IndexOf('/') + 1)
            & git -C $path show-ref --verify --quiet ("refs/heads/$branch")
            if ($LASTEXITCODE -eq 0) {
                & git -C $path merge-base --is-ancestor $branch $remoteHead
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Local branch $branch has diverged in $path"
                    return $false
                }

                & git -C $path branch -f $branch $remoteHead
                if ($LASTEXITCODE -ne 0) {
                    return $false
                }

                & git -C $path switch $branch *> $null
                return ($LASTEXITCODE -eq 0)
            }

            & git -C $path switch --track -c $branch $remoteHead *> $null
            return ($LASTEXITCODE -eq 0)
        }
    }

    Write-Error "Cannot safely choose a branch for detached HEAD in $path."
    return $false
}

function Invoke-CommitAllSubmodules {
    $message = Read-Host 'Commit message for all changed submodules'
    if ([string]::IsNullOrWhiteSpace($message)) {
        Write-Host 'Commit message cannot be empty.' -ForegroundColor Yellow
        return
    }

    $exitCode = 0
    $paths = @(Get-SubmodulePaths | Sort-Object { ($_ -split '[/\\]').Count } -Descending)
    foreach ($path in $paths) {
        if (-not (Attach-SubmoduleHead $path)) {
            $exitCode = 1
            continue
        }

        $changes = @(& git -C $path status --porcelain)
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
            continue
        }

        if ($changes.Count -eq 0) {
            Write-Host "--- $path (clean, skipped)"
            continue
        }

        Write-Host "--- $path"
        & git -C $path add -A
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
            continue
        }

        & git -C $path commit -m $message
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
        }
    }

    if ($exitCode -eq 0) {
        Write-Host 'Finished committing all changed submodules.' -ForegroundColor Green
        Write-Host 'The parent repository was not committed; its submodule pointers may now be modified.'
    } else {
        Write-Host "One or more submodule commits failed. Exit code: $exitCode" -ForegroundColor Red
    }
}

function Invoke-PushAll {
    & git -C $root push
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Root repository push failed. Exit code: $LASTEXITCODE" -ForegroundColor Red
        return
    }

    $exitCode = 0
    foreach ($path in Get-SubmodulePaths) {
        Write-Host "--- $path"
        & git -C $path push
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
        }
    }

    if ($exitCode -eq 0) {
        Write-Host 'Finished pushing the root repository and all submodules.' -ForegroundColor Green
    } else {
        Write-Host "One or more submodule pushes failed. Exit code: $exitCode" -ForegroundColor Red
    }
}

function Invoke-PullAllSubmodules {
    & git -C $root pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Root repository pull failed. Exit code: $LASTEXITCODE" -ForegroundColor Red
        return
    }

    & git -C $root submodule sync --recursive
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Submodule synchronization failed. Exit code: $LASTEXITCODE" -ForegroundColor Red
        return
    }

    & git -C $root submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Submodule initialization failed. Exit code: $LASTEXITCODE" -ForegroundColor Red
        return
    }

    $exitCode = 0
    foreach ($path in Get-SubmodulePaths) {
        if (-not (Attach-SubmoduleHead $path)) {
            $exitCode = 1
            continue
        }

        Write-Host "--- $path"
        & git -C $path pull --ff-only
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
        }
    }

    if ($exitCode -eq 0) {
        Write-Host 'Finished pulling the root repository and all submodules.' -ForegroundColor Green
    } else {
        Write-Host "One or more submodule pulls failed. Exit code: $exitCode" -ForegroundColor Red
    }
}

function Read-MenuSelection([string[]] $items) {
    $selected = 0
    while ($true) {
        Clear-Host
        Write-Host 'Submodule Git Operations' -ForegroundColor Cyan
        Write-Host 'Use Up/Down to choose, Enter to run, Esc to go back.'
        Write-Host ''

        for ($index = 0; $index -lt $items.Count; $index++) {
            if ($index -eq $selected) {
                Write-Host ("> " + $items[$index]) -ForegroundColor Black -BackgroundColor Cyan
            } else {
                Write-Host ("  " + $items[$index])
            }
        }

        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            ([ConsoleKey]::UpArrow) { $selected = ($selected - 1 + $items.Count) % $items.Count }
            ([ConsoleKey]::DownArrow) { $selected = ($selected + 1) % $items.Count }
            ([ConsoleKey]::Enter) { return $selected }
            ([ConsoleKey]::Escape) { return -1 }
        }
    }
}

$items = @(
    'Commit all changed submodules',
    'Push root repository and all submodules',
    'Pull root repository and all submodules',
    'Exit'
)

while ($true) {
    $selection = Read-MenuSelection $items
    if ($selection -lt 0 -or $selection -eq 3) {
        exit 0
    }

    Clear-Host
    try {
        switch ($selection) {
            0 { Invoke-CommitAllSubmodules }
            1 { Invoke-PushAll }
            2 { Invoke-PullAllSubmodules }
        }
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
    }

    Write-Host ''
    Write-Host 'Press any key to return to the menu. Esc also returns to the menu.' -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}
