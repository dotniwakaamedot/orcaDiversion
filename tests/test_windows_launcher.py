import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

STAGE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("launcher", STAGE / "adapters/windows/run_issue_review_hidden.py")
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class LauncherTests(unittest.TestCase):
    def test_failure_records_only_fixed_fields(self):
        with tempfile.TemporaryDirectory(prefix="workflow-launcher-test-") as temp:
            print("scratch=" + temp)
            state = Path(temp) / "state"
            config = Path(temp) / "config.json"
            config.write_text(json.dumps({"state_root": str(state)}), encoding="utf-8")
            for error, expected in [(None, "runner_failed"), (OSError("secret-value"), "runner_start_failed")]:
                with patch.object(sys, "argv", ["launcher", "--config", str(config)]), patch.object(launcher.subprocess, "run") as run:
                    if error:
                        run.side_effect = error
                    else:
                        run.return_value = subprocess.CompletedProcess([], 7)
                    result = launcher.main()
                    self.assertEqual(result, 1 if error else 7)
                    kwargs = run.call_args.kwargs
                    self.assertEqual(kwargs["stdin"], subprocess.DEVNULL)
                    self.assertEqual(kwargs["stdout"], subprocess.DEVNULL)
                    self.assertEqual(kwargs["stderr"], subprocess.DEVNULL)
                    self.assertEqual(kwargs["creationflags"], subprocess.CREATE_NO_WINDOW)
                    self.assertIn("-WindowStyle", run.call_args.args[0])
                paths = list((state / "launcher-errors").glob("*.json"))
                record = json.loads(paths[-1].read_text(encoding="utf-8"))
                self.assertEqual(set(record), {"schema_version", "time", "outcome", "exit_code"})
                self.assertEqual(record["outcome"], expected)
                self.assertNotIn("secret-value", json.dumps(record))
                for path in paths:
                    path.unlink()
        print("scratch_exists=" + str(Path(temp).exists()))

    def test_invalid_relative_config_never_starts_process(self):
        with patch.object(sys, "argv", ["launcher", "--config", "relative.json"]), patch.object(launcher.subprocess, "run") as run:
            self.assertEqual(launcher.main(), 1)
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
