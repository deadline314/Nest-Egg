"""Keep the local ComfyUI server alive while a batch generates: start it, notice a hang, restart it.

Used by comfy_api.run(); nothing here talks to the model. What counts as "stuck" (each is retried by restarting the server
and re-queueing the job, up to MAX_RETRIES times, then ComfyFailure is raised and the job is written to FAIL_LOG):

  - the server does not answer (crashed, or killed by an out-of-memory error)
  - no message at all from the server for STALL_S seconds while a job is queued (hung on the GPU; queue shows "running" forever)
    - COLD_STALL_S for the first job after a (re)start, because loading the models takes 3-4 minutes
  - the server log shows a fatal device out-of-memory error
  - the machine stays nearly out of RAM (under MIN_FREE_RAM_GB for LOW_RAM_S seconds in a row): restart before Windows swaps
    the whole desktop to death. Loading the 20 GB model briefly drops free RAM to ~0.1 GB, so a dip alone is not a hang

Settings come from environment variables so a batch can be tuned without editing code:
  COMFY_MAX_RETRIES (3)  COMFY_STALL_S (300)  COMFY_COLD_STALL_S (900)  COMFY_MIN_FREE_RAM_GB (0.4)  COMFY_LOW_RAM_S (90)
  COMFY_HOST (http://127.0.0.1:8188)  COMFY_LOG (server log path)  COMFY_FAIL_LOG (assets_src/work/comfy_failures.log)
"""
from __future__ import annotations

import contextlib
import ctypes
import json
import os
import re
import subprocess
import time
import urllib.request
from pathlib import Path

if os.name == "nt":
    import msvcrt
else:
    import fcntl

ROOT = Path(__file__).resolve().parents[2]
START_SCRIPT = Path(__file__).with_name("start_comfyui.ps1")
HOST = os.environ.get("COMFY_HOST", "http://127.0.0.1:8188")
FAIL_LOG = Path(os.environ.get("COMFY_FAIL_LOG", ROOT / "assets_src" / "work" / "comfy_failures.log"))

MAX_RETRIES = int(os.environ.get("COMFY_MAX_RETRIES", "3"))
STALL_S = float(os.environ.get("COMFY_STALL_S", "300"))
COLD_STALL_S = float(os.environ.get("COMFY_COLD_STALL_S", "900"))
MIN_FREE_RAM_GB = float(os.environ.get("COMFY_MIN_FREE_RAM_GB", "0.4"))
LOW_RAM_S = float(os.environ.get("COMFY_LOW_RAM_S", "90"))
DEAD_POLLS = 3  # consecutive failed polls (about 2 s apart) before the server counts as down

# Fatal device errors only. ComfyUI also prints "Ran out of memory when regular VAE decoding, retrying with tiled VAE
# decoding" and recovers by itself, so plain "out of memory" is not enough.
_FATAL_LOG = re.compile(r"OutOfMemoryError|UR_RESULT_ERROR_OUT_OF_(?:DEVICE|HOST)_MEMORY|UR_RESULT_ERROR_DEVICE_LOST|"
                        r"CUDA error: out of memory|std::bad_alloc|DefaultCPUAllocator: can't allocate memory")
_RECOVERED = re.compile(r"retrying with tiled", re.I)
_OOM_TEXT = re.compile(r"out of memory|OutOfMemory|OUT_OF_DEVICE_MEMORY|OUT_OF_HOST_MEMORY|DEVICE_LOST", re.I)


def _lock_root() -> Path:
    # Linked worktrees must serialize with generation in the primary checkout.
    result = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                            cwd=ROOT, capture_output=True, text=True)
    return Path(result.stdout.strip()).parent if result.returncode == 0 else ROOT


LOCK_PATH = _lock_root() / "assets_src" / "work" / "comfy.lock"


@contextlib.contextmanager
def server_lock():
    """One generation client at a time. Two clients on one server restart it under each other (seen in the first selftest)
    and double the memory pressure. The OS releases the lock when the process dies."""
    LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
    f = open(LOCK_PATH, "a+b")
    announced = False
    while True:
        try:
            f.seek(0)
            if os.name == "nt":
                msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError:
            if not announced:
                print("  [comfy] another GPU job is running; waiting for it to finish", flush=True)
                announced = True
            time.sleep(3)
    try:
        yield
    finally:
        f.seek(0)
        if os.name == "nt":
            msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        f.close()


class ComfyStalled(RuntimeError):
    """The server hung, died or ran out of memory; restarting it and re-queueing the job may help."""


class ComfyFailure(RuntimeError):
    """The job still failed after every retry. The message names the job and each attempt's reason."""


def is_oom_text(text: str) -> bool:
    return bool(_OOM_TEXT.search(text))


def server_up(timeout: float = 3.0) -> bool:
    try:
        return urllib.request.urlopen(HOST + "/system_stats", timeout=timeout).status == 200
    except OSError:
        return False


def server_warm() -> bool:
    """True when the server already ran a job (its model is loaded), so the next job starts fast."""
    try:
        return bool(json.load(urllib.request.urlopen(HOST + "/history?max_items=1", timeout=5)))
    except (OSError, ValueError):
        return False


def _start(*flags: str) -> None:
    cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(START_SCRIPT), *flags]
    r = subprocess.run(cmd, capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    if r.returncode != 0:
        raise ComfyStalled(f"start_comfyui.ps1 {' '.join(flags)} failed (exit {r.returncode}): {out[-600:]}")
    print(f"  [comfy] {out.splitlines()[-1] if out else 'started'}", flush=True)


def ensure_server() -> None:
    """Make sure a server answers; starts one when it is down."""
    if not server_up():
        _start()


_safe_mode = False  # set after an out-of-memory failure: every later restart in this process stays conservative


def restart_server(reason: str) -> None:
    """Kill and start ComfyUI. After a memory failure it comes back in -Safe mode (models unloaded after each job)."""
    global _safe_mode
    if is_oom_text(reason) or "RAM" in reason:
        _safe_mode = True
    print(f"  [comfy] restarting ComfyUI{' (safe mode)' if _safe_mode else ''}: {reason}", flush=True)
    _start("-Restart", *(["-Safe"] if _safe_mode else []))


def free_ram_gb() -> float:
    """Physical memory Windows can hand out right now (free + cache that can be dropped), in GB."""
    class Status(ctypes.Structure):
        _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong), ("total_phys", ctypes.c_ulonglong),
                    ("avail_phys", ctypes.c_ulonglong), ("total_page", ctypes.c_ulonglong), ("avail_page", ctypes.c_ulonglong),
                    ("total_virt", ctypes.c_ulonglong), ("avail_virt", ctypes.c_ulonglong), ("avail_ext", ctypes.c_ulonglong)]
    s = Status()
    s.length = ctypes.sizeof(s)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(s)):
        return float("inf")  # cannot tell: do not restart over it
    return s.avail_phys / 2**30


def log_path() -> Path | None:
    """The server log written by start_comfyui.ps1 (newest one when several installs exist)."""
    if os.environ.get("COMFY_LOG"):
        return Path(os.environ["COMFY_LOG"])
    found = [p for p in (Path(d) / "nest_egg" / "comfy.log" for d in (os.environ.get("COMFYUI_DIR", ""), "C:/ComfyUI", "D:/ComfyUI"))
             if p.parent.parent.exists() and p.exists()]
    return max(found, key=lambda p: p.stat().st_mtime) if found else None


def server_pid() -> int | None:
    """Process that owns the server port (for tests that freeze or kill it)."""
    port = HOST.rsplit(":", 1)[-1]
    r = subprocess.run(["powershell", "-NoProfile", "-Command",
                        f"(Get-NetTCPConnection -LocalPort {port} -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess"],
                       capture_output=True, text=True)
    return int(r.stdout.strip()) if r.stdout.strip().isdigit() else None


class Watchdog:
    """Per-job observer. Call wait() between polls; it raises ComfyStalled when the job should be abandoned."""

    def __init__(self, client_id: str):
        self.start = self.last_activity = time.monotonic()
        self.stall_s = STALL_S if server_warm() else COLD_STALL_S
        self.dead = 0
        self.low_ram_since = None
        self.ws = None
        self.log = log_path()
        self.log_pos = self.log.stat().st_size if self.log and self.log.exists() else 0
        try:  # progress and status messages are the heartbeat; without the websocket only the log and RAM checks remain
            from websockets.sync.client import connect
            self.ws = connect(HOST.replace("http", "ws", 1) + f"/ws?clientId={client_id}", open_timeout=10, max_size=None, ping_interval=None)
        except Exception as ex:  # noqa: BLE001 - library missing or server just died; polling still works
            print(f"  [comfy] no websocket heartbeat ({type(ex).__name__}); relying on log and RAM checks", flush=True)

    def close(self) -> None:
        if self.ws is not None:
            try:
                self.ws.close()
            except Exception:  # noqa: BLE001
                pass

    def _drain(self, seconds: float) -> None:
        end = time.monotonic() + seconds
        while True:
            left = end - time.monotonic()
            if left <= 0:
                return
            if self.ws is None:
                time.sleep(left)
                return
            try:
                self.ws.recv(timeout=left)
                self.last_activity = time.monotonic()
            except TimeoutError:
                return
            except Exception:  # noqa: BLE001 - socket closed: the poll below decides whether the server is gone
                self.ws = None

    def _new_log_text(self) -> str:
        if self.log is None or not self.log.exists():
            return ""
        size = self.log.stat().st_size
        if size < self.log_pos:  # log was recreated by a restart
            self.log_pos = 0
        with open(self.log, "rb") as f:
            f.seek(self.log_pos)
            data = f.read()
        self.log_pos = size
        return data.decode("utf-8", errors="ignore")

    def wait(self, seconds: float, poll_ok: bool) -> None:
        """Sleep/drain for `seconds`, then run the checks. poll_ok says whether the last HTTP poll succeeded."""
        self._drain(seconds)
        self.dead = 0 if poll_ok else self.dead + 1
        if self.dead >= DEAD_POLLS:
            raise ComfyStalled("server not answering")
        idle = time.monotonic() - self.last_activity
        if idle > self.stall_s:
            raise ComfyStalled(f"no progress for {idle:.0f} s (limit {self.stall_s:.0f} s)")
        for line in self._new_log_text().splitlines():
            if _FATAL_LOG.search(line) and not _RECOVERED.search(line):
                raise ComfyStalled(f"server log: {line.strip()[:200]}")
        ram = free_ram_gb()
        if ram >= MIN_FREE_RAM_GB:
            self.low_ram_since = None
        elif self.low_ram_since is None:
            self.low_ram_since = time.monotonic()
        elif time.monotonic() - self.low_ram_since > LOW_RAM_S:
            raise ComfyStalled(f"system RAM exhausted for {LOW_RAM_S:.0f} s ({ram:.2f} GB free, limit {MIN_FREE_RAM_GB} GB)")


def record_failure(job: str, reasons: list[str], prompt: str = "") -> str:
    """Append the failed job to FAIL_LOG and return the one-line message for the exception."""
    msg = f"job '{job}' failed after {len(reasons)} attempt(s): " + " | ".join(f"#{i + 1} {r}" for i, r in enumerate(reasons))
    FAIL_LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(FAIL_LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps({"time": time.strftime("%Y-%m-%d %H:%M:%S"), "job": job, "reasons": reasons, "prompt": prompt[:300]},
                           ensure_ascii=False) + "\n")
    return msg
