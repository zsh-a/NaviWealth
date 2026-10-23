"""Reject business contracts in every shared contract file."""

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

TOOL_ROOT = Path(__file__).resolve().parents[1]


class DomainNeutralContractTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.lib = self.root / "apps/mobile/lib"
        (self.lib / "core/ai/contracts").mkdir(parents=True)
        (self.lib / "core/sync").mkdir(parents=True)
        (self.root / "tool").mkdir()
        self.script = self.root / "tool/lint-domain-neutral-contracts.sh"
        shutil.copyfile(TOOL_ROOT / self.script.name, self.script)

    def gate(self):
        return subprocess.run(
            ["bash", str(self.script)], capture_output=True, text=True, check=False
        )

    def test_rejects_real_business_type_names_and_suffixes(self):
        path = self.lib / "core/ai/contracts/context.dart"
        for name in (
            "AccountSummary", "AccountBalanceSnapshot", "CashflowSummary",
            "FireGoalSummary", "HoldingSnapshot", "SleepSessionSummary",
        ):
            with self.subTest(name=name):
                path.write_text(f"class {name} {{}}\n")
                result = self.gate()
                self.assertEqual(result.returncode, 1)
                self.assertIn(name, result.stderr)

    def test_no_file_exemption_can_hide_a_business_type(self):
        for relative in (
            "core/ai/contracts/intent.dart",
            "core/ai/contracts/tool_descriptor.dart",
            "core/sync/domain_prefix.dart",
        ):
            with self.subTest(path=relative):
                path = self.lib / relative
                path.write_text("final AccountSummary? summary = null;\n")
                result = self.gate()
                self.assertEqual(result.returncode, 1)
                self.assertIn("AccountSummary", result.stderr)
                path.unlink()

    def test_neutral_contracts_and_domain_namespace_literals_pass(self):
        (self.lib / "core/ai/contracts/context.dart").write_text(
            "class AgentRuntimeContextBlock {}\n"
            "class ContextPackMemory {}\n"
            "const domain = 'finance';\n"
            "const source = 'health:health_metrics';\n"
        )
        self.assertEqual(self.gate().returncode, 0)


if __name__ == "__main__":
    unittest.main()
