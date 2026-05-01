"""pytest bootstrap for the catalog adapters.

Adds the repo root to ``sys.path`` so adapters can be imported as
``tool.asset_catalog.sources.<name>`` without requiring the user to
configure PYTHONPATH or run pytest with ``-m``.
"""
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
