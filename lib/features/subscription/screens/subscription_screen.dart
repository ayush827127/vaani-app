import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/injector.dart';
import '../models/plan.dart';
import '../models/payment_claim.dart';
import '../models/voice_usage.dart';
import '../models/subscription_status.dart';
import '../providers/subscription_provider.dart';
import '../repositories/subscription_repository.dart';
import '../services/upi_payment_service.dart';

const _moduleLabels = {
  'billing': 'Voice & manual billing',
  'inventory': 'Inventory management',
  'customers': 'Customer records',
  'reports': 'Sales reports',
  'ai_manager': 'AI Manager',
  'printer': 'Receipt printing',
  'notifications': 'In-app notifications',
};

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _loading = true;
  String? _loadError;
  List<Plan> _plans = [];
  List<PaymentClaim> _claims = [];
  VoiceUsage? _voiceUsage;

  // Which plan a Pay/Switch action is currently in flight for — disables
  // just that button rather than the whole screen, and doubles as a guard
  // against a double-tap starting two payment claims for the same plan.
  String? _actingOnPlanId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final repo = getIt<SubscriptionRepository>();
    try {
      // Sequential, not Future.wait — three requests landing on Render's
      // free-tier instance in the same instant was reproducibly enough load
      // to make some of them fail outright (confirmed via on-device logs:
      // one sibling got a clean 200 while another got back a generic
      // server-level failure, all fired within the same millisecond). One
      // at a time costs a bit of latency but is what the backend can
      // actually handle reliably.
      final plans = await repo.listPlans();
      final claims = await repo.listMyPaymentClaims();
      final voiceUsage = await repo.getVoiceUsage();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _claims = claims;
        _voiceUsage = voiceUsage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _refreshStatusOnly() async {
    await ref.read(subscriptionProvider.notifier).refresh();
    await _load();
  }

  Future<void> _switchToFree(Plan plan) async {
    setState(() => _actingOnPlanId = plan.id);
    try {
      await getIt<SubscriptionRepository>().switchToFreePlan(plan.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Switched to ${plan.name}'),
        backgroundColor: AppColors.success,
      ));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _actingOnPlanId = null);
    }
  }

  Future<void> _payForPlan(Plan plan) async {
    setState(() => _actingOnPlanId = plan.id);
    try {
      // Generated once per attempt and used for both the UPI transaction
      // note/ref and the payment-claim's idempotency key, so an admin can
      // match the two, and a retried submission for the same intended
      // payment (e.g. this call succeeding but the response getting lost)
      // reuses the same claim instead of creating a duplicate one.
      final reference = const Uuid().v4();

      try {
        await UpiPaymentService.launch(amount: plan.price, reference: reference);
      } on UpiPaymentException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.error,
        ));
        return;
      }

      // Recording the claim only after the UPI app actually opened (not
      // before) — if no UPI app exists, nothing is submitted at all. Either
      // way, opening the UPI app is never itself proof of payment — see
      // UpiPaymentService's doc comment — so this claim starts PENDING and
      // stays that way until an admin confirms it.
      await getIt<SubscriptionRepository>().submitPaymentClaim(
        planId: plan.id,
        reference: reference,
        amount: plan.price,
      );

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: context.colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Payment submitted', style: TextStyle(color: context.colors.textPrimary)),
          content: Text(
            "We've recorded your ₹${plan.price.toStringAsFixed(0)} payment for ${plan.name}. "
            "It'll be verified and activated shortly — usually within a few hours. "
            'You can keep using the app in the meantime.',
            style: TextStyle(color: context.colors.textSecondary),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$e'),
        backgroundColor: AppColors.error,
      ));
    } finally {
      if (mounted) setState(() => _actingOnPlanId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = ref.watch(subscriptionProvider);
    final pendingClaim = _claims.where((claim) => claim.isPending).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription', style: TextStyle(fontWeight: FontWeight.w600)),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _refreshStatusOnly,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
          : _loadError != null
              ? _ErrorState(message: _loadError!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primaryLight,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _CurrentStatusCard(status: status, voiceUsage: _voiceUsage),
                      if (pendingClaim != null) ...[
                        const SizedBox(height: 12),
                        _PendingClaimBanner(claim: pendingClaim),
                      ],
                      const SizedBox(height: 20),
                      Text('Plans',
                          style: TextStyle(
                              color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      for (final plan in _plans) ...[
                        _PlanCard(
                          plan: plan,
                          isCurrent: plan.name == status?.effectivePlanName,
                          busy: _actingOnPlanId == plan.id,
                          onAction: plan.isFree ? () => _switchToFree(plan) : () => _payForPlan(plan),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Payments are verified manually after you pay via UPI — this can take '
                          'a few hours. Your current plan keeps working until then.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textDisabled, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
    );
  }
}

class _CurrentStatusCard extends StatelessWidget {
  final SubscriptionStatus? status;
  final VoiceUsage? voiceUsage;
  const _CurrentStatusCard({required this.status, required this.voiceUsage});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: AppColors.primaryLight, size: 28),
              const SizedBox(width: 10),
              Text(
                status?.effectivePlanName ?? 'Basic',
                style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (status?.shopStatus == 'SUSPENDED' || status?.shopStatus == 'CANCELLED')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(status!.shopStatus,
                      style: TextStyle(color: c.danger, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          if (status?.endDate != null) ...[
            const SizedBox(height: 8),
            Text(
              'Renews / expires: ${_formatDate(status!.endDate!)}',
              style: TextStyle(color: c.textSecondary, fontSize: 12),
            ),
          ],
          if (voiceUsage != null && !voiceUsage!.unlimited) ...[
            const SizedBox(height: 14),
            _VoiceUsageBar(usage: voiceUsage!),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

class _VoiceUsageBar extends StatelessWidget {
  final VoiceUsage usage;
  const _VoiceUsageBar({required this.usage});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final limit = usage.limit ?? 1;
    final fraction = (usage.used / limit).clamp(0.0, 1.0);
    final nearLimit = usage.used >= limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Voice invoices used', style: TextStyle(color: c.textSecondary, fontSize: 12)),
            const Spacer(),
            Text(
              '${usage.used} / ${usage.limit}',
              style: TextStyle(
                  color: nearLimit ? c.danger : c.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: c.surfaceBorder,
            valueColor: AlwaysStoppedAnimation(nearLimit ? c.danger : AppColors.primaryLight),
          ),
        ),
        if (nearLimit) ...[
          const SizedBox(height: 6),
          Text(
            'Limit reached — upgrade to Pro for unlimited voice billing.',
            style: TextStyle(color: c.danger, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _PendingClaimBanner extends StatelessWidget {
  final PaymentClaim claim;
  const _PendingClaimBanner({required this.claim});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF8C00).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, color: Color(0xFFFF8C00), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Payment of ₹${claim.amount.toStringAsFixed(0)} for ${claim.planName} is awaiting '
              'verification.',
              style: TextStyle(color: c.textPrimary, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool isCurrent;
  final bool busy;
  final VoidCallback onAction;

  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.busy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? AppColors.primaryLight : c.surfaceBorder,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(plan.name,
                  style: TextStyle(
                      color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('CURRENT PLAN',
                      style: TextStyle(
                          color: AppColors.primaryLight, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              const Spacer(),
              Text(
                plan.isFree ? 'Free' : '₹${plan.price.toStringAsFixed(0)}/mo',
                style: TextStyle(
                    color: AppColors.primaryLight, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...plan.modules.map((key) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: c.success),
                    const SizedBox(width: 8),
                    Text(_moduleLabels[key] ?? key,
                        style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  ],
                ),
              )),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: isCurrent
                ? OutlinedButton(
                    onPressed: null,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Current plan'),
                  )
                : ElevatedButton(
                    onPressed: busy ? null : onAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryLight,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(plan.isFree ? 'Switch to ${plan.name}' : 'Pay ₹${plan.price.toStringAsFixed(0)} via UPI'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: c.textSecondary),
            const SizedBox(height: 12),
            Text("Couldn't load plans", style: TextStyle(color: c.textPrimary, fontSize: 15)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 12)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
