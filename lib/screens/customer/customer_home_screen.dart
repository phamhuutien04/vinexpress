import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/order_service.dart';
import '../auth/login_screen.dart';
import 'create_order_screen.dart';
import 'order_history_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  final _orderService = OrderService();
  int _waitingCount = 0;
  int _deliveringCount = 0;
  int _deliveredCount = 0;
  List<Map<String, dynamic>> _recentOrders = [];

  Map<String, dynamic> get _customer =>
      CustomerAuthService.currentCustomer ?? const {};

  @override
  void initState() {
    super.initState();
    _loadOrderSummary();
  }

  Future<void> _loadOrderSummary() async {
    try {
      final orders = await _orderService.getCustomerOrders();
      if (!mounted) return;
      setState(() {
        _recentOrders = orders.take(3).toList();
        _waitingCount = orders
            .where((order) => order['trang_thai'] == 'CHO_LAY_HANG')
            .length;
        _deliveredCount = orders
            .where((order) => order['trang_thai'] == 'DA_GIAO_HANG')
            .length;
        _deliveringCount = orders.where((order) {
          return const {
            'DA_LAY_HANG',
            'DANG_VAN_CHUYEN',
            'DEN_KHO_TRUNG_CHUYEN',
            'DEN_KHO_DICH',
            'GIAO_CHO_SHIPPER',
            'DANG_GIAO_HANG',
          }.contains(order['trang_thai']);
        }).length;
      });
    } on OrderServiceException {
      // Màn hình lịch sử sẽ hiển thị lỗi chi tiết nếu RPC chưa được cài đặt.
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (_customer['ho_ten'] as String?)?.trim();
    final displayName = name == null || name.isEmpty ? 'Khách hàng' : name;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 210,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            title: const Text(
              'VINEXPRESS',
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
            actions: [
              IconButton(
                tooltip: 'Thông báo',
                onPressed: () {},
                icon: const Badge(
                  smallSize: 8,
                  child: Icon(Icons.notifications_none_rounded),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Tài khoản',
                icon: const CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person_outline, color: Colors.white),
                ),
                onSelected: (value) {
                  if (value == 'logout') _logout(context);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded),
                        SizedBox(width: 10),
                        Text('Đăng xuất'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                ),
                padding: const EdgeInsets.fromLTRB(20, 92, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      'Xin chào,',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Hôm nay bạn muốn gửi hàng đến đâu?',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 110),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _CreateOrderBanner(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CreateOrderScreen(),
                      ),
                    );
                    await _loadOrderSummary();
                  },
                ),
                const SizedBox(height: 24),
                _SectionTitle(
                  title: 'Tra cứu vận đơn',
                  action: 'Xem lịch sử',
                  onTap: () => _openHistory(context),
                ),
                const SizedBox(height: 12),
                const _TrackingBox(),
                const SizedBox(height: 24),
                const _SectionTitle(title: 'Đơn hàng của tôi'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _StatusCard(
                      icon: Icons.inventory_2_outlined,
                      label: 'Chờ lấy',
                      value: '$_waitingCount',
                      color: Color(0xFFFFA726),
                    ),
                    SizedBox(width: 10),
                    _StatusCard(
                      icon: Icons.local_shipping_outlined,
                      label: 'Đang giao',
                      value: '$_deliveringCount',
                      color: Color(0xFF42A5F5),
                    ),
                    SizedBox(width: 10),
                    _StatusCard(
                      icon: Icons.check_circle_outline,
                      label: 'Đã giao',
                      value: '$_deliveredCount',
                      color: AppColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const _SectionTitle(title: 'Tiện ích'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _UtilityButton(
                      icon: Icons.calculate_outlined,
                      label: 'Ước tính phí',
                      onTap: () {},
                    ),
                    _UtilityButton(
                      icon: Icons.location_on_outlined,
                      label: 'Tìm bưu cục',
                      onTap: () {},
                    ),
                    _UtilityButton(
                      icon: Icons.headset_mic_outlined,
                      label: 'Hỗ trợ',
                      onTap: () {},
                    ),
                    _UtilityButton(
                      icon: Icons.help_outline_rounded,
                      label: 'Hướng dẫn',
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_recentOrders.isEmpty)
                  const _EmptyOrders()
                else
                  _RecentOrders(
                    orders: _recentOrders,
                    onViewAll: () => _openHistory(context),
                  ),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) {
            _openHistory(context);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Đơn hàng',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await CustomerAuthService().logout();
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _openHistory(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
    );
    await _loadOrderSummary();
  }
}

class _CreateOrderBanner extends StatelessWidget {
  const _CreateOrderBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: AppColors.primary10,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.add_box_outlined,
                  color: AppColors.primary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tạo đơn hàng mới',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gửi hàng nhanh chóng chỉ trong vài bước',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const CircleAvatar(
                backgroundColor: AppColors.primary,
                child: Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackingBox extends StatefulWidget {
  const _TrackingBox();

  @override
  State<_TrackingBox> createState() => _TrackingBoxState();
}

class _TrackingBoxState extends State<_TrackingBox> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        hintText: 'Nhập mã vận đơn',
        prefixIcon: const Icon(Icons.qr_code_scanner_rounded),
        suffixIcon: Padding(
          padding: const EdgeInsets.all(6),
          child: FilledButton(
            onPressed: () {
              if (_controller.text.trim().isEmpty) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Đang tra cứu ${_controller.text.trim().toUpperCase()}',
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Text('Tra cứu'),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 7),
            Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _UtilityButton extends StatelessWidget {
  const _UtilityButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary10,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 42,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: 10),
          Text(
            'Chưa có đơn hàng gần đây',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Các đơn hàng mới nhất của bạn sẽ hiển thị tại đây.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.orders, required this.onViewAll});

  final List<Map<String, dynamic>> orders;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Đơn hàng gần đây',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton(onPressed: onViewAll, child: const Text('Xem tất cả')),
          ],
        ),
        const SizedBox(height: 8),
        ...orders.map((order) => _RecentOrderCard(order: order)),
      ],
    );
  }
}

class _RecentOrderCard extends StatelessWidget {
  const _RecentOrderCard({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final status = _status('${order['trang_thai']}');
    final createdAt = DateTime.tryParse('${order['ngay_tao']}')?.toLocal();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${order['ma_van_don']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${order['nguoi_nhan_dia_chi']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 7),
              Text(
                '${createdAt.day.toString().padLeft(2, '0')}/'
                '${createdAt.month.toString().padLeft(2, '0')}/'
                '${createdAt.year} '
                '${createdAt.hour.toString().padLeft(2, '0')}:'
                '${createdAt.minute.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static _HomeStatus _status(String value) {
    if (value == 'CHO_LAY_HANG') {
      return const _HomeStatus('Chờ lấy hàng', Colors.orange);
    }
    if (value == 'DA_GIAO_HANG') {
      return const _HomeStatus('Đã giao', AppColors.success);
    }
    if (value == 'DA_HUY') {
      return const _HomeStatus('Đã hủy', AppColors.error);
    }
    return const _HomeStatus('Đang giao', Colors.blue);
  }
}

class _HomeStatus {
  const _HomeStatus(this.label, this.color);
  final String label;
  final Color color;
}
