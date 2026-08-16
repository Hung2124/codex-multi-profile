#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'tests\Invoke-ParseCheck.ps1')
& (Join-Path $root 'tests\ConvertTo-ProfileKey.Tests.ps1')
& (Join-Path $root 'tests\AuthSwap.Tests.ps1')
& (Join-Path $root 'tests\HideEmailAndEnvCmd.Tests.ps1')
& (Join-Path $root 'tests\StatusAndRemove.Tests.ps1')
& (Join-Path $root 'tests\Doctor.Tests.ps1')
& (Join-Path $root 'tests\RedactLaunchTrace.Tests.ps1')
& (Join-Path $root 'tests\RepairAndSync.Tests.ps1')
& (Join-Path $root 'tests\CloneVersionSort.Tests.ps1')
& (Join-Path $root 'tests\ExportDiagnostics.Tests.ps1')
Write-Output 'OK: all tests passed.'
