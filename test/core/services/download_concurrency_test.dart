import 'package:animewitcher/core/services/download_concurrency.dart';
import 'package:animewitcher/core/storage/settings_repository.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_storage_service.dart';

void main() {
  group('clampDownloadConcurrency', () {
    test('default sequential cap is 1', () {
      expect(kDownloadConcurrencyDefault, 1);
      expect(parseDownloadConcurrency(null), 1);
    });

    test('clamps to 1–5', () {
      expect(clampDownloadConcurrency(0), 1);
      expect(clampDownloadConcurrency(-3), 1);
      expect(clampDownloadConcurrency(1), 1);
      expect(clampDownloadConcurrency(3), 3);
      expect(clampDownloadConcurrency(5), 5);
      expect(clampDownloadConcurrency(6), 5);
      expect(clampDownloadConcurrency(10), 5);
    });

    test('parses numeric storage values and ignores junk', () {
      expect(parseDownloadConcurrency(4), 4);
      expect(parseDownloadConcurrency(4.9), 5);
      expect(parseDownloadConcurrency('3'), 1);
      expect(parseDownloadConcurrency(true), 1);
    });
  });

  group('holding queue tuple', () {
    test('uses the user N with unconstrained host and group', () {
      expect(downloadHoldingQueueValue(1), (1, null, null));
      expect(downloadHoldingQueueValue(3), (3, null, null));
      expect(downloadHoldingQueueValue(99), (5, null, null));

      final config = downloadHoldingQueueGlobalConfig(2);
      expect(config, hasLength(1));
      expect(config.single.$1, Config.holdingQueue);
      expect(config.single.$2, (2, null, null));
    });
  });

  group('applyDownloadQueueSettings', () {
    test(
      'writes the clamped value and the holding-queue configure tuple',
      () async {
        final storage = MemoryStorageService();
        List<(String, dynamic)>? configured;

        final applied = await applyDownloadQueueSettings(
          maxConcurrent: 9,
          persist: storage.setDownloadConcurrency,
          configure: (globalConfig) async {
            configured = globalConfig;
          },
        );

        expect(applied, 5);
        expect(storage.getDownloadConcurrency(), 5);
        expect(configured, <(String, dynamic)>[
          (Config.holdingQueue, (5, null, null)),
        ]);
      },
    );

    test(
      'sequential default persists as 1 and waits extras behind one slot',
      () async {
        final storage = MemoryStorageService();
        late List<(String, dynamic)> configured;

        await applyDownloadQueueSettings(
          maxConcurrent: 1,
          persist: storage.setDownloadConcurrency,
          configure: (globalConfig) async {
            configured = globalConfig;
          },
        );

        expect(storage.getDownloadConcurrency(), 1);
        expect(configured.single.$2, (1, null, null));
      },
    );
  });

  group('queue gate / overlay', () {
    test('waiting metadata is only the queueWaiting flag', () {
      expect(isQueueWaitingMetadata(null), isFalse);
      expect(isQueueWaitingMetadata({'queueWaiting': false}), isFalse);
      expect(
        isQueueWaitingMetadata({kDownloadQueueWaitingMetadataKey: true}),
        isTrue,
      );
    });

    test('only running/enqueued/waitingToRetry occupy a slot', () {
      expect(occupiesDownloadSlot(status: TaskStatus.running), isTrue);
      expect(occupiesDownloadSlot(status: TaskStatus.enqueued), isTrue);
      expect(occupiesDownloadSlot(status: TaskStatus.waitingToRetry), isTrue);
      expect(occupiesDownloadSlot(status: TaskStatus.paused), isFalse);
      expect(
        occupiesDownloadSlot(status: TaskStatus.enqueued, queueWaiting: true),
        isFalse,
      );
      expect(
        occupiesDownloadSlot(status: TaskStatus.paused, queueWaiting: true),
        isFalse,
      );
    });

    test('queue-waiting paused rows display as enqueued (في الانتظار)', () {
      expect(
        displayDownloadStatus(persisted: TaskStatus.paused, queueWaiting: true),
        TaskStatus.enqueued,
      );
      expect(
        displayDownloadStatus(
          persisted: TaskStatus.paused,
          queueWaiting: false,
        ),
        TaskStatus.paused,
      );
      expect(
        displayDownloadStatus(
          persisted: TaskStatus.running,
          queueWaiting: false,
        ),
        TaskStatus.running,
      );
    });

    test('Live Activity starts only when the OS will enqueue', () {
      expect(shouldStartDownloadLiveActivity(willEnqueueWithOs: true), isTrue);
      expect(
        shouldStartDownloadLiveActivity(willEnqueueWithOs: false),
        isFalse,
      );
      expect(
        shouldStartDownloadLiveActivity(
          willEnqueueWithOs:
              admitDownload(occupiedSlots: 0, maxConcurrent: 1) ==
              DownloadAdmission.enqueueNow,
        ),
        isTrue,
      );
      expect(
        shouldStartDownloadLiveActivity(
          willEnqueueWithOs:
              admitDownload(occupiedSlots: 1, maxConcurrent: 1) ==
              DownloadAdmission.enqueueNow,
        ),
        isFalse,
      );
    });

    test('overflow parks instead of enqueueing when concurrency is 1', () {
      expect(
        admitDownload(occupiedSlots: 0, maxConcurrent: 1),
        DownloadAdmission.enqueueNow,
      );
      expect(
        admitDownload(occupiedSlots: 1, maxConcurrent: 1),
        DownloadAdmission.parkAsWaiting,
      );
      expect(
        admitDownload(occupiedSlots: 2, maxConcurrent: 3),
        DownloadAdmission.enqueueNow,
      );
    });

    test(
      'completing the running download promotes the oldest waiting, not user-paused',
      () {
        final planWhileRunning = planDownloadQueue(
          maxConcurrent: 1,
          entries: const [
            DownloadQueueEntry(
              taskId: 'ep3',
              status: TaskStatus.running,
              timestamp: 1,
            ),
            DownloadQueueEntry(
              taskId: 'ep4',
              status: TaskStatus.paused,
              timestamp: 2,
              queueWaiting: true,
            ),
            DownloadQueueEntry(
              taskId: 'ep5-user-paused',
              status: TaskStatus.paused,
              timestamp: 0,
            ),
          ],
        );
        expect(planWhileRunning.occupiedCount, 1);
        expect(planWhileRunning.idsToPromote, isEmpty);
        expect(planWhileRunning.waitingFifoIds, ['ep4']);
        expect(
          shouldStartDownloadLiveActivity(
            willEnqueueWithOs: planWhileRunning.idsToPromote.contains('ep4'),
          ),
          isFalse,
        );

        final afterComplete = planDownloadQueue(
          maxConcurrent: 1,
          entries: const [
            DownloadQueueEntry(
              taskId: 'ep3',
              status: TaskStatus.complete,
              timestamp: 1,
            ),
            DownloadQueueEntry(
              taskId: 'ep4',
              status: TaskStatus.paused,
              timestamp: 2,
              queueWaiting: true,
            ),
            DownloadQueueEntry(
              taskId: 'ep5-user-paused',
              status: TaskStatus.paused,
              timestamp: 0,
            ),
          ],
        );
        expect(afterComplete.occupiedCount, 0);
        expect(afterComplete.idsToPromote, ['ep4']);
        expect(afterComplete.idsToPromote, isNot(contains('ep5-user-paused')));
      },
    );

    test('lowering N parks the newest occupying download', () {
      final plan = planDownloadQueue(
        maxConcurrent: 1,
        entries: const [
          DownloadQueueEntry(
            taskId: 'older',
            status: TaskStatus.running,
            timestamp: 10,
          ),
          DownloadQueueEntry(
            taskId: 'newer',
            status: TaskStatus.running,
            timestamp: 20,
          ),
        ],
      );
      expect(plan.idsToPark, ['newer']);
      expect(plan.idsToPromote, isEmpty);
    });
  });

  group('SettingsRepository download concurrency', () {
    test('defaults to 1 and clamps writes', () async {
      final storage = MemoryStorageService();
      final repository = SettingsRepository(storage);

      expect(repository.getDownloadConcurrency(), 1);
      await repository.setDownloadConcurrency(0);
      expect(repository.getDownloadConcurrency(), 1);
      await repository.setDownloadConcurrency(4);
      expect(repository.getDownloadConcurrency(), 4);
      await repository.setDownloadConcurrency(99);
      expect(repository.getDownloadConcurrency(), 5);
    });
  });
}
