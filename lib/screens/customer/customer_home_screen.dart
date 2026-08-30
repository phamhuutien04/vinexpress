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

  Map<String, dynamic> get _customer =>
      CustomerAuthService.currentCustomer ?? const {};

  List<Map<String, dynamic>> get _recentOrders => _orders.take(3).toList();

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

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: 16,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandMark(),
            SizedBox(width: 10),
            Text(
              'VinExpress',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
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
                    const SizedBox(height: 18),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) {
            _openHistory(context);
          } else if (index == 2) {
            _openWallet(context);
          } else if (index == 3) {
            _openAccount(context);
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

  Future<void> _openHistory(
    BuildContext context, {
    String title = 'Lịch sử đơn hàng',
    Set<String>? statuses,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderHistoryScreen(title: title, statuses: statuses),
      ),
    );
    await _loadOrderSummary();
  }

  Future<void> _openWallet(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomerWalletScreen()),
    );
  }

  Future<void> _openAccount(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomerAccountScreen()),
    );
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: const Color(0xFF143B38),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF143B38).withValues(alpha: 0.18),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 650;
        final copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Xin chào, $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF9EDBD3), fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Gửi hàng nhanh, theo dõi rõ ràng.',
              style: TextStyle(
                color: Color(0xFFF4FAF9),
                fontSize: 27,
                height: 1.12,
                letterSpacing: -0.7,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'Tạo đơn và kiểm tra hành trình trong cùng một nơi.',
              style: TextStyle(color: Color(0xFFD3E5E2), height: 1.4),
            ),
          ],
        );
        final action = SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: onCreateOrder,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(CustomerUi.controlRadius),
              ),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'Tạo đơn mới',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [copy, const SizedBox(height: 20), action],
          );
        }
        return Row(
          children: [
            Expanded(child: copy),
            const SizedBox(width: 32),
            SizedBox(width: 190, child: action),
          ],
        );
      },
    ),
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
          const SizedBox(height: 10),
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 680;
      final active = _StatusTile(
        icon: Icons.local_shipping_outlined,
        title: 'Đang vận chuyển',
        value: delivering,
        accent: true,
        onTap: onDelivering,
      );
      final waitingTile = _StatusTile(
        icon: Icons.inventory_2_outlined,
        title: 'Chờ lấy hàng',
        value: waiting,
        onTap: onWaiting,
      );
      final deliveredTile = _StatusTile(
        icon: Icons.check_circle_outline_rounded,
        title: 'Đã giao',
        value: delivered,
        onTap: onDelivered,
      );
      if (!wide) {
        return Column(
          children: [
            active,
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: waitingTile),
                const SizedBox(width: 10),
                Expanded(child: deliveredTile),
              ],
            ),
          ],
        );
      }
      return SizedBox(
        height: 210,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 7, child: active),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  Expanded(child: waitingTile),
                  const SizedBox(height: 12),
                  Expanded(child: deliveredTile),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final int value;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = accent ? AppColors.primary : colors.surfaceContainerLow;
    final foreground = accent ? Colors.white : colors.onSurface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(CustomerUi.surfaceRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CustomerUi.surfaceRadius),
            border: accent ? null : Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent
                      ? Colors.white.withValues(alpha: 0.18)
                      : AppColors.primary10,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  icon,
                  color: accent ? Colors.white : AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$value',
                      style: TextStyle(
                        color: foreground,
                        fontSize: accent ? 30 : 23,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent
                            ? Colors.white.withValues(alpha: 0.9)
                            : colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: accent
                    ? Colors.white.withValues(alpha: 0.8)
                    : colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => CustomerPanel(
    padding: EdgeInsets.zero,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actions = [
          _QuickAction(
            icon: Icons.receipt_long_outlined,
            label: 'Đơn hàng',
            onTap: onOrders,
          ),
          _QuickAction(
            icon: Icons.account_balance_wallet_outlined,
            label: 'Ví của tôi',
            onTap: onWallet,
          ),
          _QuickAction(
            icon: Icons.manage_accounts_outlined,
            label: 'Tài khoản',
            onTap: onAccount,
          ),
        ];
        if (constraints.maxWidth < 520) return Column(children: actions);
        return Row(
          children: actions.map((action) => Expanded(child: action)).toList(),
        );
      },
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(CustomerUi.surfaceRadius),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.orders});

  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) => CustomerPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (var index = 0; index < orders.length; index++) ...[
          _RecentOrderRow(order: orders[index]),
          if (index < orders.length - 1)
            Divider(
              height: 1,
              indent: 72,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
        ],
      ],
    ),
  );
}

class _RecentOrderRow extends StatelessWidget {
  const _RecentOrderRow({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final statusValue = '${order['trang_thai']}';
    final status = _status(statusValue);
    final canTrack = const {
      'CHO_LAY_HANG',
      'DA_LAY_HANG',
      'GIAO_CHO_SHIPPER',
      'DANG_GIAO_HANG',
    }.contains(statusValue);
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(CustomerUi.surfaceRadius),
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
                borderRadius: BorderRadius.circular(14),
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

  static _HomeStatus _status(String value) {
    if (value == 'CHO_LAY_HANG') {
      return const _HomeStatus('Chờ lấy', Color(0xFFB26A00));
    }
    if (value == 'DA_LAY_HANG') {
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
