import 'dart:async';
import 'package:flutter/material.dart';

/// WTransitionScreen — Animated loading page shown between register → main
/// Lets Phase 2 services (Bluetooth, audio, voice) finish loading
/// before the user hits the main dashboard.
class WTransitionScreen extends StatefulWidget {
  final String destination;
  final String title;
  final String subtitle;
  final int durationMs;
  final Map<String, dynamic>? args;

  const WTransitionScreen({
    Key? key,
    required this.destination,
    this.title = 'Setting up your device',
    this.subtitle = 'Loading ShaRogai services...',
    this.durationMs = 2500,
    this.args,
  }) : super(key: key);

  @override
  State<WTransitionScreen> createState() => _WTransitionScreenState();
}

class _WTransitionScreenState extends State<WTransitionScreen>
    with TickerProviderStateMixin {
  late AnimationController _progressCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  int _stepIndex = 0;
  Timer? _stepTimer;

  static const _steps = [
    _LoadStep(icon: Icons.security, label: 'Checking permissions'),
    _LoadStep(icon: Icons.chat_bubble_outline, label: 'Starting chat service'),
    _LoadStep(icon: Icons.bluetooth, label: 'Scanning for devices'),
    _LoadStep(icon: Icons.volume_up, label: 'Initializing audio'),
    _LoadStep(icon: Icons.check_circle, label: 'All set — welcome!'),
  ];

  @override
  void initState() {
    super.initState();

    _progressCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    )..forward();

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    // Advance step label every (duration / steps) ms
    final stepMs = widget.durationMs ~/ _steps.length;
    _stepTimer = Timer.periodic(Duration(milliseconds: stepMs), (_) {
      if (mounted) {
        setState(() {
          _stepIndex = (_stepIndex + 1).clamp(0, _steps.length - 1);
        });
      }
    });

    // Navigate when done
    Future.delayed(Duration(milliseconds: widget.durationMs), _navigate);
  }

  void _navigate() {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(
      widget.destination,
      arguments: widget.args,
    );
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _fadeCtrl.dispose();
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_stepIndex];

    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('W',
                          style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Title
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 6),
                  Text(widget.subtitle,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 13),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 44),

                  // Animated progress bar
                  AnimatedBuilder(
                    animation: _progressCtrl,
                    builder: (_, __) => Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progressCtrl.value,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.amber),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${(_progressCtrl.value * 100).toInt()}%',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Current step label — switches with animation
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Row(
                      key: ValueKey(_stepIndex),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(step.icon, size: 16, color: Colors.amber),
                        const SizedBox(width: 8),
                        Text(step.label,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Progress dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_steps.length, (i) {
                      final active = i <= _stepIndex;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? Colors.amber
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadStep {
  final IconData icon;
  final String label;
  const _LoadStep({required this.icon, required this.label});
}
