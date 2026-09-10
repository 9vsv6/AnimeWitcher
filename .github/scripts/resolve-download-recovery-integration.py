from pathlib import Path


def parse_conflicts(text: str):
    out: list[str] = []
    conflicts: list[tuple[list[str], list[str]]] = []
    lines = text.splitlines(keepends=True)
    i = 0
    while i < len(lines):
        if not lines[i].startswith("<<<<<<< "):
            out.append(lines[i])
            i += 1
            continue
        i += 1
        ours: list[str] = []
        while i < len(lines) and not lines[i].startswith("======="):
            ours.append(lines[i])
            i += 1
        if i >= len(lines):
            raise SystemExit("unterminated conflict")
        i += 1
        theirs: list[str] = []
        while i < len(lines) and not lines[i].startswith(">>>>>>> "):
            theirs.append(lines[i])
            i += 1
        if i >= len(lines):
            raise SystemExit("unterminated conflict")
        i += 1
        out.append(f"__CONFLICT_{len(conflicts)}__\n")
        conflicts.append((ours, theirs))
    return "".join(out), conflicts


def resolve_parallel(path: str) -> None:
    file = Path(path)
    skeleton, conflicts = parse_conflicts(file.read_text())
    resolved: list[str] = []
    for ours, theirs in conflicts:
        ours_text = "".join(ours)
        theirs_text = "".join(theirs)
        if "schemaVersion" in ours_text and "parentTaskId" in theirs_text:
            resolved.append(
                """        final schemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? 1;
        if (schemaVersion < 1 ||
            schemaVersion > kParallelManifestSchemaVersion) {
          continue;
        }
        final parentTaskId = json['parentTaskId']?.toString().trim();
        if (parentTaskId != null &&
            parentTaskId.isNotEmpty &&
            parentTaskId != task.taskId) {
          continue;
        }
        final savedGeneration = (json['generation'] as num?)?.toInt() ?? 0;
        final checkpointSequence =
            (json['checkpointSequence'] as num?)?.toInt() ?? 0;
        final declaredTotalBytes =
            (json['totalBytes'] as num?)?.toInt() ??
            (json['expectedBytes'] as num?)?.toInt() ??
            -1;
        if (savedGeneration < 0 || checkpointSequence < 0) continue;
"""
            )
        elif "savedValidator" in ours_text and "checkpointSequence" in theirs_text:
            resolved.append(
                """        var contiguous = parts.first.from == 0;
        for (var index = 1; index < parts.length && contiguous; index++) {
          contiguous = parts[index].from == parts[index - 1].to + 1;
        }
        if (!contiguous) continue;
        final calculatedBytes = parts.fold<int>(
          0,
          (sum, part) => sum + part.size,
        );
        final savedExpectedBytes =
            (json['expectedBytes'] as num?)?.toInt() ?? -1;
        if (savedExpectedBytes > 0 && savedExpectedBytes != calculatedBytes) {
          continue;
        }
        final savedValidator = json['resourceValidator'] is String
            ? (json['resourceValidator'] as String).trim()
            : '';
        final session = _ParallelSession(
          task,
          manifest,
          parts,
          generation: savedGeneration,
          resourceValidator: savedValidator.isEmpty ? null : savedValidator,
        )..checkpointSequence = checkpointSequence;
        _applyPinnedValidatorToPendingParts(session);
"""
            )
        elif "'resourceValidator'" in ours_text and "'checkpointSequence'" in theirs_text:
            resolved.append(
                """      'parentTaskId': session.task.taskId,
      'generation': session.generation,
      'checkpointSequence': session.checkpointSequence,
      'expectedBytes': session.size,
      'totalBytes': session.size,
      'resourceValidator': session.resourceValidator,
"""
            )
        elif "String? resourceValidator" in ours_text and "checkpointSequence" in theirs_text:
            resolved.append(
                """  int generation;
  int checkpointSequence = 0;
  String? resourceValidator;
"""
            )
        else:
            raise SystemExit(
                "unrecognized persistent_parallel conflict\n"
                f"OURS:\n{ours_text}\nTHEIRS:\n{theirs_text}"
            )
    for index, value in enumerate(resolved):
        skeleton = skeleton.replace(f"__CONFLICT_{index}__\n", value, 1)
    if "<<<<<<<" in skeleton or ">>>>>>>" in skeleton:
        raise SystemExit("unresolved persistent_parallel marker")

    # Phase 1 introduced schema v2 independently, while Phase 2 advanced the
    # same manifest to v3. Keep the v3 declaration and remove the obsolete
    # duplicate block produced by the branch merge.
    obsolete_schema_block = """/// Multipart recovery checkpoints are versioned snapshots. The sequence is
/// monotonic so a crash after flushing manifest.json.tmp but before rename
/// can restore the newer snapshot instead of silently accepting an older
/// manifest.json.
const int kParallelManifestSchemaVersion = 2;

"""
    skeleton = skeleton.replace(obsolete_schema_block, "", 1)
    if skeleton.count("const int kParallelManifestSchemaVersion") != 1:
        raise SystemExit("manifest schema declaration is not unique after merge")
    file.write_text(skeleton)


def resolve_auto_recovery(path: str) -> None:
    file = Path(path)
    skeleton, conflicts = parse_conflicts(file.read_text())
    if len(conflicts) != 1:
        raise SystemExit(f"expected one auto recovery conflict, got {len(conflicts)}")
    ours, theirs = conflicts[0]
    marker = "    'repeated system pauses recover the child without pausing the episode',\n"
    try:
        split = ours.index(marker)
    except ValueError as exc:
        raise SystemExit("repeated pause test marker not found in ours") from exc
    combined = "".join(ours[:split]) + "".join(theirs)
    skeleton = skeleton.replace("__CONFLICT_0__\n", combined, 1)
    if "<<<<<<<" in skeleton or ">>>>>>>" in skeleton:
        raise SystemExit("unresolved auto recovery marker")
    file.write_text(skeleton)


resolve_parallel("lib/core/services/persistent_parallel_download.dart")
resolve_auto_recovery("test/core/services/persistent_parallel_download_auto_recovery_test.dart")
