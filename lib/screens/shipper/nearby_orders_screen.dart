import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/shipper_service.dart';
import 'delivery_navigation_screen.dart';

class NearbyOrdersScreen extends StatefulWidget {
  const NearbyOrdersScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<NearbyOrdersScreen> createState() => _NearbyOrdersScreenState();
}

class _NearbyOrdersScreenState extends State<NearbyOrdersScreen> {
  final _service = ShipperService();
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _activeOrders = [];
  bool _loading = false;
  bool _locationReady = false;
  String? _locationText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActiveOrders());
  }

  Future<void> _loadActiveOrders() async {
    try {
      final orders = await _service.getActiveOrders();
      if (mounted) setState(() => _activeOrders = orders);
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _refreshOrdersFromSavedLocation() async {
    try {
      final results = await Future.wait([
        _service.getActiveOrders(),
        _service.getNearbyOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _activeOrders = results[0];
        _orders = results[1];
      });
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _updateLocationAndLoad() async {
    setState(() => _loading = true);
    try {
      final position = await _service.updateCurrentLocation();
      final results = await Future.wait([
        _service.getActiveOrders(),
        _service.getNearbyOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _locationReady = true;
        _locationText =
            '${position.latitude.toStringAsFixed(5)}, '
            '${position.longitude.toStringAsFixed(5)}';
        _activeOrders = results[0];
        _orders = results[1];
      });
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(Map<String, dynamic> order) async {
    setState(() => _loading = true);
    try {
      await _service.updateCurrentLocation();
      await _service.acceptOrder(order['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã nhận đơn ${order['ma_van_don']}'),
          backgroundColor: AppColors.success,
        ),
      );
      setState(() => _loading = false);
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DeliveryNavigationScreen(order: order),
        ),
      );
      if (!mounted) return;
      if (completed == true) {
        setState(() {
          _orders.removeWhere((item) => item['id'] == order['id']);
          _activeOrders.removeWhere((item) => item['id'] == order['id']);
        });
      }
      unawaited(_refreshOrdersFromSavedLocation());
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reject(Map<String, dynamic> order) async {
    setState(() => _loading = true);
    try {
      await _service.rejectOrder(order['id'] as int);
      if (!mounted) return;
      setState(() => _orders.removeWhere((item) => item['id'] == order['id']));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã chuyển đơn cho shipper khác')),
      );
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _resume(Map<String, dynamic> order) async {
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DeliveryNavigationScreen(order: order)),
    );
    if (!mounted) return;
    if (completed == true) {
      setState(() {
        _activeOrders.removeWhere((item) => item['id'] == order['id']);
      });
    }
    unawaited(_refreshOrdersFromSavedLocation());
  }

  @override
  Widget build(BuildContext context) {
    final content = RefreshIndicator(
      onRefresh: _updateLocationAndLoad,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: _buildContent(context),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Đơn gần bạn')),
      body: content,
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.my_location_rounded,
              color: Colors.white,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              _locationReady
                  ? 'Đang tìm đơn trong bán kính 10 km'
                  : 'Bật vị trí để tìm đơn gần bạn',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_locationText != null) ...[
              const SizedBox(height: 4),
              Text(
                'Vị trí: $_locationText',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loading ? null : _updateLocationAndLoad,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.gps_fixed_rounded),
              label: Text(
                _locationReady ? 'Cập nhật vị trí' : 'Cho phép vị trí',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (_activeOrders.isNotEmpty) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                'Đơn đang giao',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text('${_activeOrders.length} đơn'),
          ],
        ),
        const SizedBox(height: 12),
        ..._activeOrders.map(
          (order) =>
              _ActiveOrderCard(order: order, onResume: () => _resume(order)),
        ),
        const SizedBox(height: 12),
      ],
      Row(
        children: [
          Expanded(
            child: Text(
              'Đơn có thể nhận',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text('${_orders.length} đơn'),
        ],
      ),
      const SizedBox(height: 12),
      if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        )
      else if (!_locationReady)
        const _EmptyState(
          icon: Icons.location_disabled_outlined,
          text: 'Chưa có vị trí hiện tại',
        )
      else if (_orders.isEmpty)
        const _EmptyState(
          icon: Icons.inventory_2_outlined,
          text: 'Chưa có đơn lấy hàng nào gần bạn',
        )
      else
        ..._orders.map(
          (order) => _NearbyOrderCard(
            order: order,
            onAccept: () => _accept(order),
            onReject: () => _reject(order),
          ),
        ),
    ];
  }
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order, required this.onResume});

  final Map<String, dynamic> order;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final pickedUp = order['trang_thai'] != 'CHO_LAY_HANG';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: AppColors.primary10,
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.primary,
          child: Icon(Icons.delivery_dining, color: Colors.white),
        ),
        title: Text(
          '${order['ma_van_don']}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${pickedUp ? 'Đang giao tới người nhận' : 'Đang đến lấy hàng'}\n'
          'Thu nhập: ${_formatMoney(order['tien_shipper_du_kien'])}',
        ),
        trailing: FilledButton(
          onPressed: onResume,
          child: const Text('Tiếp tục'),
        ),
      ),
    );
  }
}

class _NearbyOrderCard extends StatelessWidget {
  const _NearbyOrderCard({
    required this.order,
    required this.onAccept,
    required this.onReject,
  });
  final Map<String, dynamic> order;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final distance = (order['khoang_cach_den_diem_lay_km'] as num).toDouble();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order['ma_van_don'] as String,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.near_me_outlined, size: 16),
                  label: Text('${distance.toStringAsFixed(1)} km'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _line(Icons.person_outline, order['nguoi_gui_ten'] as String),
            _line(
              Icons.location_on_outlined,
              order['nguoi_gui_dia_chi'] as String,
            ),
            _line(Icons.flag_outlined, order['nguoi_nhan_dia_chi'] as String),
            _line(
              Icons.payments_outlined,
              'Thu nhập shipper: ${_money(order['tien_shipper_du_kien'])}',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    child: const Text('Từ chối'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.delivery_dining_rounded),
                    label: const Text('Nhận đơn'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  String _money(dynamic value) {
    final number = (value as num?)?.round() ?? 0;
    final formatted = number.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}.',
    );
    return '$formattedđ';
  }
}

String _formatMoney(dynamic value) {
  final number = (value as num?)?.round() ?? 0;
  final formatted = number.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );
  return '$formattedđ';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.textDisabled),
          const SizedBox(height: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
