String money(int minor) {
  final pounds = minor / 100;
  final whole = pounds == pounds.roundToDouble();
  final text = whole ? pounds.toStringAsFixed(0) : pounds.toStringAsFixed(2);
  return '$text ج.م';
}

String kmLabel(int meters) {
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} كم' : '${km.toStringAsFixed(0)} كم';
}

String greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'صباح الخير';
  if (hour < 18) return 'مرحبًا';
  return 'مساء الخير';
}

String whenLabel(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  if (sameDay) return 'اليوم $hh:$mm';
  return '${local.day}/${local.month} $hh:$mm';
}

String clock(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String statusLabel(String status) {
  switch (status) {
    case 'SEARCHING':
      return 'جاري البحث';
    case 'ACCEPTED':
      return 'تم القبول';
    case 'EN_ROUTE_PICKUP':
      return 'في الطريق للاستلام';
    case 'PICKED_UP':
      return 'تم الاستلام';
    case 'EN_ROUTE_DROPOFF':
      return 'في الطريق للتسليم';
    case 'DELIVERED':
      return 'تم التسليم';
    case 'CANCELLED':
      return 'ملغي';
    case 'NO_COURIER':
      return 'لا يوجد مندوب';
    default:
      return status;
  }
}

String vehicleLabel(String code) => code == 'CAR' ? 'سيارة' : 'موتوسيكل';

String sizeLabel(String code) {
  switch (code) {
    case 'MEDIUM':
      return 'متوسط';
    case 'LARGE':
      return 'كبير';
    default:
      return 'صغير';
  }
}

String parcelLabel(String code) {
  switch (code) {
    case 'DOCUMENTS':
      return 'مستندات';
    case 'FOOD':
      return 'طعام';
    case 'PERSONAL':
      return 'أغراض شخصية';
    case 'OTHER':
      return 'غرض آخر';
    default:
      return 'طرد';
  }
}
