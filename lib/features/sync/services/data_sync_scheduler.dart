import 'dart:async';
import '../../../core/di/injector.dart';
import '../repositories/data_sync_repository.dart';

/// Drives the "every 1 hour while the app is open" auto-sync requirement
/// with a plain in-app timer — no OS-level background execution.
class DataSyncScheduler {
  static const interval = Duration(hours: 1);

  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => getIt<DataSyncRepository>().syncNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Call when the app resumes from background — syncs immediately if the
  /// app was backgrounded past [interval], instead of waiting for the next
  /// timer tick.
  Future<void> checkOnResume() async {
    final repo = getIt<DataSyncRepository>();
    final lastSyncedAt = await repo.getLastSyncedAt();
    if (lastSyncedAt == null || DateTime.now().difference(lastSyncedAt) > interval) {
      await repo.syncNow();
    }
  }
}
