import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/order_service.dart';
import 'create_order_screen.dart';
import 'customer_account_screen.dart';
import 'customer_wallet_screen.dart';
import 'order_history_screen.dart';
import 'order_tracking_screen.dart';
import 'widgets/customer_design.dart';

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
  bool _loadingSummary = true;
  String? _summaryError;
  List<Map<String, dynamic>> _orders = [];
  int _selectedTab = 0;
  String _historyTitle = 'Lịch sử đơn hàng';
  Set<String>? _historyStatuses;

  Map<String, dynamic> get _customer =>
      CustomerAuthService.currentCustomer ?? const {};

  List<Map<String, dynamic>> get _recentOrders => _orders.take(3).toList();

  String get _historyKey {
    final statuses = _historyStatuses?.toList() ?? <String>[];
    statuses.sort();
    return '$_historyTitle:${statuses.join(',')}';
  }

  @override
  void initState() {
    super.initState();
    _loadOrderSummary();
  }

  Future<void> _loadOrderSummary() async {
    if (mounted) {
      setState(() {
        _loadingSummary = true;
        _summaryError = null;
      });
    }
    try {
      final orders = await _orderService.getCustomerOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
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
    } on OrderServiceException catch (error) {
      if (mounted) setState(() => _summaryError = error.message);
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (_customer['ho_ten'] as String?)?.trim();
    final displayName = name == null || name.isEmpty ? 'Khách hàng' : name;
    final theme = Theme.of(context);

    final homeTab = Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _BrandMark(),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'VinExpress',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  'Giao hàng mọi nơi',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Thông báo',
            onPressed: () => _notAvailable(context),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Tài khoản',
            onPressed: () => _openAccount(context),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          onRefresh: _loadOrderSummary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: CustomerUi.pagePadding(constraints.maxWidth, bottom: 110),
            children: [
              CustomerConstrained(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _CustomerHero(
                      name: displayName,
                      onCreateOrder: () => _openCreateOrder(context),
                    ),
                    const SizedBox(height: 14),
                    _TrackingPanel(
                      onTrack: (code) => _trackOrder(context, code),
                    ),
                    const SizedBox(height: 30),
                    CustomerSectionHeader(
                      title: 'Đơn hàng của bạn',
                      subtitle: 'Theo dõi nhanh trạng thái các đơn gần đây',
                      actionLabel: 'Xem tất cả',
                      onAction: () => _openHistory(context),
                    ),
                    const SizedBox(height: 14),
                    if (_loadingSummary)
                      const _SummarySkeleton()
                    else if (_summaryError != null)
                      CustomerPanel(
                        child: CustomerEmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'Chưa tải được đơn hàng',
                          message: _summaryError!,
                          actionLabel: 'Thử lại',
                          onAction: _loadOrderSummary,
                        ),
                      )
                    else
                      _OrderOverview(
                        waiting: _waitingCount,
                        delivering: _deliveringCount,
                        delivered: _deliveredCount,
                        onWaiting: () => _openHistory(
                          context,
                          title: 'Đơn chờ lấy hàng',
                          statuses: const {'CHO_LAY_HANG'},
                        ),
                        onDelivering: () => _openHistory(
                          context,
                          title: 'Đơn đang giao',
                          statuses: const {
                            'DA_LAY_HANG',
                            'DANG_VAN_CHUYEN',
                            'DEN_KHO_TRUNG_CHUYEN',
                            'DEN_KHO_DICH',
                            'GIAO_CHO_SHIPPER',
                            'DANG_GIAO_HANG',
                          },
                        ),
                        onDelivered: () => _openHistory(
                          context,
                          title: 'Đơn đã giao',
                          statuses: const {'DA_GIAO_HANG'},
                        ),
                      ),
                    const SizedBox(height: 30),
                    const CustomerSectionHeader(title: 'Truy cập nhanh'),
                    const SizedBox(height: 12),
                    _QuickActions(
                      onOrders: () => _openHistory(context),
                      onWallet: () => _openWallet(context),
                      onAccount: () => _openAccount(context),
                    ),
                    const SizedBox(height: 30),
                    CustomerSectionHeader(
                      title: 'Đơn gần đây',
                      actionLabel: _recentOrders.isEmpty ? null : 'Xem tất cả',
                      onAction: () => _openHistory(context),
                    ),
                    const SizedBox(height: 12),
                    if (_loadingSummary)
                      const Column(
                        children: [
                          CustomerSkeleton(height: 118),
                          SizedBox(height: 10),
                          CustomerSkeleton(height: 118),
                        ],
                      )
                    else if (_recentOrders.isEmpty)
                      CustomerPanel(
                        child: CustomerEmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'Chưa có đơn hàng',
                          message: 'Tạo đơn đầu tiên để bắt đầu gửi hàng.',
                          actionLabel: 'Tạo đơn',
                          onAction: () => _openCreateOrder(context),
                        ),
                      )
                    else
                      _RecentOrders(orders: _recentOrders),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return PopScope(
      canPop: _selectedTab == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedTab != 0) {
          setState(() => _selectedTab = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _selectedTab,
          children: [
            homeTab,
            OrderHistoryScreen(
              key: ValueKey(_historyKey),
              title: _historyTitle,
              statuses: _historyStatuses,
            ),
            const CustomerWalletScreen(),
            const CustomerAccountScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Trang chủ',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: 'Đơn hàng',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: 'Ví',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_circle_outlined),
              selectedIcon: Icon(Icons.account_circle_rounded),
              label: 'Tài khoản',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateOrder(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateOrderScreen()),
    );
    await _loadOrderSummary();
  }

  Future<void> _trackOrder(BuildContext context, String code) async {
    final normalized = code.trim().toUpperCase();
    Map<String, dynamic>? match;
    for (final order in _orders) {
      if ('${order['ma_van_don']}'.trim().toUpperCase() == normalized) {
        match = order;
        break;
      }
    }
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy mã vận đơn của bạn.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OrderTrackingScreen(orderId: (match!['id'] as num).toInt()),
      ),
    );
  }

  void _selectTab(int index) {
    setState(() {
      _selectedTab = index;
      if (index == 1) {
        _historyTitle = 'Lịch sử đơn hàng';
        _historyStatuses = null;
      }
    });
  }

  void _openHistory(
    BuildContext context, {
    String title = 'Lịch sử đơn hàng',
    Set<String>? statuses,
  }) {
    setState(() {
      _historyTitle = title;
      _historyStatuses = statuses;
      _selectedTab = 1;
    });
  }

  void _openWallet(BuildContext context) {
    setState(() => _selectedTab = 2);
  }

  void _openAccount(BuildContext context) {
    setState(() => _selectedTab = 3);
  }

  void _notAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tính năng này đang được hoàn thiện.')),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(11),
    ),
    child: const Icon(
      Icons.local_shipping_rounded,
      color: Colors.white,
      size: 20,
    ),
  );
}

class _CustomerHero extends StatelessWidget {
  const _CustomerHero({required this.name, required this.onCreateOrder});

  final String name;
  final VoidCallback onCreateOrder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 560;
      return Container(
        height: compact ? 330 : 270,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.2),
              blurRadius: 28,
              offset: const Offset(0, 13),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/customer/hero_courier.jpg',
              fit: BoxFit.cover,
              alignment: compact ? Alignment.centerRight : Alignment.center,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xF5007669), Color(0xA300BFA5)],
                  stops: [0.12, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.32),
                      ),
                    ),
                    child: Text(
                      'Xin chào, $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(
                    width: 280,
                    child: Text(
                      'Giao tận nơi,\ntrọn vẹn niềm tin.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        height: 1.07,
                        letterSpacing: -0.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 264,
                    child: Text(
                      'Tạo đơn trong vài bước. Theo dõi hành trình mọi lúc.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onCreateOrder,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF007E70),
                      minimumSize: const Size(156, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text(
                      'Tạo đơn mới',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _TrackingPanel extends StatefulWidget {
  const _TrackingPanel({required this.onTrack});

  final ValueChanged<String> onTrack;

  @override
  State<_TrackingPanel> createState() => _TrackingPanelState();
}

class _TrackingPanelState extends State<_TrackingPanel> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    widget.onTrack(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomerPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tra cứu vận đơn',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Xem hành trình đơn hàng của bạn',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Mã vận đơn',
              hintText: 'Ví dụ: VEX123456',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: Padding(
                padding: const EdgeInsets.all(6),
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Tra cứu'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderOverview extends StatelessWidget {
  const _OrderOverview({
    required this.waiting,
    required this.delivering,
    required this.delivered,
    required this.onWaiting,
    required this.onDelivering,
    required this.onDelivered,
  });

  final int waiting;
  final int delivering;
  final int delivered;
  final VoidCallback onWaiting;
  final VoidCallback onDelivering;
  final VoidCallback onDelivered;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _StatusTile(
            icon: Icons.inventory_2_outlined,
            title: 'Chờ lấy hàng',
            value: waiting,
            color: const Color(0xFFFF9500),
            onTap: onWaiting,
          ),
          _CustomerDivider(),
          _StatusTile(
            icon: Icons.local_shipping_outlined,
            title: 'Đang vận chuyển',
            value: delivering,
            color: AppColors.primary,
            onTap: onDelivering,
          ),
          _CustomerDivider(),
          _StatusTile(
            icon: Icons.check_circle_outline_rounded,
            title: 'Đã giao',
            value: delivered,
            color: const Color(0xFF34C759),
            onTap: onDelivered,
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String title;
  final int value;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomerDivider extends StatelessWidget {
  const _CustomerDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: 68,
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onOrders,
    required this.onWallet,
    required this.onAccount,
  });

  final VoidCallback onOrders;
  final VoidCallback onWallet;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actions = [
        _QuickAction(
          icon: Icons.receipt_long_outlined,
          label: 'Đơn hàng',
          caption: 'Xem đơn đã tạo',
          onTap: onOrders,
        ),
        _QuickAction(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Ví của tôi',
          caption: 'Nạp và quản lý ví',
          onTap: onWallet,
        ),
        _QuickAction(
          icon: Icons.manage_accounts_outlined,
          label: 'Tài khoản',
          caption: 'Thông tin cá nhân',
          onTap: onAccount,
        ),
      ];
      final columns = constraints.maxWidth >= 720
          ? 3
          : constraints.maxWidth >= 440
          ? 2
          : 1;
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: columns == 1 ? 4.2 : 1.85,
        children: actions,
      );
    },
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary10,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 15,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.orders});

  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var index = 0; index < orders.length; index++) ...[
            _RecentOrderRow(order: orders[index]),
            if (index < orders.length - 1) const _CustomerDivider(),
          ],
        ],
      ),
    );
  }
}

class _RecentOrderRow extends StatelessWidget {
  const _RecentOrderRow({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final statusValue = '${order['trang_thai']}';
    final status = _status(order);
    final canTrack = const {
      'CHO_LAY_HANG',
      'DA_LAY_HANG',
      'DANG_VAN_CHUYEN',
      'DEN_KHO_TRUNG_CHUYEN',
      'DEN_KHO_DICH',
      'GIAO_CHO_SHIPPER',
      'DANG_GIAO_HANG',
    }.contains(statusValue);
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: canTrack
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    OrderTrackingScreen(orderId: (order['id'] as num).toInt()),
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: status.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.inventory_2_outlined, color: status.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${order['ma_van_don']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        status.label,
                        style: TextStyle(
                          color: status.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${order['nguoi_nhan_dia_chi']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (canTrack) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ],
        ),
      ),
    );
  }

  static _HomeStatus _status(Map<String, dynamic> order) {
    final value = '${order['trang_thai']}';
    if (value == 'CHO_LAY_HANG') {
      return const _HomeStatus('Chờ lấy', Color(0xFFB26A00));
    }
    if (value == 'DA_LAY_HANG') {
      final distance = (order['khoang_cach_km'] as num?)?.toDouble();
      final isDirectDelivery =
          order['phuong_tien'] == 'XE_MAY' ||
          (distance != null && distance <= 50);
      if (isDirectDelivery) {
        return const _HomeStatus('Đang giao', Color(0xFF276E8C));
      }
      return const _HomeStatus('Về kho', Color(0xFF276E8C));
    }
    if (value == 'DA_GIAO_HANG') {
      return const _HomeStatus('Đã giao', Color(0xFF287A4B));
    }
    if (value == 'DA_HUY') {
      return const _HomeStatus('Đã hủy', AppColors.error);
    }
    return const _HomeStatus('Đang giao', Color(0xFF276E8C));
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      CustomerSkeleton(height: 108),
      SizedBox(height: 10),
      Row(
        children: [
          Expanded(child: CustomerSkeleton(height: 92)),
          SizedBox(width: 10),
          Expanded(child: CustomerSkeleton(height: 92)),
        ],
      ),
    ],
  );
}

class _HomeStatus {
  const _HomeStatus(this.label, this.color);

  final String label;
  final Color color;
}
