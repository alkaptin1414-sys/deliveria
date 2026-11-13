import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as geo;

import '../../core/theme/tokens.dart';
import '../../core/widgets/ui.dart';

class MapPickPage extends StatefulWidget {
  const MapPickPage({super.key, this.initial});
  final geo.LatLng? initial;

  @override
  State<MapPickPage> createState() => _MapPickPageState();
}

class _MapPickPageState extends State<MapPickPage> {
  GoogleMapController? _map;
  final _line = TextEditingController();
  late geo.LatLng _center = widget.initial ?? const geo.LatLng(30.0444, 31.2357);
  bool _locating = false;
  String? _error;

  @override
  void dispose() {
    _line.dispose();
    super.dispose();
  }

  Future<void> _myLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() => _error = 'تقدر تكتب العنوان أو تحرك الخريطة بدون إذن الموقع.');
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final next = geo.LatLng(position.latitude, position.longitude);
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(next.latitude, next.longitude), 16));
      setState(() => _center = next);
    } catch (_) {
      setState(() => _error = 'تعذر تحديد موقعك. حرّك الخريطة أو اكتب العنوان.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _search() async {
    final query = _line.text.trim();
    if (query.length < 3) return;
    try {
      final response = await Dio().get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {'q': query, 'format': 'json', 'limit': '1', 'countrycodes': 'eg'},
        options: Options(headers: {'User-Agent': 'Deliveria/0.1', 'Accept-Language': 'ar'}),
      );
      final list = response.data is String ? jsonDecode(response.data as String) as List : response.data as List;
      if (list.isEmpty) {
        setState(() => _error = 'مفيش نتيجة. حرّك الخريطة على المكان.');
        return;
      }
      final hit = list.first as Map<String, dynamic>;
      final next = geo.LatLng(double.parse(hit['lat'] as String), double.parse(hit['lon'] as String));
      await _map?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(next.latitude, next.longitude), 16));
      setState(() {
        _center = next;
        _error = null;
        if ((hit['display_name'] as String?)?.isNotEmpty == true) {
          _line.text = (hit['display_name'] as String).split(',').take(3).join('،');
        }
      });
    } catch (_) {
      setState(() => _error = 'البحث غير متاح الآن. حدد المكان على الخريطة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: LatLng(_center.latitude, _center.longitude), zoom: 15),
            onMapCreated: (controller) => _map = controller,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onCameraMove: (position) => _center = geo.LatLng(position.target.latitude, position.target.longitude),
          ),
          const IgnorePointer(child: Center(child: Icon(Icons.location_on, size: 40, color: AppColors.petrol))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: TextField(
                      controller: _line,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: 'ابحث عن العنوان',
                        prefixIcon: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_forward)),
                        suffixIcon: IconButton(onPressed: _search, icon: const Icon(Icons.search)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_error != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom + 68,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.ink,
              onPressed: _locating ? null : _myLocation,
              child: _locating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            child: AppButton(
              label: 'تأكيد المكان',
              onPressed: () {
                Navigator.pop(context, {
                  'lat': _center.latitude,
                  'lng': _center.longitude,
                  'line': _line.text.trim().isEmpty ? 'موقع محدد على الخريطة' : _line.text.trim(),
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
