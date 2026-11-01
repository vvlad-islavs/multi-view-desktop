"""Scenario helpers: process launch + assertions + report writing."""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from collections import deque
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path

from .client import E2eError, MvdE2eClient
from .report import CaseResult, begin_report, finish_report, format_exc, record_case

# tool/multiview_e2e/mvd_e2e/runner.py → repo root is parents[3]
REPO_ROOT = Path(__file__).resolve().parents[3]
EXAMPLE_DIR = REPO_ROOT / "example"


def default_base_url() -> str:
    port = os.environ.get("MVD_E2E_PORT", "9876")
    host = os.environ.get("MVD_E2E_HOST", "127.0.0.1")
    return f"http://{host}:{port}"


def default_device() -> str:
    if sys.platform == "darwin":
        return "macos"
    if sys.platform.startswith("win"):
        return "windows"
    return "linux"


@contextmanager
def launched_example(
    *,
    device: str | None = None,
    port: int | None = None,
    extra_defines: list[str] | None = None,
    extra_env: dict[str, str] | None = None,
    ready_timeout: float = 120.0,
    allow_exit: bool = False,
) -> Iterator[tuple[MvdE2eClient, subprocess.Popen[str]]]:
    """Start `flutter run` for example with MVD_E2E harness, yield client, then kill."""
    device = device or default_device()
    port = port if port is not None else int(os.environ.get("MVD_E2E_PORT", "9876"))
    env = os.environ.copy()
    env["MVD_E2E_PORT"] = str(port)
    if extra_env:
        env.update(extra_env)

    defines = [
        "--dart-define=MVD_E2E=true",
        f"--dart-define=MVD_E2E_PORT={port}",
        # Bust const dart-define cache when macos params / other defines change.
        f"--dart-define=MVD_E2E_EPOCH={time.time_ns()}",
    ]

    # macOS .app often does not inherit custom env; materialize params to a file
    # and point the app at it via dart-define (path is compile-time; file is runtime).
    macos_file: Path | None = None
    if extra_env and (
        "MVD_E2E_CLOSE_APP_AFTER_LAST" in extra_env
        or "MVD_E2E_SAVE_LAST_WINDOW" in extra_env
    ):
        tool_dir = EXAMPLE_DIR / ".dart_tool"
        tool_dir.mkdir(parents=True, exist_ok=True)
        macos_file = tool_dir / f"mvd_e2e_macos_params_{port}.json"
        payload: dict[str, bool] = {}
        if "MVD_E2E_CLOSE_APP_AFTER_LAST" in extra_env:
            payload["closeAppAfterLastWindowClosed"] = _env_truthy(
                extra_env["MVD_E2E_CLOSE_APP_AFTER_LAST"]
            )
        if "MVD_E2E_SAVE_LAST_WINDOW" in extra_env:
            payload["saveLastWindowToReopen"] = _env_truthy(
                extra_env["MVD_E2E_SAVE_LAST_WINDOW"]
            )
        macos_file.write_text(json.dumps(payload), encoding="utf-8")
        defines.append(f"--dart-define=MVD_E2E_MACOS_PARAMS_FILE={macos_file}")

    if extra_defines:
        defines.extend(extra_defines)

    # On Windows, `flutter` is a .bat — CreateProcess needs cmd.exe.
    flutter = ["cmd", "/c", "flutter"] if sys.platform.startswith("win") else ["flutter"]
    cmd = [
        *flutter,
        "run",
        "-d",
        device,
        *defines,
    ]

    proc = subprocess.Popen(
        cmd,
        cwd=str(EXAMPLE_DIR),
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    # Verbose native MVD logs fill the pipe and deadlock Flutter if unread.
    startup_output: deque[str] = deque(maxlen=40)
    teardown_errors: deque[str] = deque(maxlen=40)

    def _drain_stdout() -> None:
        if proc.stdout is None:
            return
        try:
            for line in proc.stdout:
                startup_output.append(line.rstrip())
                if re.search(r"View #\d+ doesn't exist", line):
                    teardown_errors.append(line.rstrip())
        except Exception:  # noqa: BLE001
            pass

    drain_thread = threading.Thread(
        target=_drain_stdout, name="mvd-e2e-drain", daemon=True
    )
    drain_thread.start()
    client = MvdE2eClient(base_url=f"http://127.0.0.1:{port}")
    try:
        try:
            client.wait_ready(timeout=ready_timeout)
        except E2eError as error:
            output = "\n".join(startup_output)
            raise E2eError(
                f"{error}\nFlutter exit code: {proc.poll()}\nLast output:\n{output}"
            ) from error
        # Primary FlView first-frame / GLX must settle before secondary create on X11.
        try:
            client.call("wait_open_settle")
        except Exception:  # noqa: BLE001
            time.sleep(1.5)
        yield client, proc
        if not allow_exit and proc.poll() is not None:
            raise E2eError(f"Flutter process exited early with code {proc.returncode}")
    finally:
        _terminate(proc)
        drain_thread.join(timeout=2)
        if macos_file is not None:
            try:
                macos_file.unlink(missing_ok=True)
            except OSError:
                pass
    if teardown_errors:
        raise E2eError("Duplicate engine-view removal:\n" + "\n".join(teardown_errors))


def _env_truthy(raw: str | None, *, default: bool = False) -> bool:
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in {"1", "true", "yes"}


def _harness_reachable(client: MvdE2eClient) -> bool:
    try:
        client.ping()
        return True
    except Exception:  # noqa: BLE001
        return False


def _wait_for_exit(
    client: MvdE2eClient,
    proc: subprocess.Popen[str] | None,
    *,
    timeout: float = 15.0,
) -> None:
    """Succeed when the OS process exits and/or the harness stops responding."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        proc_dead = proc is not None and proc.poll() is not None
        if proc_dead or not _harness_reachable(client):
            return
        time.sleep(0.2)
    proc_dead = proc is not None and proc.poll() is not None
    if proc_dead or not _harness_reachable(client):
        return
    raise E2eError("Expected app/harness exit, but process is still alive")


def _terminate(proc: subprocess.Popen[str]) -> None:
    if proc.poll() is not None:
        return
    try:
        if sys.platform.startswith("win"):
            # flutter.bat runs through cmd.exe; stopping only that parent leaves
            # Flutter and the example alive with the harness port still bound.
            subprocess.run(
                ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=8,
            )
        else:
            proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.kill()
    except Exception:  # noqa: BLE001
        pass


def run_scenario(
    name: str,
    fn: Callable[[MvdE2eClient], None],
    *,
    launch: bool = True,
    capture_snapshots: bool = True,
    expect_exit: bool = False,
    extra_defines: list[str] | None = None,
    extra_env: dict[str, str] | None = None,
) -> bool:
    """Run one case, append to the active report, return True on success.

    When ``expect_exit`` is True, the scenario is allowed to tear down the app
    (``close_app`` / primary cascade). Connection drops during the case are OK;
    success means the process/harness is gone afterwards.
    """
    print(f"==> {name}", flush=True)
    started = time.perf_counter()
    snap_before = None
    snap_after = None
    try:
        if not launch:
            client = MvdE2eClient(default_base_url())
            client.wait_ready(timeout=30)
            if capture_snapshots:
                try:
                    snap_before = client.snapshot()
                except Exception:  # noqa: BLE001
                    snap_before = None
            try:
                fn(client)
            except AssertionError:
                raise
            except Exception:
                if not expect_exit:
                    raise
                # Mid-RPC teardown (e.g. closing primary) often resets the socket.
            if expect_exit:
                _wait_for_exit(client, None)
            elif capture_snapshots:
                try:
                    snap_after = client.snapshot()
                except Exception:  # noqa: BLE001
                    snap_after = None
        else:
            with launched_example(
                allow_exit=expect_exit,
                extra_defines=extra_defines,
                extra_env=extra_env,
            ) as (client, proc):
                if capture_snapshots:
                    try:
                        snap_before = client.snapshot()
                    except Exception:  # noqa: BLE001
                        snap_before = None
                try:
                    fn(client)
                except AssertionError:
                    raise
                except Exception:
                    if not expect_exit:
                        raise
                if expect_exit:
                    _wait_for_exit(client, proc)
                else:
                    time.sleep(0.3)
                    if proc.poll() is not None:
                        raise E2eError(
                            f"Process died during scenario (code={proc.returncode})"
                        )
                    client.assert_alive()
                    if capture_snapshots:
                        try:
                            snap_after = client.snapshot()
                        except Exception:  # noqa: BLE001
                            snap_after = None

        duration = time.perf_counter() - started
        record_case(
            CaseResult(
                name=name,
                status="passed",
                duration_sec=duration,
                snapshot_before=snap_before,
                snapshot_after=snap_after,
            )
        )
        print(f"OK  {name} ({duration:.2f}s)")
        return True
    except Exception as exc:  # noqa: BLE001 — record then fail case
        duration = time.perf_counter() - started
        err, tb = format_exc(exc)
        record_case(
            CaseResult(
                name=name,
                status="failed",
                duration_sec=duration,
                error=err,
                traceback=tb,
                snapshot_before=snap_before,
                snapshot_after=snap_after,
            )
        )
        print(f"FAIL {name} ({duration:.2f}s): {err}")
        return False


def finalize_and_exit(ok: bool) -> None:
    finish_report(write=True)
    raise SystemExit(0 if ok else 1)
