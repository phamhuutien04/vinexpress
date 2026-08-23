import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Nhãn địa lý tiếng Việt bổ sung trên lớp nền OpenStreetMap.
List<Marker> get vietnamIslandMarkers => const [
  Marker(
    point: LatLng(16.5, 112.0),
    width: 150,
    height: 42,
    child: _IslandLabel(text: 'Quần đảo Hoàng Sa'),
  ),
  Marker(
    point: LatLng(10.0, 114.0),
    width: 160,
    height: 42,
    child: _IslandLabel(text: 'Quần đảo Trường Sa'),
  ),
];

class _IslandLabel extends StatelessWidget {
  const _IslandLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF00AFA0), width: 0.8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF006C63),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
