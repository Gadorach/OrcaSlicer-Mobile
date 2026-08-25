#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import argparse
import shutil


def copy_tree_contents(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for item in source.iterdir():
        target = destination / item.name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True, symlinks=False)
        else:
            shutil.copy2(item, target, follow_symlinks=True)


def overlay_occt_source_headers(source_root: Path, destination: Path) -> int:
    src_root = source_root / "src"
    if not src_root.is_dir():
        return 0
    candidates: dict[str, list[Path]] = {}
    for ext in ("*.hxx", "*.lxx", "*.gxx"):
        for path in src_root.rglob(ext):
            if path.is_file():
                candidates.setdefault(path.name, []).append(path)
    copied = 0
    for name, paths in candidates.items():
        target = destination / name
        if target.is_file():
            continue
        chosen = paths[0]
        if len(paths) > 1:
            first = chosen.read_bytes()
            if any(other.read_bytes() != first for other in paths[1:]):
                continue
        shutil.copy2(chosen, target, follow_symlinks=True)
        copied += 1
    return copied


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    work = args.work_dir.expanduser().resolve()

    boost_dest = root / "app/src/main/jniImports/boost/include"
    boost_header = boost_dest / "boost/beast/core/detail/base64.hpp"
    if not boost_header.is_file():
        for source in (
            boost_dest / "boost-1_85",
            work / "Boost-for-Android/build/out/arm64-v8a/include/boost-1_85",
        ):
            if (source / "boost/beast/core/detail/base64.hpp").is_file():
                copy_tree_contents(source, boost_dest)
                break

    occt_dest = root / "app/src/main/occt/include/arm64-v8a"
    sentinel = occt_dest / "TDF_LabelSequence.hxx"
    if not sentinel.is_file():
        for source in (
            occt_dest / "opencascade",
            work / "OCCT/build-android/include/opencascade",
            work / "OCCT/build-android/inc",
        ):
            if source.is_dir():
                copy_tree_contents(source, occt_dest)
                if sentinel.is_file():
                    break
    if not sentinel.is_file():
        copied = overlay_occt_source_headers(work / "OCCT", occt_dest)
        if copied:
            print(f"[COMPAT] filled {copied} missing flat OCCT public headers")

    missing = []
    if not boost_header.is_file():
        missing.append(str(boost_header.relative_to(root)))
    if not sentinel.is_file():
        missing.append(str(sentinel.relative_to(root)))
    if missing:
        raise SystemExit("generated dependency headers remain incomplete:\n  " + "\n  ".join(missing))
    print("[OK] OpenGantry fork dependency imports normalized")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
