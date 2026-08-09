import base64, json, pathlib, subprocess, zlib
parts = sorted(pathlib.Path('.github/patch-parts').glob('part*.txt'))
payload = ''.join(path.read_text().strip() for path in parts)
data = json.loads(zlib.decompress(base64.b64decode(payload)))
patch = pathlib.Path('/tmp/comments.patch')
patch.write_text(data['patch'], encoding='utf-8')
subprocess.run(['git','apply','--whitespace=nowarn',str(patch)], check=True)
for path, content in data['new_files'].items():
    target = pathlib.Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8')
checks = [
    ('lib/core/account/animewitcher_account_service.dart','toggleCommentLike'),
    ('lib/core/account/firestore_rest_client.dart','queryReplies'),
    ('lib/features/comments/presentation/animewitcher_comments_screen.dart','AnimeWitcherRepliesScreen'),
    ('lib/features/comments/presentation/animewitcher_comments_screen.dart','extentAfter < 520'),
    ('lib/features/comments/presentation/animewitcher_comments_screen.dart','الأكثر اعجابا'),
]
for path, needle in checks:
    if needle not in pathlib.Path(path).read_text(encoding='utf-8'):
        raise SystemExit(f'validation failed: {path}: {needle}')
if not pathlib.Path('lib/features/comments/presentation/animewitcher_replies_screen.dart').is_file():
    raise SystemExit('validation failed: replies screen missing')
subprocess.run(['git','config','user.name','github-actions[bot]'], check=True)
subprocess.run(['git','config','user.email','41898282+github-actions[bot]@users.noreply.github.com'], check=True)
for path in parts: path.unlink()
pathlib.Path('.github/patch-parts/apply.py').unlink()
pathlib.Path('.github/workflows/apply-animewitcher-comment-interactions.yml').unlink()
subprocess.run(['git','add','-A'], check=True)
subprocess.run(['git','commit','-m','Fix AnimeWitcher comment interactions'], check=True)
subprocess.run(['git','push','origin','HEAD:main'], check=True)
