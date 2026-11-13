import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';
import '../models.dart';
import 'api_exception.dart';
import 'session_store.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) {
  return SessionStore(const FlutterSecureStorage());
});

final apiProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(sessionStoreProvider));
});

class ApiClient {
  ApiClient(this.store) {
    dio = Dio(BaseOptions(
      baseUrl: '${AppConfig.apiBase}/v1',
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 8),
      headers: {'Accept': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = store.accessToken;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 && store.refreshToken != null && error.requestOptions.path != '/auth/refresh') {
          try {
            final refreshed = await Dio(BaseOptions(baseUrl: '${AppConfig.apiBase}/v1')).post('/auth/refresh', data: {
              'refreshToken': store.refreshToken,
            });
            final data = Map<String, dynamic>.from(refreshed.data as Map);
            await store.save(data['accessToken'] as String, data['refreshToken'] as String);
            final request = error.requestOptions;
            request.headers['Authorization'] = 'Bearer ${store.accessToken}';
            final response = await dio.fetch(request);
            handler.resolve(response);
            return;
          } catch (_) {
            await store.clear();
          }
        }
        handler.next(error);
      },
    ));
  }

  final SessionStore store;
  late final Dio dio;

  Future<T> _send<T>(Future<Response<dynamic>> future, T Function(dynamic data) parse) async {
    try {
      final response = await future;
      return parse(response.data);
    } on DioException catch (error) {
      final offline = error.type == DioExceptionType.connectionError || error.type == DioExceptionType.connectionTimeout;
      if (offline && AppConfig.tryNextBase()) {
        final next = '${AppConfig.apiBase}/v1';
        dio.options.baseUrl = next;
        final request = error.requestOptions;
        request.baseUrl = next;
        return _send(dio.fetch(request), parse);
      }
      final data = error.response?.data;
      if (data is Map && data['message'] is String) {
        throw ApiException(data['message'] as String, code: data['code'] as String?);
      }
      if (offline) {
        throw ApiException('تعذر الاتصال بالخادم. تأكد من الإنترنت وحاول مرة أخرى.', code: 'OFFLINE');
      }
      throw ApiException('تعذر تنفيذ الطلب.');
    }
  }

  Future<Map<String, dynamic>> requestOtp(String phone) {
    return _send(dio.post('/auth/otp', data: {'phone': phone}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> verifyOtp(String challengeId, String code) async {
    final data = await _send(
      dio.post('/auth/otp/verify', data: {'challengeId': challengeId, 'code': code}),
      (data) => Map<String, dynamic>.from(data as Map),
    );
    await store.save(data['accessToken'] as String, data['refreshToken'] as String);
    return data;
  }

  Future<Map<String, dynamic>> registerAccount({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final data = await _send(
      dio.post('/auth/register', data: {'name': name, 'email': email, 'password': password, 'role': role}),
      (data) => Map<String, dynamic>.from(data as Map),
    );
    await store.save(data['accessToken'] as String, data['refreshToken'] as String);
    return data;
  }

  Future<Map<String, dynamic>> loginWithEmail(String email, String password) async {
    final data = await _send(
      dio.post('/auth/login', data: {'email': email, 'password': password}),
      (data) => Map<String, dynamic>.from(data as Map),
    );
    await store.save(data['accessToken'] as String, data['refreshToken'] as String);
    return data;
  }

  Future<void> logout() async {
    final refresh = store.refreshToken;
    if (refresh != null) {
      try {
        await dio.post('/auth/logout', data: {'refreshToken': refresh});
      } catch (_) {}
    }
    await store.clear();
  }

  Future<UserProfile> me() {
    return _send(dio.get('/me'), (data) => UserProfile.fromJson(Map<String, dynamic>.from(data as Map)));
  }

  Future<UserProfile> completeProfile(String name, String accountType) {
    return _send(
      dio.post('/me/profile', data: {'name': name, 'accountType': accountType}),
      (data) => UserProfile.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  Future<UserProfile> updateMe(Map<String, dynamic> body) {
    return _send(dio.patch('/me', data: body), (data) => UserProfile.fromJson(Map<String, dynamic>.from(data as Map)));
  }

  Future<List<dynamic>> categories() => _send(dio.get('/catalog/business-categories'), (data) => data as List);
  Future<Map<String, dynamic>> parcelCatalog() => _send(dio.get('/catalog/parcel-types'), (data) => Map<String, dynamic>.from(data as Map));
  Future<List<dynamic>> vehicles(double lat, double lng) => _send(dio.get('/catalog/vehicles', queryParameters: {'lat': lat, 'lng': lng}), (data) => data as List);

  Future<Map<String, dynamic>> createBusiness(Map<String, dynamic> body) {
    return _send(dio.post('/business', data: body), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> business() => _send(dio.get('/business'), (data) => Map<String, dynamic>.from(data as Map));
  Future<Map<String, dynamic>> businessStats() => _send(dio.get('/business/stats'), (data) => Map<String, dynamic>.from(data as Map));
  Future<List<dynamic>> recipients({String? q}) {
    return _send(dio.get('/business/recipients', queryParameters: {if (q != null && q.isNotEmpty) 'q': q}), (data) => data as List);
  }

  Future<Map<String, dynamic>> saveRecipient(Map<String, dynamic> body) {
    return _send(dio.post('/business/recipients', data: body), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteRecipient(String id) => _send(dio.delete('/business/recipients/$id'), (_) {});
  Future<Map<String, dynamic>> finance() => _send(dio.get('/business/finance'), (data) => Map<String, dynamic>.from(data as Map));
  Future<Map<String, dynamic>> reports({String? from, String? to}) {
    return _send(dio.get('/business/reports', queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<List<SavedAddress>> addresses() {
    return _send(dio.get('/addresses'), (data) {
      return (data as List).map((item) => SavedAddress(Map<String, dynamic>.from(item as Map))).toList();
    });
  }

  Future<SavedAddress> saveAddress(Map<String, dynamic> body, {String? id}) {
    final call = id == null ? dio.post('/addresses', data: body) : dio.patch('/addresses/$id', data: body);
    return _send(call, (data) => SavedAddress(Map<String, dynamic>.from(data as Map)));
  }

  Future<void> deleteAddress(String id) => _send(dio.delete('/addresses/$id'), (_) {});
  Future<void> defaultAddress(String id) => _send(dio.post('/addresses/$id/default'), (_) {});

  Future<Map<String, dynamic>> findPlace(String line) {
    return _send(dio.get('/geo/place', queryParameters: {'q': line}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<List<Map<String, dynamic>>> selectableCouriers() {
    return _send(dio.get('/couriers/selectable'), (data) {
      return (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList();
    });
  }

  Future<Map<String, dynamic>> quote(Map<String, dynamic> body) {
    return _send(dio.post('/orders/quote', data: body), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<DeliveryOrder> createOrder(Map<String, dynamic> body, String key) {
    return _send(
      dio.post('/orders', data: body, options: Options(headers: {'Idempotency-Key': key})),
      (data) => DeliveryOrder(Map<String, dynamic>.from(data as Map)),
    );
  }

  Future<List<DeliveryOrder>> orders(String bucket, {String? q}) {
    return _send(dio.get('/orders', queryParameters: {'bucket': bucket, if (q != null && q.isNotEmpty) 'q': q}), (data) {
      return (data as List).map((item) => DeliveryOrder(Map<String, dynamic>.from(item as Map))).toList();
    });
  }

  Future<DeliveryOrder> order(String id) => _send(dio.get('/orders/$id'), (data) => DeliveryOrder(Map<String, dynamic>.from(data as Map)));
  Future<Map<String, dynamic>> cancelPreview(String id) {
    return _send(dio.get('/orders/$id/cancel-preview'), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<DeliveryOrder> cancel(String id, {required String code, String? reason}) {
    return _send(dio.post('/orders/$id/cancel', data: {'code': code, 'reason': reason}), (data) => DeliveryOrder(Map<String, dynamic>.from(data as Map)));
  }

  Future<DeliveryOrder> retry(String id) => _send(dio.post('/orders/$id/retry'), (data) => DeliveryOrder(Map<String, dynamic>.from(data as Map)));
  Future<String> deliveryCode(String id) {
    return _send(dio.get('/orders/$id/delivery-code'), (data) => (data as Map)['code'] as String);
  }

  Future<Map<String, dynamic>> orderReview(String id) {
    return _send(dio.get('/orders/$id/review'), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> review(String id, int rating, List<String> tags, String? comment, {bool update = false}) {
    final path = update ? '/orders/$id/review/update' : '/orders/$id/review';
    return _send(dio.post(path, data: {'rating': rating, 'tags': tags, 'comment': comment}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> courierRatings(String courierId) {
    return _send(dio.get('/couriers/$courierId/ratings'), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<void> reportReview(String id, String reason) => _send(dio.post('/reviews/$id/report', data: {'reason': reason}), (_) {});

  Future<List<dynamic>> messages(String id) => _send(dio.get('/orders/$id/messages'), (data) => data as List);
  Future<Map<String, dynamic>> sendMessage(String id, String body) {
    return _send(dio.post('/orders/$id/messages', data: {'body': body}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<void> registerDevice(String token, String platform) {
    return _send(dio.post('/notifications/devices', data: {'token': token, 'platform': platform}), (_) {});
  }

  Future<List<dynamic>> notifications() => _send(dio.get('/notifications'), (data) => data as List);
  Future<void> readNotification(String id) => _send(dio.post('/notifications/$id/read'), (_) {});
  Future<List<dynamic>> faq() => _send(dio.get('/support/faq'), (data) => data as List);
  Future<Map<String, dynamic>> legal(String kind) => _send(dio.get('/legal/$kind'), (data) => Map<String, dynamic>.from(data as Map));
  Future<Map<String, dynamic>> ticket({required String kind, required String subject, required String message, String? orderId}) {
    return _send(dio.post('/support/tickets', data: {'kind': kind, 'subject': subject, 'message': message, 'orderId': orderId}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<List<dynamic>> tickets() => _send(dio.get('/support/tickets'), (data) => data as List);
  Future<Map<String, dynamic>> ticketDetail(String id) => _send(dio.get('/support/tickets/$id'), (data) => Map<String, dynamic>.from(data as Map));
  Future<void> ticketReply(String id, String body) => _send(dio.post('/support/tickets/$id/messages', data: {'body': body}), (_) {});

  Future<String> upload(String path, {String purpose = 'parcel'}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(path),
    });
    final data = await _send(dio.post('/uploads', data: form, queryParameters: {'purpose': purpose}), (data) => Map<String, dynamic>.from(data as Map));
    return data['url'] as String;
  }

  Future<List<Map<String, dynamic>>> restaurants({String? q, String? category, String? sort}) {
    return _send(
      dio.get('/restaurants', queryParameters: {'q': q, 'category': category, 'sort': sort}),
      (data) => (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> restaurantCategories() {
    return _send(dio.get('/restaurants/categories'), (data) => (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList());
  }

  Future<Map<String, dynamic>> restaurant(String id) {
    return _send(dio.get('/restaurants/$id'), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> cart(String restaurantId) {
    return _send(dio.get('/restaurants/$restaurantId/cart'), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> saveCart(String restaurantId, List<Map<String, dynamic>> items) {
    return _send(dio.put('/restaurants/$restaurantId/cart', data: {'items': items}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> foodQuote(String restaurantId, String addressId) {
    return _send(dio.get('/restaurants/$restaurantId/cart/quote', queryParameters: {'addressId': addressId}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> placeFoodOrder(String restaurantId, Map<String, dynamic> body, String idempotencyKey) {
    return _send(
      dio.post('/food-orders', data: {'restaurantId': restaurantId, ...body}, options: Options(headers: {'idempotency-key': idempotencyKey})),
      (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<List<Map<String, dynamic>>> foodOrders() {
    return _send(dio.get('/food-orders'), (data) => (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList());
  }

  Future<Map<String, dynamic>> foodOrder(String id) {
    return _send(dio.get('/food-orders/$id'), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> cancelFoodOrder(String id) {
    return _send(dio.post('/food-orders/$id/cancel'), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<void> reviewRestaurant(String id, int rating, String? comment) {
    return _send(dio.post('/food-orders/$id/review', data: {'rating': rating, 'comment': comment}), (_) {});
  }

  Future<Map<String, dynamic>> courierMe() => _send(dio.get('/courier/me'), (data) => Map<String, dynamic>.from(data as Map));

  Future<UserProfile> applyCourier(Map<String, dynamic> body) async {
    final data = await _send(dio.post('/courier/application', data: body), (data) => Map<String, dynamic>.from(data as Map));
    await store.save(data['accessToken'] as String, data['refreshToken'] as String);
    return UserProfile.fromJson(Map<String, dynamic>.from(data['user'] as Map));
  }

  Future<Map<String, dynamic>> uploadCourierDoc(String path, String kind) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path)});
    return _send(dio.post('/courier/documents', data: form, queryParameters: {'kind': kind}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> courierAvailability(bool available, {double? lat, double? lng}) {
    return _send(dio.post('/courier/availability', data: {'available': available, 'lat': lat, 'lng': lng}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<List<Map<String, dynamic>>> courierOffers() {
    return _send(dio.get('/courier/offers'), (data) => (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList());
  }

  Future<Map<String, dynamic>> courierAccept(String offerId) => _send(dio.post('/courier/offers/$offerId/accept'), (data) => Map<String, dynamic>.from(data as Map));
  Future<void> courierDecline(String offerId) => _send(dio.post('/courier/offers/$offerId/decline'), (_) {});
  Future<List<Map<String, dynamic>>> courierHistory() {
    return _send(dio.get('/courier/orders'), (data) => (data as List).map((item) => Map<String, dynamic>.from(item as Map)).toList());
  }

  Future<Map<String, dynamic>> courierJob(String orderId) => _send(dio.get('/courier/orders/$orderId'), (data) => Map<String, dynamic>.from(data as Map));

  Future<void> courierReport(String orderId, String message) {
    return _send(dio.post('/courier/orders/$orderId/report', data: {'message': message}), (_) {});
  }

  Future<Map<String, dynamic>> courierAdvance(String orderId, String status) {
    return _send(dio.post('/courier/orders/$orderId/advance', data: {'status': status}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> courierDeliver(String orderId, String code) {
    return _send(dio.post('/courier/orders/$orderId/deliver', data: {'code': code}), (data) => Map<String, dynamic>.from(data as Map));
  }

  Future<void> courierPing(String orderId, double lat, double lng) {
    return _send(dio.post('/courier/orders/$orderId/location', data: {'lat': lat, 'lng': lng}), (_) {});
  }

  Future<Map<String, dynamic>> courierEarnings() => _send(dio.get('/courier/earnings'), (data) => Map<String, dynamic>.from(data as Map));
  Future<Map<String, dynamic>> myCourierRatings() => _send(dio.get('/courier/ratings'), (data) => Map<String, dynamic>.from(data as Map));

  Future<Map<String, dynamic>> drivingRoute(double fromLat, double fromLng, double toLat, double toLng) {
    return _send(
      dio.get('/geo/route', queryParameters: {'fromLat': fromLat, 'fromLng': fromLng, 'toLat': toLat, 'toLng': toLng}),
      (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<Map<String, dynamic>> adminHome() => _send(dio.get('/admin/home'), (data) => Map<String, dynamic>.from(data as Map));

  Future<void> adminReviewCourier(String id, String status, String? note) {
    return _send(dio.post('/admin/couriers/$id/review', data: {'status': status, 'note': note}), (_) {});
  }

  Future<dynamic> adminGet(String path) => _send(dio.get(path), (data) => data);

  Future<dynamic> adminPost(String path, Map<String, dynamic> body) => _send(dio.post(path, data: body), (data) => data);

  Future<void> dev(String orderId, String action, [Map<String, dynamic>? body]) {
    return _send(
      dio.post('/dev/orders/$orderId/$action', data: body ?? {}, options: Options(headers: {'x-dev-key': AppConfig.devKey})),
      (_) {},
    );
  }
}
