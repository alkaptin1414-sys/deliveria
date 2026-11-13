import 'package:deliveria/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('money renders Egyptian pounds from minor units', () {
    expect(money(2500), '25 ج.م');
    expect(money(2550), '25.50 ج.م');
  });

  test('distance label stays readable', () {
    expect(kmLabel(3200), '3.2 كم');
  });
}
