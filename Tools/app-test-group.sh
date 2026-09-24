#!/usr/bin/env bash
# 把 KanpanTests 里某几组（= Kanpan/KanpanTests/ 下的子目录）翻成 xcodebuild 的
# `-only-testing:KanpanTests/<套件>` 参数，给 Makefile 的 symbols-test / settings-test 这些目标用。
#
#   Tools/app-test-group.sh Symbols Settings      → 这两组里全部顶层套件
#   Tools/app-test-group.sh --except Main         → 除 Main 之外的所有组
#
# 套件 = 文件顶层声明的 struct / class / enum（或顶层 extension），且它那一段里至少有一条 `@Test`。
# 只按目录分组，不另维护名单：往某组目录里加一个测试文件，对应的 make 目标自动就跑它。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 - "$ROOT/Kanpan/KanpanTests" "$@" <<'PY'
import os, re, sys
base, args = sys.argv[1], sys.argv[2:]
groups = sorted(d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d)))
if args[:1] == ["--except"]:
    chosen = [g for g in groups if g not in args[1:]]
else:
    chosen = args
missing = [g for g in chosen if g not in groups]
if missing or not chosen:
    sys.exit(f"没有这一组：{missing or '（空）'}；现有 {groups}")
decl = re.compile(r'^(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|final)\s+)*'
                  r'(struct|class|enum|actor|extension)\s+([A-Za-z_][A-Za-z0-9_]*)')
top = re.compile(r'^\S')
suites = set()
for g in chosen:
    for dirpath, _, files in os.walk(os.path.join(base, g)):
        for f in sorted(files):
            if not f.endswith(".swift"):
                continue
            current = None
            for line in open(os.path.join(dirpath, f), encoding="utf-8"):
                if top.match(line) and not line.startswith(("//", "}", "#", "@")):
                    m = decl.match(line)
                    current = m.group(2) if m else None
                elif top.match(line) and line.startswith("@"):
                    m = decl.match(line)
                    if m:
                        current = m.group(2)
                if current and "@Test" in line and not line.lstrip().startswith("//"):
                    suites.add(current)
for s in sorted(suites):
    print(f"-only-testing:KanpanTests/{s}")
PY
