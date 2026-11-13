import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens.dart';
import 'ui.dart';

/// Original flat delivery drawings for Deliveria.
/// Storyset needs a visible Freepik credit, and its scenes are character-heavy.
/// unDraw delivery art is detailed cartoon people, not a quiet service mark.
/// The Iconsax Flutter package is GPL-3, so small controls stay on Material Icons.
class BrandArt extends StatelessWidget {
  const BrandArt(this.asset, {super.key, this.size = 120, this.semanticLabel});

  final String asset;
  final double size;
  final String? semanticLabel;

  static const rider = 'assets/illustrations/delivery/delivery_rider.svg';
  static const riderOnPetrol = 'assets/illustrations/delivery/delivery_rider_light.svg';
  static const motorcycle = 'assets/illustrations/delivery/delivery_motorcycle.svg';
  static const delivered = 'assets/illustrations/delivery/order_delivered.svg';
  static const emptyOrders = 'assets/illustrations/empty_states/empty_orders.svg';
  static const emptyOffers = 'assets/illustrations/empty_states/empty_available_orders.svg';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticsLabel: semanticLabel,
    );
  }
}

class DeliveryEmptyState extends StatelessWidget {
  const DeliveryEmptyState({
    super.key,
    required this.asset,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
    this.note,
    this.artSize = 132,
  });

  final String asset;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  final String? note;
  final double artSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandArt(asset, size: artSize, semanticLabel: title),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(body, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, height: 1.4)),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
          if (action != null) ...[
            const SizedBox(height: 14),
            SizedBox(width: 200, child: AppButton(label: action!, onPressed: onAction)),
          ],
        ],
      ),
    );
  }
}
