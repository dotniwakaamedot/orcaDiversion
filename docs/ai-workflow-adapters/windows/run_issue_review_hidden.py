"""Windows の pythonw.exe から非表示で Issue runner を実行する。"""
import argparse
import json
from pathlib import Path
import subprocess
from uuid import uuid4
from datetime import datetime, timezone


def record_failure(config_path, outcome, exit_code=None):
    try:
        config = json.loads(config_path.read_text(encoding="utf-8-sig"))
        state = Path(config["state_root"])
        if not state.is_absolute():
            return
        directory = state / "launcher-errors"
        directory.mkdir(parents=True, exist_ok=True)
        data = {"schema_version": 1, "time": datetime.now(timezone.utc).isoformat(),
                "outcome": outcome, "exit_code": exit_code}
        with (directory / (uuid4().hex + ".json")).open("x", encoding="utf-8") as stream:
            json.dump(data, stream)
    except (OSError, ValueError, TypeError, KeyError):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--preflight", action="store_true")
    args = parser.parse_args()
    if not args.config.is_absolute():
        return 1
    command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
               "-File", str(Path(__file__).with_name("run_issue_review.ps1")),
               "-ConfigPath", str(args.config)]
    if args.preflight:
        command.append("-Preflight")
    try:
        result = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW).returncode
        if result:
            record_failure(args.config, "runner_failed", result)
        return result
    except OSError:
        record_failure(args.config, "runner_start_failed")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
