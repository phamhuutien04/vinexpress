import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/last_mile_staff_service.dart';
import '../auth/login_screen.dart';
import 'employee_wallet_screen.dart';
import 'pickup_navigation_screen.dart';

class LastMileStaffScreen extends StatefulWidget {
  const LastMileStaffScreen({super.key});
  @override
  State<LastMileStaffScreen> createState() => _LastMileStaffScreenState();
}

class _LastMileStaffScreenState extends State<LastMileStaffScreen> {
  final _service = LastMileStaffService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tasks = [];
  final Set<int> _busyOrderIds = {};
  bool _showMyOrders = false;
  int _tabIndex = 0;
  bool get _pickup =>
      CustomerAuthService.currentEmployee?['vai_tro'] == 'NHAN_VIEN_LAY_HANG';

  List<Map<String, dynamic>> get _visibleTasks => _pickup
      ? _tasks
            .where((item) => (item['da_nhan'] == true) == _showMyOrders)
            .toList()
      : _tasks;

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
      final tasks = await _service.tasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final employee = CustomerAuthService.currentEmployee;
    final employeeName = '${employee?['ho_ten'] ?? 'Nhân viên'}';
    final availableCount = _tasks
        .where((item) => item['da_nhan'] != true)
        .length;
    final mineCount = _tasks.where((item) => item['da_nhan'] == true).length;
    final visibleTasks = _visibleTasks;
    return Scaffold(
      appBar: AppBar(
        title: Text(_pickup ? 'Nhân viên lấy hàng' : 'Nhân viên giao hàng'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') _logout();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Đăng xuất')),
            ],
          ),
        ],
      ),
      body: _pickup && _tabIndex == 3
          ? _PickupAccount(
              employee: employee ?? const <String, dynamic>{},
              onLogout: _logout,
            )
          : _pickup && _tabIndex == 2
          ? const EmployeeWalletScreen()
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _StaffHeader(
                      employeeName: employeeName,
                      pickup: _pickup,
                      availableCount: availableCount,
                      mineCount: mineCount,
                    ),
                  ),
                  if (_loading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ErrorState(message: _error!, onRetry: _load),
                    )
                  else if (visibleTasks.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(
                        message: _pickup
                            ? _showMyOrders
                                  ? 'Bạn chưa nhận đơn lấy hàng nào'
                                  : 'Chưa có đơn mới trong khu vực phụ trách'
                            : 'Hãy quét mã trên kiện hàng tại kho',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList.builder(
                        itemCount: visibleTasks.length,
                        itemBuilder: (_, index) =>
                            _taskCard(visibleTasks[index]),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: _pickup
          ? null
          : FloatingActionButton.extended(
              onPressed: _scanParcel,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Quét kiện tại kho'),
            ),
      bottomNavigationBar: _pickup
          ? NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _tabIndex = index;
                  if (index < 2) _showMyOrders = index == 1;
                });
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.inventory_2_outlined),
                  selectedIcon: const Icon(Icons.inventory_2),
                  label: 'Đơn mới ($availableCount)',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.delivery_dining_outlined),
                  selectedIcon: const Icon(Icons.delivery_dining),
                  label: 'Đơn của tôi ($mineCount)',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet_outlined),
                  selectedIcon: Icon(Icons.account_balance_wallet),
                  label: 'Ví',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Tài khoản',
                ),
              ],
            )
          : null,
    );
  }

  Widget _taskCard(Map<String, dynamic> item) {
    final delivering = item['trang_thai'] == 'DANG_GIAO_HANG';
    final claimed = item['da_nhan'] == true;
    final id = (item['id'] as num).toInt();
    final busy = _busyOrderIds.contains(id);
    final phone = '${item['so_dien_thoai'] ?? ''}';
    final address = '${item['dia_chi'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['ma_van_don']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    _pickup
                        ? claimed
                              ? 'Bạn đã nhận'
                              : 'Đang mở'
                        : 'Đã quét',
                  ),
                ),
              ],
            ),
            _InfoLine(
              icon: Icons.person_outline_rounded,
              text: '${item['ten_khach']}',
              strong: true,
            ),
            _InfoLine(icon: Icons.phone_outlined, text: phone),
            _InfoLine(icon: Icons.location_on_outlined, text: address),
            const Divider(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warehouse_outlined,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _pickup
                          ? 'Kho trả hàng: ${item['ten_kho']}'
                          : 'Kho nhận hàng: ${item['ten_kho']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: phone.isEmpty ? null : () => _call(phone),
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Gọi khách'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: address.isEmpty
                        ? null
                        : () => _directions(address),
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Chỉ đường'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () => _pickup && !claimed
                        ? _claimPickup(item)
                        : _pickup
                        ? _openPickupNavigation(item)
                        : _confirmWithPrompt(id, claimed: claimed),
              icon: Icon(
                busy
                    ? Icons.hourglass_top_rounded
                    : _pickup && !claimed
                    ? Icons.pan_tool_alt_outlined
                    : delivering
                    ? Icons.check_circle_outline
                    : Icons.delivery_dining,
              ),
              label: Text(
                busy
                    ? 'Đang xử lý...'
                    : _pickup
                    ? claimed
                          ? 'Mở chỉ đường lấy hàng'
                          : 'Nhận đơn này'
                    : delivering
                    ? 'Xác nhận đã giao'
                    : 'Bắt đầu giao hàng',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claimPickup(Map<String, dynamic> item) async {
    final id = (item['id'] as num).toInt();
    setState(() => _busyOrderIds.add(id));
    try {
      await _service.claimPickup(id);
      if (!mounted) return;
      final claimedOrder = Map<String, dynamic>.from(item)..['da_nhan'] = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã nhận đơn, đang mở chỉ đường'),
          backgroundColor: AppColors.success,
        ),
      );
      await _openPickupNavigation(claimedOrder);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyOrderIds.remove(id));
        await _load();
      }
    }
  }

  Future<void> _openPickupNavigation(Map<String, dynamic> item) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PickupNavigationScreen(order: item)),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _confirmWithPrompt(int id, {required bool claimed}) async {
    if (_pickup && claimed) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Xác nhận đã lấy hàng?'),
          content: const Text(
            'Chỉ xác nhận khi bạn đã nhận đúng kiện hàng từ người gửi. '
            'Sau đó hãy mang kiện về kho được chỉ định.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Chưa lấy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Đã lấy hàng'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    await _runForOrder(
      id,
      () => _service.confirm(id),
      _pickup ? 'Đã xác nhận lấy hàng' : 'Đã cập nhật trạng thái giao hàng',
    );
  }

  Future<void> _runForOrder(
    int id,
    Future<dynamic> Function() action,
    String successMessage,
  ) async {
    setState(() => _busyOrderIds.add(id));
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: AppColors.success,
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busyOrderIds.remove(id));
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
    if (!await launchUrl(uri)) {
      _showActionError('Không thể mở ứng dụng gọi điện');
    }
  }

  Future<void> _directions(String address) async {
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': address,
      'travelmode': 'driving',
    });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showActionError('Không thể mở bản đồ chỉ đường');
    }
  }

  void _showActionError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.error),
    );
  }

  Future<void> _run(Future<dynamic> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _scanParcel() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _ParcelScannerPage()),
    );
    if (code == null || code.trim().isEmpty) return;
    await _run(() => _service.scanDeliveryParcel(code));
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

class _StaffHeader extends StatelessWidget {
  const _StaffHeader({
    required this.employeeName,
    required this.pickup,
    required this.availableCount,
    required this.mineCount,
  });

  final String employeeName;
  final bool pickup;
  final int availableCount;
  final int mineCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF27C2D2)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: .2),
                child: Icon(
                  pickup
                      ? Icons.delivery_dining
                      : Icons.local_shipping_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employeeName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 19,
                      ),
                    ),
                    Text(
                      pickup
                          ? 'Phụ trách lấy hàng trong khu vực'
                          : 'Phụ trách giao hàng chặng cuối',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pickup) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _HeaderMetric(
                    value: '$availableCount',
                    label: 'Đơn có thể nhận',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeaderMetric(
                    value: '$mineCount',
                    label: 'Đơn của tôi',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 24,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.text,
    this.strong = false,
  });
  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AppColors.textSecondary),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontWeight: strong ? FontWeight.w700 : null),
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          const Text(
            'Kéo xuống để làm mới danh sách',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 58,
            color: AppColors.error,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    ),
  );
}

class _PickupAccount extends StatelessWidget {
  const _PickupAccount({required this.employee, required this.onLogout});
  final Map<String, dynamic> employee;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final name = '${employee['ho_ten'] ?? 'Nhân viên'}';
    final phone = '${employee['so_dien_thoai'] ?? 'Chưa cập nhật'}';
    final email = '${employee['email'] ?? 'Chưa cập nhật'}';
    final warehouse =
        '${employee['ten_kho'] ?? employee['kho_hang_ten'] ?? 'Kho đã phân công'}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 12),
        Center(
          child: CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.primary.withValues(alpha: .12),
            child: Text(
              name.isEmpty ? 'N' : name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
                fontSize: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          name,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const Text(
          'Nhân viên lấy hàng',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.phone_outlined),
                title: const Text('Số điện thoại'),
                subtitle: Text(phone),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Email'),
                subtitle: Text(email),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.warehouse_outlined),
                title: const Text('Kho làm việc'),
                subtitle: Text(warehouse),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Trạng thái'),
                subtitle: Text('${employee['trang_thai'] ?? 'HOAT_DONG'}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: onLogout,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Đăng xuất'),
        ),
      ],
    );
  }
}

class _ParcelScannerPage extends StatefulWidget {
  const _ParcelScannerPage();
  @override
  State<_ParcelScannerPage> createState() => _ParcelScannerPageState();
}

class _ParcelScannerPageState extends State<_ParcelScannerPage> {
  bool _handled = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quét mã kiện hàng')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (_handled || capture.barcodes.isEmpty) return;
            final value = capture.barcodes.first.rawValue;
            if (value == null || value.trim().isEmpty) return;
            _handled = true;
            Navigator.of(context).pop(value.trim());
          },
        ),
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 4),
              borderRadius: BorderRadius.circular(22),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Text(
            'Đưa mã QR trên kiện hàng vào giữa khung',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
