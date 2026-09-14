#!/usr/bin/env python3
"""skill の構造を決定的に検査する。意味の検査は skill-audit が行う。

引数は skills root (`<name>/SKILL.md` を含むディレクトリ)、プロジェクトルート、
または skill 配下のファイル。省略時は chezmoi の skills root を見る。
"""

import os
import re
import subprocess
import sys
from pathlib import Path

# TODO(未決定): 閾値の根拠は「現状の最大 + 少しの余裕」でしかない。
# 実際に超えて削った経験が溜まったら決め直す。
SKILL_MAX_LINES = 250
REFERENCE_MAX_LINES = 100

LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")


def chezmoi_skills_root() -> Path | None:
    try:
        out = subprocess.run(
            ["chezmoi", "source-path"], capture_output=True, text=True, check=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    root = Path(out) / "skills"
    return root if root.is_dir() else None


def skills_roots(arg: Path) -> tuple[list[Path], Path | None]:
    """引数から skills root と、絞り込む skill を引く。

    ファイルを渡されたら、その skill だけを見る。編集していない skill の違反を混ぜると、
    直す気のないものが毎回出て読まれなくなる。
    """
    p = arg.resolve()
    while p != p.parent:
        if (p / "SKILL.md").is_file():
            return [p.parent], p
        if p.name == "skills" and p.is_dir():
            return [p], None
        for sub in (".agents/skills", ".claude/skills"):
            if (p / sub).is_dir():
                # .claude/skills は .agents/skills への symlink 置き場なので、両方見る
                return [p / s for s in (".agents/skills", ".claude/skills") if (p / s).is_dir()], None
        p = p.parent
    return [], None


def frontmatter(text: str) -> dict[str, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    body, key = {}, None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        m = re.match(r"^([a-z-]+):\s*(.*)$", line)
        if m:
            key = m.group(1)
            body[key] = m.group(2).strip()
        elif key and line.strip():
            body[key] = (body[key] + " " + line.strip()).strip()
    return body


def check_skill(d: Path, out: list[str]) -> None:
    skill_md = d / "SKILL.md"
    text = skill_md.read_text(encoding="utf-8")
    n = len(text.splitlines())
    if n > SKILL_MAX_LINES:
        out.append(f"{skill_md}:1 — {n} 行。警報ライン {SKILL_MAX_LINES} を超えた。削る対象を探す")

    fm = frontmatter(text)
    if fm.get("name") != d.name:
        out.append(f"{skill_md}:1 — frontmatter の name ({fm.get('name')!r}) がディレクトリ名 ({d.name}) と違う")
    if not fm.get("description"):
        out.append(f"{skill_md}:1 — frontmatter に description が無い")

    for ref in sorted((d / "references").glob("*.md")) if (d / "references").is_dir() else []:
        rn = len(ref.read_text(encoding="utf-8").splitlines())
        if rn > REFERENCE_MAX_LINES:
            out.append(f"{ref}:1 — {rn} 行。警報ライン {REFERENCE_MAX_LINES} を超えた")

    for md in [skill_md, *sorted((d / "references").glob("*.md"))] if (d / "references").is_dir() else [skill_md]:
        for i, line in enumerate(md.read_text(encoding="utf-8").splitlines(), 1):
            for target in LINK.findall(line):
                target = target.split("#", 1)[0].strip()
                if not target or "://" in target or target.startswith("mailto:"):
                    continue
                if not (md.parent / target).exists():
                    out.append(f"{md}:{i} — リンク先が無い: {target}")


def find_origin(name: str, root: Path) -> Path | None:
    """fork 元の skill を、同じ root と共通の skills root から探す。"""
    for base in (root, Path.home() / ".claude" / "skills", chezmoi_skills_root()):
        if base is None:
            continue
        cand = base / name
        if (cand / "SKILL.md").is_file():
            return cand
    return None


def check_audit(d: Path, root: Path, out: list[str]) -> None:
    """AUDIT.md は宣言があるときだけ検査する。無いことは違反ではない。

    存在確認だけでは中身が古びても通るので、落とした工程の逐語引用を fork 元と照合する。
    """
    audit = d / "AUDIT.md"
    if not audit.is_file():
        return
    text = audit.read_text(encoding="utf-8")

    if "AUDIT.md" in (d / "SKILL.md").read_text(encoding="utf-8"):
        out.append(f"{audit}:1 — SKILL.md から参照されている。ここはエージェントが読まない場所である")

    m = re.search(r"^fork 元:\s*(\S+)\s*$", text, re.M)
    if m is None:
        out.append(f"{audit}:1 — 「fork 元: <skill 名>」の行が無い")
        return
    origin = find_origin(m.group(1), root)
    if origin is None:
        out.append(f"{audit}:1 — fork 元 {m.group(1)} が見つからない")
        return

    origin_text = (origin / "SKILL.md").read_text(encoding="utf-8")
    body = text.split("## 落とした工程", 1)
    if len(body) == 1:
        out.append(f"{audit}:1 — 「## 落とした工程」の節が無い")
        return
    for i, line in enumerate(text.splitlines(), 1):
        if not line.startswith("- ") or " — " not in line:
            continue
        quote = line[2:].split(" — ", 1)[0].strip()
        if quote and quote not in origin_text:
            out.append(f"{audit}:{i} — 逐語引用が fork 元 ({origin.name}) に無い: {quote}")


def check_symlinks(root: Path, out: list[str]) -> None:
    """.claude/skills が .agents/skills を指しているか。切れても静かに skill が消えるだけなので見る。"""
    if root.name != "skills" or root.parent.name != ".agents":
        return
    mirror = root.parent.parent / ".claude" / "skills"
    if not mirror.is_dir():
        return
    for d in sorted(root.iterdir()):
        if not (d / "SKILL.md").is_file():
            continue
        link = mirror / d.name
        if not link.exists():
            out.append(f"{link} — .agents/skills/{d.name} に対応する symlink が無い。この skill は読まれない")
        elif link.resolve() != d.resolve():
            out.append(f"{link} — symlink の指す先が {link.resolve()} で、{d} と違う")
    for link in sorted(mirror.iterdir()):
        if link.name.startswith("."):
            continue
        if not link.exists():
            out.append(f"{link} — symlink が切れている")


def check_home_mirror(root: Path, out: list[str]) -> None:
    """chezmoi の skills/ は apply 対象外で、~/.claude/skills/ から symlink される。"""
    if root != (chezmoi_skills_root() or Path("/nonexistent")):
        return
    home = Path.home() / ".claude" / "skills"
    if not home.is_dir():
        return
    for d in sorted(root.iterdir()):
        if not (d / "SKILL.md").is_file():
            continue
        link = home / d.name
        if not link.exists():
            out.append(f"{link} — chezmoi の skills/{d.name} が ~/.claude/skills/ から辿れない")


def main(argv: list[str]) -> int:
    args = [Path(a) for a in argv[1:]]
    if not args:
        root = chezmoi_skills_root()
        if root is None:
            print("chezmoi の skills root が引けない", file=sys.stderr)
            return 1
        args = [root]

    roots: list[Path] = []
    focus: set[Path] = set()
    for a in args:
        rs, f = skills_roots(a)
        for r in rs:
            if r not in roots:
                roots.append(r)
        if f is not None:
            focus.add(f)

    out: list[str] = []
    for root in roots:
        for d in sorted(root.iterdir()):
            if not (d / "SKILL.md").is_file():
                continue
            target = d.resolve() if d.is_symlink() else d
            if focus and target not in focus and d not in focus:
                continue
            check_skill(target, out)
            check_audit(target, root, out)
        check_symlinks(root, out)
        check_home_mirror(root, out)

    for line in dict.fromkeys(out):
        print(line)
    return 1 if out else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
