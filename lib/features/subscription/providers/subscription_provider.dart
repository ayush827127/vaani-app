import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/injector.dart';
import '../models/subscription_status.dart';
import '../repositories/subscription_repository.dart';

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionStatus?>(
        (ref) => SubscriptionNotifier());

class SubscriptionNotifier extends StateNotifier<SubscriptionStatus?> {
  SubscriptionNotifier() : super(null) {
    _loadCached();
  }

  Future<void> _loadCached() async {
    state = await getIt<SubscriptionRepository>().getCachedStatus();
  }

  /// Triggers a backend re-check and reloads the cache into state. Safe to
  /// call anytime (offline included) — the underlying repository call never
  /// throws.
  Future<void> refresh() async {
    await getIt<SubscriptionRepository>().refreshStatus();
    await _loadCached();
  }

  /// Re-reads the on-disk cache into state without hitting the network.
  /// Use after something else has already refreshed the cache from the
  /// backend — e.g. DataSyncRepository.syncNow(), which is a plain GetIt
  /// singleton with no Riverpod [ref] of its own, so it can update
  /// SharedPreferences but can't push the change into this provider's
  /// in-memory state on its own.
  Future<void> reloadFromCache() async {
    await _loadCached();
  }

  /// Whether [moduleKey] should be accessible right now. Fails open if no
  /// successful check has ever completed (brand-new/offline signup) —
  /// otherwise delegates to SubscriptionStatus.isModuleEnabled, the same
  /// grace-period logic the router redirect in app_router.dart also uses,
  /// so a button's enabled/disabled look and the route it points at can
  /// never disagree with each other.
  bool isModuleEnabled(String moduleKey) {
    final cached = state;
    if (cached == null) return true;
    return cached.isModuleEnabled(moduleKey);
  }
}
