#!/usr/bin/env python3
"""Regenerate the record list in Docs/acceptance/README.md.

Only the block between the index markers is rewritten; text outside it is
hand-maintained. Run with --check to fail (exit 1) when the index is stale.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ACCEPTANCE = ROOT / "Docs" / "acceptance"
INDEX = ACCEPTANCE / "README.md"
START, END = "<!-- index:start -->", "<!-- index:end -->"
DATED = re.compile(r"^(\d{4})-(\d{2})-(\d{2})-.+\.md$")


def title_of(path: pathlib.Path) -> str:
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if line.startswith("# "):
            return line[2:].strip().replace("|", "\\|")
    return path.stem


def render() -> str:
    records = sorted(
        (p for p in ACCEPTANCE.glob("*.md") if DATED.match(p.name)),
        key=lambda p: p.name,
        reverse=True,
    )
    lines, month = [START, ""], None
    for p in records:
        y, m, d = DATED.match(p.name).groups()
        if (y, m) != month:
            if month:
                lines.append("")
            month = (y, m)
            lines += [f"### {y}-{m}", "", "| 日期 | 记录 |", "| --- | --- |"]
        lines.append(f"| {m}-{d} | [{title_of(p)}]({p.name}) |")
    lines += ["", f"共 {len(records)} 份带日期记录。", END]
    return "\n".join(lines)


def main() -> int:
    text = INDEX.read_text(encoding="utf-8")
    head, _, rest = text.partition(START)
    _, _, tail = rest.partition(END)
    updated = head + render() + tail
    if "--check" in sys.argv:
        if updated != text:
            print("Docs/acceptance/README.md is stale; run Scripts/generate-acceptance-index.py")
            return 1
        return 0
    INDEX.write_text(updated, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
