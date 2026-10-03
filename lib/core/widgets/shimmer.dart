import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Moving light band over grey placeholder shapes while data loads.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value * 3 - 1; // -1 → 2: band sweeps across
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Color(0xFFE2E8F0),
              Color(0xFFF8FAFC),
              Color(0xFFE2E8F0),
            ],
            stops: [
              (t - 0.3).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.3).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

/// Grey rounded block used inside [Shimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Placeholder list (avatar + two lines + amount) shown while a list or
/// detail page loads, instead of a bare spinner.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSizes.gutter),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const SkeletonBox(width: 44, height: 44, radius: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: i.isEven ? 150 : 110, height: 14),
                    const SizedBox(height: 8),
                    SkeletonBox(width: i.isEven ? 90 : 130, height: 11),
                  ],
                ),
              ),
              const SkeletonBox(width: 64, height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen loading page with the skeleton list.
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SafeArea(child: ListSkeleton()));
}

/// Progress bar with a percentage and a step label, e.g. backup upload.
class PercentProgress extends StatelessWidget {
  const PercentProgress({
    super.key,
    required this.value,
    required this.label,
    this.detail,
  });

  /// 0.0 – 1.0, or null while the size is not known yet.
  final double? value;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final percent = value == null ? null : (value! * 100).clamp(0, 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (percent != null)
              Text(
                '$percent%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppColors.blue700,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: value ?? 0),
            duration: const Duration(milliseconds: 300),
            builder: (context, v, _) => LinearProgressIndicator(
              value: value == null ? null : v,
              minHeight: 10,
              backgroundColor: AppColors.border,
              color: AppColors.amber500,
            ),
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 6),
          Text(
            detail!,
            style: const TextStyle(color: AppColors.slate600, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// Branded loading screen shown while the app starts (matches the native
/// splash: dark background, app icon).
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.slate900,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 104,
                height: 104,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Thekedaar',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Hisaab-kitaab, ek jagah',
              style: TextStyle(color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 28),
            const SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(999)),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: Color(0xFF1E293B),
                  color: AppColors.amber500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
