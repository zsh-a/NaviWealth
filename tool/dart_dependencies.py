"""Resolve local Dart import/export edges for the architecture lint gates."""

from collections.abc import Iterator
from pathlib import Path
import re
from typing import NamedTuple


_TOKENS = re.compile(
    r"(?P<comment>//[^\n]*|/\*.*?\*/)"
    r"|(?P<string>r?(?:'''[\s\S]*?'''|\"\"\"[\s\S]*?\"\"\""
    r"|'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"))"
    r"|(?P<directive>\b(?:import|export)\b)"
    r"|(?P<end>;)",
    re.DOTALL,
)


class DartDependency(NamedTuple):
    line: int
    directive: str
    uri: str
    target: Path


def feature_for_path(path: Path, features_root: Path) -> str | None:
    try:
        relative = path.resolve().relative_to(features_root.resolve())
    except ValueError:
        return None
    return relative.parts[0] if relative.parts else None


def iter_dart_dependencies(path: Path, lib_root: Path) -> Iterator[DartDependency]:
    """Include every conditional URI; ignore comments and string examples."""
    source = path.read_text(encoding="utf-8")
    directive = None
    for token in _TOKENS.finditer(source):
        if token.lastgroup == "directive":
            directive = token.group()
        elif token.lastgroup == "end":
            directive = None
        elif token.lastgroup == "string" and directive is not None:
            value = token.group()
            if value.startswith("r"):
                value = value[1:]
            uri = value[1:-1]
            if uri.startswith("package:naviwealth/"):
                target = lib_root / uri.removeprefix("package:naviwealth/")
            elif ":" not in uri:
                target = path.parent / uri
            else:
                continue
            yield DartDependency(
                source.count("\n", 0, token.start()) + 1,
                directive,
                uri,
                target.resolve(),
            )
