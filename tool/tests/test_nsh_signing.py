"""Fail-closed signing orchestration; CI verifies the real keystore and APK."""

import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "sign-nsh-apk.sh"
CERTIFICATE = b"public fixture certificate"


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        tools = self.root / "sdk/build-tools/35.0.1"
        tools.mkdir(parents=True)
        self.input = self.root / "packaged.apk"
        self.input.write_bytes(b"packaged input")
        self.output = self.root / "release.apk"
        self.calls = self.root / "calls.jsonl"
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "ANDROID_HOME": str(self.root / "sdk"),
            "RUNNER_TEMP": str(self.root),
            "KEYSTORE_BASE64": base64.b64encode(b"private fixture keystore").decode(),
            "KEYSTORE_PASSWORD": "store-secret-sentinel",
            "KEY_PASSWORD": "different-key-secret-sentinel",
            "KEY_ALIAS": "release",
            "CALLS": str(self.calls),
            "CERTIFICATE_SHA": hashlib.sha256(CERTIFICATE).hexdigest(),
        }
        keytool = self.bin / "keytool"
        keytool.write_text(
            "#!/usr/bin/env python3\n"
            "import os,sys,json\nfrom pathlib import Path\n"
            "with open(os.environ['CALLS'],'a') as f: f.write(json.dumps(sys.argv)+'\\n')\n"
            f"Path(sys.argv[sys.argv.index('-file')+1]).write_bytes({CERTIFICATE!r})\n"
        )
        keytool.chmod(0o755)
        apksigner = tools / "apksigner"
        apksigner.write_text(
            "#!/usr/bin/env python3\n"
            "import os,sys,json,shutil\n"
            "with open(os.environ['CALLS'],'a') as f: f.write(json.dumps(sys.argv)+'\\n')\n"
            "if sys.argv[1]=='sign':\n"
            " shutil.copyfile(sys.argv[-1],sys.argv[sys.argv.index('--out')+1])\n"
            "else:\n"
            " if os.environ.get('FAIL_VERIFY'): sys.exit(1)\n"
            " digest='wrong' if os.environ.get('MISMATCH') else os.environ['CERTIFICATE_SHA']\n"
            " print('Signer #1 certificate SHA-256 digest: '+digest)\n"
            " print('Signer #1 certificate DN: CN='+('Android Debug' if os.environ.get('DEBUG_CERT') else 'Release'))\n"
        )
        apksigner.chmod(0o755)

    def run_signer(self):
        result = subprocess.run(
            ["bash", str(SCRIPT), str(self.input), str(self.output)],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )
        # Neither subprocess arguments nor logs may contain password values.
        evidence = result.stdout + result.stderr
        if self.calls.exists():
            evidence += self.calls.read_text()
        self.assertNotIn(self.env["KEYSTORE_PASSWORD"], evidence)
        self.assertNotIn(self.env["KEY_PASSWORD"], evidence)
        self.assertEqual(list(self.root.glob("naviwealth-signing.*")), [])
        return result

    def test_matching_release_certificate_keeps_the_apk_and_uses_env_passwords(self):
        result = self.run_signer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_bytes(), self.input.read_bytes())
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        sign = next(args for args in calls if args[1] == "sign")
        self.assertIn("env:KEYSTORE_PASSWORD", sign)
        self.assertIn("env:KEY_PASSWORD", sign)

    def test_missing_signing_secret_fails_without_an_apk(self):
        self.env["KEYSTORE_BASE64"] = ""
        self.assertNotEqual(self.run_signer().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_verification_failure_removes_the_apk_and_key_material(self):
        self.env["FAIL_VERIFY"] = "1"
        self.assertNotEqual(self.run_signer().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_wrong_certificate_removes_the_apk(self):
        self.env["MISMATCH"] = "1"
        self.assertNotEqual(self.run_signer().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_debug_certificate_is_rejected_even_if_it_matches_the_keystore(self):
        self.env["DEBUG_CERT"] = "1"
        self.assertNotEqual(self.run_signer().returncode, 0)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
