"""Exercise dependency gate bypasses with isolated, invalid Dart fixtures."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


TOOL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_ROOT))
from dart_dependencies import iter_dart_dependencies


class DependencyGateTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.lib = self.root / "apps/mobile/lib"
        (self.lib / "features").mkdir(parents=True)
        (self.root / "tool").mkdir()
        for name in (
            "dart_dependencies.py",
            "lint-no-feature-in-shared.sh",
            "lint-cross-feature-imports.sh",
        ):
            shutil.copyfile(TOOL_ROOT / name, self.root / "tool" / name)

    def source(self, relative, contents):
        path = self.lib / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def gate(self, name):
        return subprocess.run(
            ["bash", str(self.root / "tool" / name)],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_shared_gate_rejects_relative_conditional_exports(self):
        for layer in ("core", "design_system"):
            with self.subTest(layer=layer):
                path = self.source(
                    f"{layer}/surface.dart",
                    "export\n 'stub.dart'\n"
                    " if (dart.library.io) '../features/finance/model.dart';\n",
                )
                result = self.gate("lint-no-feature-in-shared.sh")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("../features/finance/model.dart", result.stderr)
                path.unlink()

    def test_cross_feature_gate_covers_finance_life_and_new_features(self):
        for feature in ("finance", "life", "new_feature"):
            with self.subTest(feature=feature):
                path = self.source(
                    f"features/{feature}/surface.dart",
                    "export 'package:naviwealth/features/health/model.dart';\n",
                )
                result = self.gate("lint-cross-feature-imports.sh")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"{feature} exports features/health", result.stderr)
                path.unlink()

    def test_cross_feature_gate_rejects_conditional_relative_imports(self):
        self.source(
            "features/finance/ui/surface.dart",
            "import 'stub.dart' if (dart.library.io) "
            "'../../knowledge/model.dart';\n",
        )
        result = self.gate("lint-cross-feature-imports.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("finance imports features/knowledge", result.stderr)

    def test_same_feature_and_infrastructure_edges_pass(self):
        self.source(
            "features/finance/ui/surface.dart",
            "import '../data/repository.dart';\n"
            "export 'package:naviwealth/features/finance/domain/model.dart';\n"
            "import 'package:naviwealth/core/contracts.dart';\n",
        )
        self.source(
            "core/surface.dart",
            "import 'dart:async';\n"
            "import 'package:flutter/widgets.dart';\n"
            "export '../design_system/tokens.dart';\n",
        )
        for name in ("lint-cross-feature-imports.sh", "lint-no-feature-in-shared.sh"):
            with self.subTest(gate=name):
                result = self.gate(name)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_comments_and_string_examples_do_not_create_edges(self):
        path = self.source(
            "core/surface.dart",
            "// import 'package:naviwealth/features/finance/model.dart';\n"
            "/*\nexport '../features/health/model.dart';\n*/\n"
            "const example = '''\n"
            "import '../features/knowledge/model.dart';\n''';\n"
            "import /* comment */ '../design_system/tokens.dart';\n",
        )
        edges = list(iter_dart_dependencies(path, self.lib))
        self.assertEqual([edge.uri for edge in edges], ["../design_system/tokens.dart"])
        result = self.gate("lint-no-feature-in-shared.sh")
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
