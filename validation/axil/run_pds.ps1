param(
 [Parameter(Mandatory=$true)][string]$PdsShell,
 [Parameter(Mandatory=$true)][string]$AxilCpuBuild,
 [Parameter(Mandatory=$true)][string]$CpuInputRoot,
 [Parameter(Mandatory=$true)][string]$SocRun,
 [Parameter(Mandatory=$true)][string]$ReferenceProject
)
$ErrorActionPreference='Stop'
if((Get-Content -LiteralPath (Join-Path $AxilCpuBuild 'mode.txt') -Raw).Trim() -ne 'normal'){throw 'Normal CPU required'}
if((Get-FileHash -LiteralPath (Join-Path $AxilCpuBuild 'rtl/VexAxilCpu.v')).Hash.ToLower() -ne 'd0e23f3c4de105dd2c547f41c4bc5f81dd89b3d7d6dba34db8b3062eea701a25'){throw 'CPU input changed; audit configuration first'}
$uart=Join-Path $CpuInputRoot 'rtl/mini_uart.v'
$fdc=Join-Path $ReferenceProject 'mini_first_board.fdc'
if((Get-FileHash -LiteralPath $uart).Hash.ToLower() -ne '12c0b1b94fb3132e68587c72dfe431407dc12785024a07e81fac584a17f5a68e'){throw 'UART mismatch'}
if((Get-FileHash -LiteralPath $fdc).Hash.ToLower() -ne 'cc4dda537a7c352392b9cdeebfbc08c7980a23a679247b5f8b69570f752cdebe'){throw 'Candidate constraint profile changed'}
$stage=Join-Path ([IO.Path]::GetTempPath()) ('pds_axil_'+[guid]::NewGuid().ToString('N'))
if($stage -match '[^\x00-\x7F]' -or (Test-Path -LiteralPath $stage)){throw 'Need unused ASCII stage'}
New-Item -ItemType Directory -Path $stage | Out-Null
$sources=@{'VexAxilCpu.v'=(Join-Path $AxilCpuBuild 'rtl/VexAxilCpu.v');'mini_uart.v'=$uart;'mini_first_board.fdc'=$fdc}
foreach($name in @('bridge.sv','soc.sv','mini_soc_first_board.v','analysis.tcl')){$sources[$name]=Join-Path $PSScriptRoot $name}
foreach($name in @('firmware.hex','expected.hex','config.vh','coverage.json','program.dis')){$sources[$name]=Join-Path $SocRun $name}
foreach($file in Get-ChildItem -LiteralPath (Join-Path $AxilCpuBuild 'rtl') -Filter '*.bin'){$sources[$file.Name]=$file.FullName}
$hashes=foreach($name in $sources.Keys){
 Copy-Item -LiteralPath $sources[$name] -Destination (Join-Path $stage $name)
 [pscustomobject]@{File=$name;SHA256=(Get-FileHash -LiteralPath (Join-Path $stage $name)).Hash}
}
$hashes | Export-Csv -LiteralPath (Join-Path $stage 'inputs.csv') -NoTypeInformation
Write-Output "STAGE=$stage"
Push-Location $stage
try{
 & $PdsShell -file "$($stage.Replace('\','/'))/analysis.tcl" -work_dir $stage -project_name axil_analysis 2>&1 | Tee-Object -FilePath (Join-Path $stage 'console.log')
 $result=$LASTEXITCODE
}finally{Pop-Location}
if($result -ne 0){throw "PDS exit $result; inspect retained logs"}
Write-Output 'Process returned. check_pds.py and netlist regression still required.'
