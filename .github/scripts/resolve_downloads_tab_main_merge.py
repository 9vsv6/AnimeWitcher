import argparse
import re
import subprocess
from pathlib import Path

PATH = Path('test/features/library/presentation/downloads_tab_test.dart')
SAFE_TITLE = 'deleting the last episode preserves unknown series-folder evidence'
UNSAFE_TITLE = 'deleting the last episode removes the series folder leftover files and all'
SAFE_START = "  testWidgets(\n    'deleting the last episode preserves unknown series-folder evidence'"
UNSAFE_START = "  testWidgets(\n    'deleting the last episode removes the series folder leftover files and all'"
NEXT_MARKER = "\n  testWidgets('delete also removes sibling .part .tmp .download temps'"
TITLE_RE = re.compile(r"\b(?:test|testWidgets)\s*\(\s*(['\"])(.*?)\1", re.S)


def git_show(ref: str) -> str:
    return subprocess.check_output(
        ['git', 'show', f'{ref}:{PATH.as_posix()}'], text=True
    )


def titles(text: str) -> set[str]:
    return {match.group(2) for match in TITLE_RE.finditer(text)}


def prove_semantic_conflict(ours: str, theirs: str) -> None:
    ours_titles = titles(ours)
    theirs_titles = titles(theirs)
    missing = ours_titles - theirs_titles
    print(f'feature test titles: {len(ours_titles)}')
    print(f'main test titles: {len(theirs_titles)}')
    if missing != {SAFE_TITLE}:
        raise SystemExit(f'unexpected feature tests missing from main: {sorted(missing)}')
    if UNSAFE_TITLE not in theirs_titles:
        raise SystemExit('expected legacy destructive cleanup test is not present in main')
    if SAFE_TITLE in theirs_titles:
        raise SystemExit('main unexpectedly already contains the DM-14 safe cleanup test')


def replace_block(theirs: str, ours: str) -> str:
    safe_start = ours.find(SAFE_START)
    safe_end = ours.find(NEXT_MARKER, safe_start)
    unsafe_start = theirs.find(UNSAFE_START)
    unsafe_end = theirs.find(NEXT_MARKER, unsafe_start)
    if min(safe_start, safe_end, unsafe_start, unsafe_end) < 0:
        raise SystemExit('could not isolate the cleanup-contract test blocks')
    safe_block = ours[safe_start:safe_end]
    return theirs[:unsafe_start] + safe_block + theirs[unsafe_end:]


def rooted_call(indent: str, target: str) -> str:
    inner = indent + '  '
    return (
        f'{indent}await deleteDownloadedVideo(\n'
        f'{inner}{target},\n'
        f'{inner}appDownloadRoots: [\n'
        f"{inner}  p.join(root.path, 'AnimeWitcher', 'Downloads'),\n"
        f'{inner}],\n'
        f'{indent});'
    )


def inject_test_roots(text: str) -> str:
    patterns = [
        (re.compile(r'(?m)^(\s*)await deleteDownloadedVideo\(resolved\);$'), 'resolved', 1),
        (re.compile(r'(?m)^(\s*)await deleteDownloadedVideo\(video\);$'), 'video', 2),
    ]
    for pattern, target, expected in patterns:
        matches = list(pattern.finditer(text))
        if len(matches) != expected:
            raise SystemExit(
                f'expected {expected} unrooted delete calls for {target}, found {len(matches)}'
            )
        text = pattern.sub(lambda match: rooted_call(match.group(1), target), text)
    return text


def verify_result(merged: str, ours: str, theirs: str) -> None:
    ours_titles = titles(ours)
    theirs_titles = titles(theirs)
    merged_titles = titles(merged)
    expected_titles = ours_titles | (theirs_titles - {UNSAFE_TITLE})
    if merged_titles != expected_titles:
        missing = sorted(expected_titles - merged_titles)
        extra = sorted(merged_titles - expected_titles)
        raise SystemExit(f'merged test-title mismatch; missing={missing}, extra={extra}')
    if UNSAFE_TITLE in merged_titles:
        raise SystemExit('legacy destructive cleanup contract survived resolution')
    if merged.count('appDownloadRoots: [') < 3:
        raise SystemExit('trusted-root coverage is incomplete in cleanup tests')
    if 'await deleteDownloadedVideo(resolved);' in merged:
        raise SystemExit('unrooted resolved-file deletion survived test migration')
    if 'await deleteDownloadedVideo(video);' in merged:
        raise SystemExit('unrooted video deletion survived test migration')
    print(
        f'merged presentation tests: {len(merged_titles)} titles; '
        'DM-14 safe contract and explicit test roots preserved'
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--mode', choices=('preflight', 'resolve'), required=True)
    args = parser.parse_args()

    ours = git_show('HEAD')
    theirs = git_show('origin/main')
    prove_semantic_conflict(ours, theirs)
    if args.mode == 'preflight':
        return

    merged = replace_block(theirs, ours)
    merged = inject_test_roots(merged)
    verify_result(merged, ours, theirs)
    PATH.write_text(merged)


if __name__ == '__main__':
    main()
