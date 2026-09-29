param(
  [Parameter(Mandatory=$true)][string]$PdsShell,
  [Parameter(Mandatory=$true)][string]$RealLsuBuild,
  [Parameter(Mandatory=$true)][string]$CpuInputRoot,
  [Parameter(Mandatory=$true)][string]$Firmware,
  [Parameter(Mandatory=$true)][string]$ReferenceProject
)
$ErrorActionPreference='Stop'
if((Get-Content -LiteralPath (Join-Path $RealLsuBuild 'mode.txt') -Raw).Trim() -ne 'normal') { throw 'Normal CPU build required' }
$uart=Join-Path $CpuInputRoot 'rtl/mini_uart.v'
if((Get-FileHash -LiteralPath $uart).Hash.ToLower() -ne '12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e') { throw 'UART input mismatch' }
$referenceHashes=@{
 'mini_soc_first_board.v'='813149ea5ccdfbeb1e555de81a5eaf4d57e83e2b644027b938a3478dbc5c1b8b'
 'mini_first_board.fdc'='cc4dda537a7c352392b9cdeebfbc08c7980a23a679247b5f8b69570f752cdebe'
}
foreach($name in $referenceHashes.Keys) {
 if((Get-FileHash -LiteralPath (Join-Path $ReferenceProject $name)).Hash.ToLower() -ne $referenceHashes[$name]) { throw "Reference profile mismatch: $name" }
}
$stage=Join-Path ([IO.Path]::GetTempPath()) ('pds_lsu_'+[guid]::NewGuid().ToString('N'))
if($stage -match '[^\x00-\x7F]' -or (Test-Path -LiteralPath $stage)) { throw 'Need a new ASCII staging directory' }
New-Item -ItemType Directory -Path $stage | Out-Null
$sources=@{
 'VexWriteResponse.v'=(Join-Path $RealLsuBuild 'rtl/VexWriteResponse.v')
 'mini_uart.v'=$uart
 'mini_soc.v'=(Join-Path $PSScriptRoot 'mini_soc.v')
 'firmware.hex'=$Firmware
 'analysis.tcl'=(Join-Path $PSScriptRoot 'analysis.tcl')
}
foreach($name in $referenceHashes.Keys) { $sources[$name]=Join-Path $ReferenceProject $name }
foreach($file in Get-ChildItem -LiteralPath (Join-Path $RealLsuBuild 'rtl') -Filter '*.bin') { $sources[$file.Name]=$file.FullName }
$hashes=foreach($name in $sources.Keys) {
 Copy-Item -LiteralPath $sources[$name] -Destination (Join-Path $stage $name)
 [pscustomobject]@{File=$name;SHA256=(Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash}
}
$hashes | Export-Csv -LiteralPath (Join-Path $stage 'inputs.csv') -NoTypeInformation
Write-Output "STAGE=$stage"
Push-Location $stage
try {
 & $PdsShell -file "$($stage.Replace('\','/'))/analysis.tcl" -work_dir $stage -project_name lsu_analysis 2>&1 | Tee-Object -FilePath (Join-Path $stage 'console.log')
 $result=$LASTEXITCODE
} finally { Pop-Location }
if($result -ne 0) { throw "PDS exit $result; retain stage and inspect reports" }
Write-Output 'PDS process completed; inspect task status, timing and unconstrained paths before accepting.'
