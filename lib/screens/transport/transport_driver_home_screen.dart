import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/transport_driver_service.dart';
import '../auth/login_screen.dart';

class TransportDriverHomeScreen extends StatefulWidget {
  const TransportDriverHomeScreen({super.key});

  @override
  State<TransportDriverHomeScreen> createState() =>
      _TransportDriverHomeScreenState();
}

class _TransportDriverHomeScreenState
    extends State<TransportDriverHomeScreen> {
  final _service = TransportDriverService();
  int _tab = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _trips = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _service.getProfile(),
        _service.getTrips(),
      ]);
      if (!mounted) return;
      setState(() {
        _profile = result[0] as Map<String, dynamic>;
        _trips = result[1] as List<Map<String, dynamic>>;
      });
    } on TransportDriverException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_profile['ho_ten'] ?? 'Tài xế xe tải'}';
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Chuyến xe của tôi' : 'Tài khoản tài xế'),
        actions: [
          if (_tab == 0)
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : IndexedStack(
                  index: _tab,
                  children: [
                    _TripsView(
                      profile: _profile,
                      trips: _trips,
                      onUpdate: _updateTrip,
                    ),
                    _DriverAccount(profile: _profile, name: name, onLogout: _logout),
                  ],
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Chuyến xe',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }

  Future<void> _updateTrip(int id, String status) async {
    try {
      await _service.updateTrip(id, status);
      await _load();
    } on TransportDriverException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _logout() async {
    await CustomerAuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

class _TripsView extends StatelessWidget {
  const _TripsView({required this.profile, required this.trips, required this.onUpdate});
  final Map<String, dynamic> profile;
  final List<Map<String, dynamic>> trips;
  final Future<void> Function(int, String) onUpdate;

  @override
  Widget build(BuildContext context) {
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.fire_truck, color: AppColors.primary, size: 32),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${profile['ho_ten'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                      Text(
                        profile['bien_so_xe'] == null
                            ? 'Chưa được gán xe tải'
                            : '${profile['bien_so_xe']} • ${profile['tai_trong'] ?? 0} kg',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('Chuyến được phân công (${trips.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (profile['xe_id'] == null)
            const _EmptyState(icon: Icons.no_transfer, text: 'Admin cần gán xe tải cho tài xế trước.')
          else if (trips.isEmpty)
            const _EmptyState(icon: Icons.route_outlined, text: 'Chưa có chuyến xe được phân công.')
          else
            ...trips.map((trip) => _TripCard(trip: trip, onUpdate: onUpdate)),
        ],
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onUpdate});
  final Map<String, dynamic> trip;
  final Future<void> Function(int, String) onUpdate;

  @override
  Widget build(BuildContext context) {
    final status = '${trip['trang_thai']}';
    final next = switch (status) {
      'CHO_KHOI_HANH' || 'DANG_XEP_HANG' => ('DANG_DI', 'Bắt đầu chạy'),
      'DANG_DI' => ('DA_DEN', 'Đã đến kho'),
      'DA_DEN' => ('DA_HOAN_THANH', 'Hoàn thành chuyến'),
      _ => null,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('${trip['ma_chuyen']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                Chip(label: Text(_status(status))),
              ],
            ),
            const Divider(),
            _line(Icons.warehouse_outlined, 'Từ: ${trip['kho_di_ten'] ?? 'Chưa xếp chặng'}'),
            const SizedBox(height: 8),
            _line(Icons.flag_outlined, 'Đến: ${trip['kho_den_ten'] ?? 'Chưa xếp chặng'}'),
            const SizedBox(height: 8),
            _line(Icons.inventory_2_outlined, '${trip['so_don_hang'] ?? 0} đơn hàng'),
            if (next != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => onUpdate((trip['id'] as num).toInt(), next.$1),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(next.$2),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Row(children: [Icon(icon, size: 20, color: AppColors.primary), const SizedBox(width: 9), Expanded(child: Text(text))]);

  String _status(String value) => switch (value) {
        'CHO_KHOI_HANH' => 'Chờ khởi hành',
        'DANG_XEP_HANG' => 'Đang xếp hàng',
        'DANG_DI' => 'Đang di chuyển',
        'DA_DEN' => 'Đã đến kho',
        'DA_HOAN_THANH' => 'Hoàn thành',
        'DA_HUY' => 'Đã hủy',
        _ => value,
      };
}

class _DriverAccount extends StatelessWidget {
  const _DriverAccount({required this.profile, required this.name, required this.onLogout});
  final Map<String, dynamic> profile;
  final String name;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const CircleAvatar(radius: 42, backgroundColor: AppColors.primary, child: Icon(Icons.fire_truck, color: Colors.white, size: 44)),
          const SizedBox(height: 12),
          Text(name, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const Text('Tài xế xe tải', textAlign: TextAlign.center),
          const SizedBox(height: 22),
          Card(child: Column(children: [
            ListTile(leading: const Icon(Icons.phone_outlined), title: Text('${profile['so_dien_thoai'] ?? ''}')),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.local_shipping_outlined), title: Text('${profile['bien_so_xe'] ?? 'Chưa gán xe'}'), subtitle: Text('Trạng thái: ${profile['xe_trang_thai'] ?? 'Chưa có'}')),
          ])),
          const SizedBox(height: 24),
          OutlinedButton.icon(onPressed: onLogout, icon: const Icon(Icons.logout), label: const Text('Đăng xuất')),
        ],
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(36), child: Column(children: [Icon(icon, size: 52, color: AppColors.textDisabled), const SizedBox(height: 12), Text(text, textAlign: TextAlign.center)]));
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 52), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Thử lại'))])));
}
