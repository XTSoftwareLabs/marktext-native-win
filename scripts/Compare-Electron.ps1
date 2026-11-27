<#
.SYNOPSIS
Measures a native MarkText build against the official Electron build.

.DESCRIPTION
Extracts both ZIPs, then launches each build with a short Markdown file: one
warm-up run per build, then -Runs alternating runs. Each figure is the median
of those runs. Memory, threads and handles are summed over all of the app's
processes, -SettleSeconds after the document opened; idle CPU is averaged over
the next -IdleSeconds. Writes comparison.md (the README table) and
comparison.json (every run) to -OutDir.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $NativeZip,
  [Parameter(Mandatory)] [string] $ElectronZip,
  [string] $Heading = 'Native build against the official Electron build:',
  [int] $Runs = 3,
  [int] $SettleSeconds = 15,
  [int] $IdleSeconds = 10,
  [int] $TimeoutSeconds = 120,
  [string] $OutDir = 'comparison'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$MiB = 1MB
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$work = Join-Path ([IO.Path]::GetTempPath()) "marktext-compare-$PID"
New-Item -ItemType Directory -Force $work | Out-Null

$document = Join-Path $work 'sample.md'
@'
# Sample document

A short Markdown file for measuring start-up.

- one
- two
- three

```js
console.log('hello')
```
'@ | Set-Content -Encoding utf8NoBOM $document
$documentName = Split-Path -Leaf $document

function Expand-Build([string] $Zip, [string] $Name) {
  $dir = Join-Path $work $Name
  Expand-Archive -LiteralPath $Zip -DestinationPath $dir -Force
  $exe = Get-ChildItem -LiteralPath $dir -Recurse -Filter 'MarkText.exe' | Select-Object -First 1
  if (-not $exe) {
    $exe = Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.exe' |
      Where-Object Name -NotMatch '^(Uninstall|elevate|crashpad)' |
      Sort-Object Length -Descending | Select-Object -First 1
  }
  if (-not $exe) { throw "No executable found in $Zip" }
  $files = Get-ChildItem -LiteralPath $dir -Recurse -File
  [pscustomobject]@{
    Name      = $Name
    Exe       = $exe.FullName
    ZipBytes  = (Get-Item -LiteralPath $Zip).Length
    DiskBytes = ($files | Measure-Object Length -Sum).Sum
    Files     = $files.Count
  }
}

# Every process started from the build's folder, which covers Electron's
# helper processes as well as the main one.
function Get-AppProcesses([string] $Exe) {
  $folder = Split-Path -Parent $Exe
  Get-CimInstance Win32_Process |
    Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($folder, [StringComparison]::OrdinalIgnoreCase) } |
    ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue } |
    Where-Object { $_ }
}

function Get-CpuSeconds($Processes) {
  ($Processes | ForEach-Object { try { $_.Refresh(); $_.TotalProcessorTime.TotalSeconds } catch { 0 } } |
    Measure-Object -Sum).Sum
}

function Stop-App([string] $Exe) {
  for ($i = 0; $i -lt 20; $i++) {
    $procs = @(Get-AppProcesses $Exe)
    if (-not $procs) { return }
    $procs | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
  }
  throw "Could not stop $Exe"
}

function Measure-Run($Build) {
  Stop-App $Build.Exe
  $clock = [Diagnostics.Stopwatch]::StartNew()
  $root = Start-Process -FilePath $Build.Exe -ArgumentList "`"$document`"" -PassThru
  $window = $null
  $opened = $null
  $deadline = [TimeSpan]::FromSeconds($TimeoutSeconds)
  while ($null -eq $opened) {
    if ($clock.Elapsed -gt $deadline) {
      Stop-App $Build.Exe
      throw "$($Build.Name): the document did not open within $TimeoutSeconds s"
    }
    # The window normally belongs to the process that was started. Only if that
    # process exited (or still has no window after 5 s) are the app's other
    # processes searched, since listing them is too slow for precise timings.
    $candidates = @($root)
    if ($root.HasExited -or ($null -eq $window -and $clock.Elapsed.TotalSeconds -gt 5)) {
      $candidates = @(Get-AppProcesses $Build.Exe)
    }
    foreach ($p in $candidates) {
      try { $p.Refresh() } catch { continue }
      if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
        if ($null -eq $window) { $window = $clock.Elapsed.TotalMilliseconds }
        if ($p.MainWindowTitle -like "*$documentName*") { $opened = $clock.Elapsed.TotalMilliseconds; break }
      }
    }
    if ($null -eq $opened) { Start-Sleep -Milliseconds 10 }
  }
  $startCpu = Get-CpuSeconds (Get-AppProcesses $Build.Exe)

  Start-Sleep -Seconds $SettleSeconds
  $procs = @(Get-AppProcesses $Build.Exe)
  foreach ($p in $procs) { $p.Refresh() }
  $sample = [pscustomobject]@{
    Processes    = $procs.Count
    WorkingSet   = ($procs | Measure-Object WorkingSet64 -Sum).Sum
    PrivateBytes = ($procs | Measure-Object PrivateMemorySize64 -Sum).Sum
    Threads      = ($procs | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum
    Handles      = ($procs | Measure-Object HandleCount -Sum).Sum
  }
  $cpuBefore = Get-CpuSeconds $procs
  $idleClock = [Diagnostics.Stopwatch]::StartNew()
  Start-Sleep -Seconds $IdleSeconds
  $idleCpu = (Get-CpuSeconds $procs) - $cpuBefore
  $idlePercent = 100 * $idleCpu / ($idleClock.Elapsed.TotalSeconds * [Environment]::ProcessorCount)

  Stop-App $Build.Exe
  Start-Sleep -Seconds 2
  [pscustomobject]@{
    WindowMs     = $window
    OpenMs       = $opened
    StartCpu     = $startCpu
    IdleCpu      = $idlePercent
    Processes    = $sample.Processes
    WorkingSet   = $sample.WorkingSet
    PrivateBytes = $sample.PrivateBytes
    Threads      = $sample.Threads
    Handles      = $sample.Handles
  }
}

function Get-Median([double[]] $Values) {
  $sorted = $Values | Sort-Object
  $n = $sorted.Count
  if ($n % 2) { $sorted[($n - 1) / 2] } else { ($sorted[$n / 2 - 1] + $sorted[$n / 2]) / 2 }
}

$builds = [ordered]@{
  electron = Expand-Build $ElectronZip 'electron'
  native   = Expand-Build $NativeZip 'native'
}

foreach ($b in $builds.Values) {
  Write-Host "Warm-up: $($b.Name)"
  Measure-Run $b | Out-Null
}
$results = @{ electron = @(); native = @() }
for ($i = 1; $i -le $Runs; $i++) {
  foreach ($key in $builds.Keys) {
    Write-Host "Run $i/$($Runs): $key"
    $r = Measure-Run $builds[$key]
    $r | Format-List | Out-String | Write-Host
    $results[$key] += $r
  }
}

$median = @{}
foreach ($key in $builds.Keys) {
  $m = [ordered]@{}
  foreach ($prop in 'WindowMs', 'OpenMs', 'StartCpu', 'IdleCpu', 'Processes', 'WorkingSet', 'PrivateBytes', 'Threads', 'Handles') {
    $m[$prop] = Get-Median ($results[$key] | ForEach-Object $prop)
  }
  $median[$key] = [pscustomobject]$m
}

$culture = [Globalization.CultureInfo]::InvariantCulture
function Format-Size([double] $Bytes) { ($Bytes / $MiB).ToString('N1', $culture) + ' MB' }
function Format-Count([double] $Value) { ([math]::Round($Value)).ToString('N0', $culture) }
function Format-Ms([double] $Value) { ([math]::Round($Value)).ToString('N0', $culture) + ' ms' }

# Lower is better for every metric. $Less and $More name the change, such as
# 'smaller' and 'larger'.
function Format-Change([double] $Electron, [double] $Native, [string] $Less, [string] $More, [switch] $Speed) {
  if ($Electron -eq 0 -and $Native -eq 0) { return 'same' }
  if ($Native -le $Electron) {
    if ($Speed -and $Native -gt 0 -and $Electron / $Native -ge 2) {
      return ($Electron / $Native).ToString('0.0', $culture) + "× $Less"
    }
    $pct = [math]::Round(100 * ($Electron - $Native) / $Electron)
    if ($pct -eq 0) { return 'same' }
    return "$pct% $Less"
  }
  if ($Electron -eq 0) { return $More }
  return ([math]::Round(100 * ($Native - $Electron) / $Electron)).ToString() + "% $More"
}

$e = $builds.electron; $n = $builds.native
$em = $median.electron; $nm = $median.native
$rows = @(
  , @('Download (ZIP)', (Format-Size $e.ZipBytes), (Format-Size $n.ZipBytes), (Format-Change $e.ZipBytes $n.ZipBytes 'smaller' 'larger'))
  , @('Installed folder', (Format-Size $e.DiskBytes), (Format-Size $n.DiskBytes), (Format-Change $e.DiskBytes $n.DiskBytes 'smaller' 'larger'))
  , @('Files on disk', (Format-Count $e.Files), (Format-Count $n.Files), (Format-Change $e.Files $n.Files 'fewer' 'more'))
  , @('Time to window', (Format-Ms $em.WindowMs), (Format-Ms $nm.WindowMs), (Format-Change $em.WindowMs $nm.WindowMs 'faster' 'slower' -Speed))
  , @('Time to open a document', (Format-Ms $em.OpenMs), (Format-Ms $nm.OpenMs), (Format-Change $em.OpenMs $nm.OpenMs 'faster' 'slower' -Speed))
  , @('CPU time to start', ($em.StartCpu.ToString('0.00', $culture) + ' s'), ($nm.StartCpu.ToString('0.00', $culture) + ' s'), (Format-Change $em.StartCpu $nm.StartCpu 'less' 'more'))
  , @('CPU when idle', ($em.IdleCpu.ToString('0.00', $culture) + '%'), ($nm.IdleCpu.ToString('0.00', $culture) + '%'), (Format-Change ([math]::Round($em.IdleCpu, 2)) ([math]::Round($nm.IdleCpu, 2)) 'less' 'more'))
  , @('Processes', (Format-Count $em.Processes), (Format-Count $nm.Processes), (Format-Change $em.Processes $nm.Processes 'fewer' 'more'))
  , @('Memory (working set)', (Format-Size $em.WorkingSet), (Format-Size $nm.WorkingSet), (Format-Change $em.WorkingSet $nm.WorkingSet 'less' 'more'))
  , @('Memory (private bytes)', (Format-Size $em.PrivateBytes), (Format-Size $nm.PrivateBytes), (Format-Change $em.PrivateBytes $nm.PrivateBytes 'less' 'more'))
  , @('Threads', (Format-Count $em.Threads), (Format-Count $nm.Threads), (Format-Change $em.Threads $nm.Threads 'fewer' 'more'))
  , @('Handles', (Format-Count $em.Handles), (Format-Count $nm.Handles), (Format-Change $em.Handles $nm.Handles 'fewer' 'more'))
)

$os = Get-CimInstance Win32_OperatingSystem
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()
$ram = [math]::Round($os.TotalVisibleMemorySize / 1MB)
$lines = @(
  $Heading
  ''
  '| Metric | Electron | Native | Change |'
  '|---|---:|---:|---:|'
) + ($rows | ForEach-Object { "| $($_ -join ' | ') |" }) + @(
  ''
  "Measured on $($os.Caption) ($($os.Version)) with $cpu ($([Environment]::ProcessorCount) logical processors) and $ram GB of RAM,"
  "opening a short Markdown file. Each figure is the median of $Runs runs, after one warm-up run per build."
  "Memory, threads and handles are summed over all of the app's processes,"
  "$SettleSeconds seconds after the document opened; idle CPU is averaged over the next"
  "$IdleSeconds seconds. Sizes are in MiB."
)
$lines | Set-Content -Encoding utf8NoBOM (Join-Path $OutDir 'comparison.md')

[ordered]@{
  native   = [ordered]@{ zip = (Split-Path -Leaf $NativeZip); build = $n; median = $nm; runs = $results.native }
  electron = [ordered]@{ zip = (Split-Path -Leaf $ElectronZip); build = $e; median = $em; runs = $results.electron }
  machine  = [ordered]@{ os = "$($os.Caption) $($os.Version)"; cpu = $cpu; logicalProcessors = [Environment]::ProcessorCount; ramGB = $ram }
  method   = [ordered]@{ runs = $Runs; settleSeconds = $SettleSeconds; idleSeconds = $IdleSeconds; document = $documentName }
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8NoBOM (Join-Path $OutDir 'comparison.json')

$lines -join "`n" | Write-Host
