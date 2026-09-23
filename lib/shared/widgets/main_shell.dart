import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../../core/services/voice_recognition_service.dart';
import '../../core/theme/app_colors.dart';
import '../../features/billing/providers/billing_providers.dart';
import '../../features/printer/providers/printer_provider.dart';
import '../../features/subscription/providers/subscription_provider.dart';
import '../../l10n/l10n_extensions.dart';
import 'common_drawer.dart';
import 'shell_scaffold_key.dart';

class MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {

  // Tab 3 points to /customers — Customers replaces Bills as the primary
  // footer destination (the ledger/udhar view is what shopkeepers reach
  // for most); Bills is still fully there, just one tap further in: from
  // Home's recent bills, or a customer's own Bills tab. /billing (the
  // new-bill/checkout screen) stays reachable only via the mic button, as
  // before — it was never a footer destination itself.
  static const _routes = ['/home', '/inventory', '', '/customers', ''];

  static int _indexFromPath(String path) {
    if (path.startsWith('/home')) return 0;
    if (path.startsWith('/inventory')) return 1;
    if (path.startsWith('/customers')) return 3;
    if (path.startsWith('/profile')) return 4;
    // /billing (checkout) and /bills (the bill list, now reached from
    // inside a customer or Home rather than its own tab) are reached via
    // the mic button or a push from elsewhere — neither is a footer
    // destination anymore, so nothing here should light up as "current".
    if (path.startsWith('/billing') || path.startsWith('/bills')) return -1;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Trigger printer auto-reconnect on shell load (after first frame)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(printerProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Intercepts the Android hardware back button.
  /// GoRouter's own observer fires first; if it can't handle the pop
  /// (no shell history), it returns false and we get called here.
  /// Returning true tells Flutter "handled — don't call SystemNavigator.pop()".
  @override
  Future<bool> didPopRoute() async {
    if (!mounted) return false;
    final location = GoRouterState.of(context).uri.path;
    if (!location.startsWith('/home')) {
      context.go('/home');
      return true; // consumed — app stays open
    }
    return false; // on home — let the system exit the app
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _indexFromPath(location);

    final navBg = isDark ? AppColors.surfaceVariantDark : Colors.white;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.35)
        : Colors.black.withValues(alpha: 0.08);

    void onTap(int index) {
      if (index == 4) {
        context.go('/profile');
        return;
      }
      final route = _routes[index];
      if (route.isNotEmpty) context.go(route);
    }

    return Scaffold(
      key: shellScaffoldKey,
      drawer: const CommonDrawer(),
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          boxShadow: [BoxShadow(color: shadowColor, blurRadius: 12)],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _NavItem(icon: Icons.home_rounded,         label: l10n.home,      index: 0, current: currentIndex, onTap: onTap, cs: cs),
                _NavItem(icon: Icons.inventory_2_rounded,  label: l10n.items,     index: 1, current: currentIndex, onTap: onTap, cs: cs),
                const _VoiceFAB(),
                _NavItem(icon: Icons.people_alt_rounded,   label: l10n.customers, index: 3, current: currentIndex, onTap: onTap, cs: cs),
                _NavItem(icon: Icons.person_rounded,       label: l10n.profile,   index: 4, current: currentIndex, onTap: onTap, cs: cs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final void Function(int) onTap;
  final ColorScheme cs;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current == index;
    final activeColor = cs.primary;
    final inactiveColor = cs.onSurface.withValues(alpha: 0.45);

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isActive ? activeColor : inactiveColor, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? activeColor : inactiveColor,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Voice FAB ───────────────────────────

class _VoiceFAB extends ConsumerStatefulWidget {
  const _VoiceFAB();

  @override
  ConsumerState<_VoiceFAB> createState() => _VoiceFABState();
}

class _VoiceFABState extends ConsumerState<_VoiceFAB>
    with TickerProviderStateMixin {
  final _voice = VoiceRecognitionService.instance;
  bool _isPressed = false;
  String _partial = '';
  bool _gotFinalResult = false;

  // Ripple: continuous ring expansion while recording (2 s per cycle)
  late final AnimationController _ripple;
  // Scale: button grows on press (180 ms), shrinks on release
  late final AnimationController _scale;
  // Fade: aura fades in on press (350 ms), fades out on release
  late final AnimationController _fade;

  late final Animation<double> _scaleAnim;
  late final Listenable _allAnims;

  // Button base diameter — 21% larger than the original 48 px
  static const double _kFab = 58.0;
  // Maximum press scale factor (1.0 → 1.25 while held, per spec)
  static const double _kScaleMax = 1.25;
  // Aura rings: expand from button radius out to this maximum (~2.25× the button diameter)
  static const double _kRingMaxRadius = 130.0;

  @override
  void initState() {
    super.initState();

    _ripple = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: _kScaleMax).animate(
      CurvedAnimation(parent: _scale, curve: Curves.easeOutCubic),
    );

    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _allAnims = Listenable.merge([_ripple, _scale, _fade]);
  }

  @override
  void dispose() {
    _ripple.dispose();
    _scale.dispose();
    _fade.dispose();
    _voice.speech.stop();
    super.dispose();
  }

  // ─── gesture handlers ───────────────────────────────────────────

  bool _isBillingEnabled() =>
      ref.read(subscriptionProvider.notifier).isModuleEnabled('billing');

  void _showUpgradeMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Upgrade your plan to unlock Billing'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _onTap() {
    if (!_isBillingEnabled()) {
      _showUpgradeMessage();
      return;
    }
    context.go('/billing');
  }

  void _onLongPressStart(LongPressStartDetails _) async {
    if (!_isBillingEnabled()) {
      _showUpgradeMessage();
      return;
    }
    _isPressed = true;
    final loc = GoRouterState.of(context).uri.path;
    if (!loc.startsWith('/billing') ||
        loc.contains('voice') ||
        loc.contains('invoice')) {
      context.go('/billing');
      await Future.delayed(const Duration(milliseconds: 450));
    }
    if (!_isPressed || !mounted) return;
    await _beginListening();
  }

  void _onLongPressEnd(LongPressEndDetails _) => _finishAndProcess();

  void _onLongPressCancel() {
    if (!_isPressed) return;
    _isPressed = false;
    _voice.speech.stop();
    _scale.reverse();
    _fade.reverse().whenComplete(() {
      if (mounted) _ripple.stop();
    });
    if (mounted) {
      ref.read(pttRecordingProvider.notifier).state = false;
      ref.read(pttPartialTranscriptProvider.notifier).state = '';
    }
  }

  // ─── speech ─────────────────────────────────────────────────────

  Future<void> _beginListening() async {
    if (!_isPressed || !mounted) return;
    // ensureReady() only actually checks permission/initializes the first
    // time it's ever called anywhere in the app — every voice entry point
    // shares one VoiceRecognitionService instance, so pressing this button
    // again (or opening the voice sheet / Voice Billing screen) never
    // re-asks for microphone permission once it's been granted once.
    final ready = await _voice.ensureReady(
      context,
      onError: (e) {
        debugPrint('[PTT] STT error: ${e.errorMsg}');
        if (_isPressed) _finishAndProcess();
      },
      onStatus: (status) {
        debugPrint('[PTT] STT status: $status (pressed=$_isPressed)');
        // Do NOT call _finishAndProcess() here — Android fires 'notListening'
        // immediately after listen() on some devices, which would set _isPressed=false
        // before the user has spoken, making the physical button release a no-op.
      },
    );
    if (!ready || !mounted || !_isPressed) return;

    _partial = '';
    _gotFinalResult = false;
    ref.read(pttRecordingProvider.notifier).state = true;
    ref.read(pttPartialTranscriptProvider.notifier).state = '';
    _scale.forward();
    _ripple
      ..reset()
      ..repeat();
    _fade.forward();

    // Short haptic + system click signals recording has started
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click).ignore();
    debugPrint('[PTT] Speech listening started (hi_IN, pauseFor=15s)');

    await _voice.speech.listen(
      onResult: (r) {
        // Only update if the new result is non-empty — prevents a new session
        // from blanking a partial already captured.
        if (r.recognizedWords.isNotEmpty) {
          _partial = r.recognizedWords;
          if (mounted) {
            ref.read(pttPartialTranscriptProvider.notifier).state = _partial;
          }
        }
        if (r.finalResult) {
          _gotFinalResult = true;
          debugPrint('[PTT] FINAL result: "$_partial"');
        } else {
          debugPrint('[PTT] Partial: "$_partial"');
        }
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: 'hi_IN',
        listenFor: const Duration(minutes: 2),
        pauseFor: const Duration(seconds: 15),
      ),
    );
  }

  Future<void> _finishAndProcess() async {
    if (!_isPressed) return;
    _isPressed = false;

    // Start release animation immediately for a responsive feel
    _scale.reverse();
    _fade.reverse().whenComplete(() {
      if (mounted) _ripple.stop();
    });

    debugPrint('[PTT] Stopping speech... (gotFinal=$_gotFinalResult, partial="$_partial")');
    await _voice.speech.stop();

    // Poll up to 800 ms for the STT engine to deliver its finalResult callback.
    // A fixed delay isn't reliable — on slow devices the callback can lag by 500 ms+.
    for (var waited = 0; !_gotFinalResult && waited < 800; waited += 50) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    debugPrint('[PTT] Wait done — gotFinal=$_gotFinalResult, partial="$_partial"');

    if (!mounted) return;
    ref.read(pttRecordingProvider.notifier).state = false;

    final transcript = _partial.trim();
    _partial = '';
    _gotFinalResult = false;
    ref.read(pttPartialTranscriptProvider.notifier).state = '';

    debugPrint('[PTT] Final transcript: "$transcript"');

    if (transcript.isNotEmpty) {
      ref.read(pttTranscriptProvider.notifier).state = transcript;
      debugPrint('[PTT] Transcript sent to BillingScreen');
    } else {
      debugPrint('[PTT] Empty transcript — nothing to process');
    }
  }

  // ─── build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const ringColor = AppColors.primaryLight;

    return Expanded(
      child: GestureDetector(
        onTap: _onTap,
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: _onLongPressEnd,
        onLongPressCancel: _onLongPressCancel,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _allAnims,
              builder: (_, __) {
                final fadeVal = _fade.value;
                final scaleVal = _scaleAnim.value;
                final btnSize = _kFab * scaleVal;

                // Breathing glow: base shadow + pulsing intensification during recording
                final pulse = 0.5 + 0.5 * math.sin(_ripple.value * 2 * math.pi);
                final glowAlpha = 0.32 + 0.32 * fadeVal * pulse;
                final glowBlur = 10.0 + 22.0 * fadeVal * (0.6 + 0.4 * pulse);
                final glowSpread = 1.5 * fadeVal * pulse;

                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // Aura rings painted via CustomPainter — zero widget allocation per ring
                    CustomPaint(
                      painter: _AuraPainter(
                        ripple: _ripple.value,
                        fade: fadeVal,
                        color: ringColor,
                      ),
                      size: Size.zero,
                    ),
                    // Mic FAB button
                    Container(
                      width: btnSize,
                      height: btnSize,
                      decoration: BoxDecoration(
                        gradient: isDark
                            ? const LinearGradient(
                                colors: [AppColors.primaryLight, AppColors.primary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : AppColors.heroGradientLight,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C3AED).withValues(alpha: glowAlpha),
                            blurRadius: glowBlur,
                            spreadRadius: glowSpread,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 26),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── Aura ring painter ───────────────────────

class _AuraPainter extends CustomPainter {
  final double ripple;
  final double fade;
  final Color color;

  static const double _kStartR = _VoiceFABState._kFab / 2;   // button radius
  static const double _kEndR   = _VoiceFABState._kRingMaxRadius;

  _AuraPainter({
    required this.ripple,
    required this.fade,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (fade <= 0.01) return;

    // ── Layer 1: inner breathing glow (soft halo around the button) ──────
    // Pulses slightly in size with the ripple cycle so it feels "alive"
    final breathe = 0.5 + 0.5 * math.sin(ripple * 2 * math.pi);
    final glowR = _kStartR * (1.15 + 0.18 * breathe);
    final glowAlpha = 0.30 * fade;
    canvas.drawCircle(
      Offset.zero,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: glowAlpha),
            color.withValues(alpha: glowAlpha * 0.45),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: glowR)),
    );

    // ── Layer 2: three staggered expanding rings ──────────────────────────
    for (final phase in [0.0, 0.34, 0.67]) {
      final p = (ripple + phase) % 1.0;
      final t = Curves.easeOutCubic.transform(p);
      final r = _kStartR + (_kEndR - _kStartR) * t;
      final alpha = (1.0 - t) * fade;

      // Ring-band gradient: transparent core → peak at ~55% radius → fade out
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.0),
              color.withValues(alpha: alpha * 0.14),
              color.withValues(alpha: alpha * 0.85),
              color.withValues(alpha: alpha * 0.22),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.38, 0.56, 0.76, 1.0],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuraPainter old) =>
      old.ripple != ripple || old.fade != fade;
}
