from pathlib import Path

path = Path('test/core/services/persistent_parallel_download_progress_test.dart')
text = path.read_text()
if "import 'dart:async';" not in text:
    anchor = "import 'dart:io';\n"
    if text.count(anchor) != 1:
        raise SystemExit('could not add dart:async import exactly once')
    path.write_text(text.replace(anchor, "import 'dart:async';\nimport 'dart:io';\n", 1))
