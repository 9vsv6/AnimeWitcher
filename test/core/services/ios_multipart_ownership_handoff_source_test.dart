import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DM-22 multipart promotion uses generation-fenced durable claims', () {
    final parallel = File(
      'lib/core/services/persistent_parallel_download.dart',
    ).readAsStringSync();
    final service = File(
      'lib/core/services/download_service.dart',
    ).readAsStringSync();
    final swift = File(
      'ios/Runner/DownloadNativeWaitingQueue.swift',
    ).readAsStringSync();

    expect(parallel, contains('class NativeParallelBackgroundCandidate'));
    expect(parallel, contains('final int generation;'));
    expect(parallel, contains('final String claimId;'));
    expect(parallel, contains('final Duration claimLease;'));
    expect(parallel, contains('_nativeClaimOffers'));
    expect(parallel, contains('!_hasActiveNativeClaimOffer(part)'));

    expect(service, contains("'generation': child.generation"));
    expect(service, contains("'claimId': child.claimId"));
    expect(
      service,
      contains("'claimLeaseMillis': child.claimLease.inMilliseconds"),
    );

    expect(swift, contains('struct MultipartClaim: Codable'));
    expect(swift, contains('var multipartClaims: [MultipartClaim]'));
    expect(swift, contains('requeueExpiredMultipartClaimsLocked(&current)'));
    expect(swift, contains(r'claimedChildIds.contains($0.taskId)'));
    expect(swift, contains('commitMultipartClaimBeforeResume(waiter)'));
    expect(swift, contains('guard !isAppInForeground() else'));
    expect(swift, contains('settleMultipartClaim(childTaskId: childId)'));

    final claimAppend = swift.indexOf('state.multipartClaims.append(');
    final startLoop = swift.indexOf('for waiter in selected {');
    expect(claimAppend, greaterThanOrEqualTo(0));
    expect(startLoop, greaterThan(claimAppend));

    final commit = swift.indexOf('commitMultipartClaimBeforeResume(waiter)');
    final resume = swift.indexOf('task.resume()', commit);
    expect(commit, greaterThanOrEqualTo(0));
    expect(resume, greaterThan(commit));
  });
}
