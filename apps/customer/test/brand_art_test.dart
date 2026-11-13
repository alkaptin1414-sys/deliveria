import 'dart:io';
import 'dart:ui' as ui;

import 'package:deliveria/core/theme/tokens.dart';
import 'package:deliveria/core/widgets/brand_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty and filled delivery states stay inside a phone width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _shot(tester, 'customer-home-before', _frame(_beforeHero(), 'customer-home-before'));
    await _shot(tester, 'customer-home-after', _frame(_afterHero(), 'customer-home-after'));
    await _shot(tester, 'customer-orders-before', _frame(const Text('لا توجد طلبات'), 'customer-orders-before'));
    await _shot(
      tester,
      'customer-orders-after',
      _frame(const DeliveryEmptyState(
        asset: BrandArt.emptyOrders,
        title: 'لسه مفيش طلبات',
        body: 'أول طلب هيظهر هنا بعد ما تطلب مندوب.',
        action: 'اطلب مندوب الآن',
      ), 'customer-orders-after'),
    );
    await _shot(
      tester,
      'customer-orders-filled',
      _frame(const Column(
        children: [
          Text('DL-1001', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('شارع التسعين'),
        ],
      ), 'customer-orders-filled'),
    );
    expect(find.byType(BrandArt), findsNothing);

    await _shot(
      tester,
      'courier-offers-before',
      _frame(const Text('لا توجد طلبات متاحة الآن.'), 'courier-offers-before'),
    );
    await _shot(
      tester,
      'courier-offers-after',
      _frame(const DeliveryEmptyState(
        asset: BrandArt.emptyOffers,
        artSize: 96,
        title: 'مفيش طلبات متاحة حاليًا',
        body: 'الطلبات الجديدة بتظهر هنا لما تكون متاحًا.',
        action: 'تحديث الطلبات',
      ), 'courier-offers-after'),
    );

    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpWidget(_frame(const DeliveryEmptyState(
      asset: BrandArt.emptyOrders,
      title: 'لسه مفيش طلبات',
      body: 'أول طلب هيظهر هنا بعد ما تطلب مندوب.',
      action: 'اطلب مندوب الآن',
    ), 'narrow'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('اطلب مندوب الآن'), findsOneWidget);
  });
}

Widget _beforeHero() {
  return Container(
    padding: const EdgeInsets.all(18),
    color: AppColors.petrol,
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('محتاج مندوب؟', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('مندوبك يوصّل طلبك بسرعة وأمان.', style: TextStyle(color: Colors.white)),
        SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: null, child: Text('اطلب مندوب الآن'))),
      ],
    ),
  );
}

Widget _afterHero() {
  return Container(
    padding: const EdgeInsets.all(18),
    color: AppColors.petrol,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(child: Text('محتاج مندوب؟', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700))),
            BrandArt(BrandArt.riderOnPetrol, size: 72, semanticLabel: 'مندوب توصيل'),
          ],
        ),
        const SizedBox(height: 4),
        const Text('مندوبك يوصّل طلبك بسرعة وأمان.', style: TextStyle(color: Colors.white)),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: () {}, child: const Text('اطلب مندوب الآن'))),
      ],
    ),
  );
}

Widget _frame(Widget child, String name) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(fontFamily: 'Cairo', colorScheme: ColorScheme.fromSeed(seedColor: AppColors.petrol)),
    home: Scaffold(
      backgroundColor: AppColors.canvas,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: RepaintBoundary(
            key: Key(name),
            child: SizedBox(width: 340, child: child),
          ),
        ),
      ),
    ),
  );
}

Future<void> _shot(WidgetTester tester, String name, Widget frame) async {
  await tester.pumpWidget(frame);
  await tester.pump();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(Key(name)));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('tool/art-previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
