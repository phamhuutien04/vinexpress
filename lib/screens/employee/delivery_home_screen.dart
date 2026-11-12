import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/customer_auth_service.dart';
import '../../services/shipper_service.dart';
import '../auth/login_screen.dart';
import '../shipper/nearby_orders_screen.dart';
import '../shipper/shipper_order_history_screen.dart';
import '../shipper/shipper_wallet_screen.dart';
import '../wallet/bank_account_screen.dart';

class DeliveryHomeScreen extends StatefulWidget {
  const DeliveryHomeScreen({super.key});

  @override
  State<DeliveryHomeScreen> createState() => _DeliveryHomeScreenState();
}

class _DeliveryHomeScreenState extends State<DeliveryHomeScreen> {
  final _shipperService = ShipperService();
  int _tab = 0;
  int _nearbyRevision = 0;
  bool? _receivingOrders;
  bool _updatingAvailability = false;
  String? _availabilityError;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    try {
      final enabled = await _shipperService.getReceivingStatus();
      if (!mounted) return;
      setState(() {
        _receivingOrders = enabled;
        _availabilityError = null;
      });
    } on ShipperServiceException catch (error) {
      if (mounted) setState(() => _availabilityError = error.message);
    }
  }

  Future<void> _setAvailability(bool enabled) async {
    setState(() => _updatingAvailability = true);
    try {
      await _shipperService.setReceivingStatus(enabled);
      if (!mounted) return;
      setState(() {
        _receivingOrders = enabled;
        _availabilityError = null;
        _nearbyRevision++;
      });
    } on ShipperServiceException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingAvailability = false);
    }
  }

  String get _name =>
      CustomerAuthService.currentEmployee?['ho_ten'] as String? ?? 'Shipper';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(switch (_tab) {
          0 => 'Nhận đơn gần bạn',
          1 => 'Ví shipper',
          2 => 'Lịch sử giao hàng',
          _ => 'Tài khoản shipper',
        }),
      ),
      drawer: Drawer(
        width: MediaQuery.sizeOf(context).width < 360
            ? MediaQuery.sizeOf(context).width * .88
            : 310,
        child: Builder(builder: (drawerContext) => _buildDrawer(drawerContext)),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          NearbyOrdersScreen(key: ValueKey(_nearbyRevision), embedded: true),
          const ShipperWalletScreen(),
          const ShipperOrderHistoryScreen(),
          _ProfilePage(name: _name, onLogout: _logout),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext drawerContext) {
    final colors = Theme.of(context).colorScheme;
    void goTo(int tab) {
      Navigator.of(drawerContext).pop();
      setState(() => _tab = tab);
    }

    Widget destination(int tab, IconData icon, String label) => ListTile(
      leading: Icon(
        icon,
        color: _tab == tab ? AppColors.primary : colors.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: _tab == tab ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: _tab == tab,
      selectedTileColor: AppColors.primary.withValues(alpha: .1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: () => goTo(tab),
    );

    return SafeArea(
      child: Column(
        children: [
          InkWell(
            onTap: () => goTo(3),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.primary.withValues(alpha: .14),
                    child: const Icon(
                      Icons.delivery_dining_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Shipper giao chặng ngắn',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              children: [
                SwitchListTile.adaptive(
                  title: const Text(
                    'Trạng thái hoạt động',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _receivingOrders == null
                        ? 'Đang tải trạng thái'
                        : _receivingOrders!
                        ? 'Đang nhận đơn mới'
                        : 'Tạm ngừng nhận đơn',
                  ),
                  value: _receivingOrders ?? false,
                  activeTrackColor: AppColors.primary,
                  onChanged: _receivingOrders == null || _updatingAvailability
                      ? null
                      : _setAvailability,
                ),
                if (_updatingAvailability)
                  const LinearProgressIndicator(minHeight: 2),
                if (_availabilityError != null)
                  TextButton.icon(
                    onPressed: _loadAvailability,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tải lại trạng thái'),
                  ),
                const SizedBox(height: 16),
                destination(0, Icons.near_me_outlined, 'Đơn gần bạn'),
                destination(2, Icons.history_rounded, 'Lịch sử đơn hàng'),
                destination(
                  1,
                  Icons.account_balance_wallet_outlined,
                  'Ví và thu nhập',
                ),
                const SizedBox(height: 16),
                Divider(color: colors.outlineVariant),
                destination(3, Icons.person_outline_rounded, 'Tài khoản'),
                ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: const Text('Tài khoản ngân hàng'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onTap: () {
                    Navigator.of(drawerContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BankAccountScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Đăng xuất'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () {
                Navigator.of(drawerContext).pop();
                _logout();
              },
            ),
          ),
        ],
      ),
    );
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

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.name, required this.onLogout});
  final String name;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final employee = CustomerAuthService.currentEmployee ?? const {};
    final colors = Theme.of(context).colorScheme;
    final role = employee['vai_tro'] == 'VAN_CHUYEN'
        ? 'Nhân viên vận chuyển'
        : 'Shipper giao chặng ngắn';
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [
                  AppColors.primary,
                  AppColors.primary.withValues(alpha: .78),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: .2),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .32),
                    ),
                  ),
                  child: Text(
                    initials.isEmpty ? 'S' : initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TÀI KHOẢN SHIPPER',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        role,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Thông tin cá nhân',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _InfoPanel(
            children: [
              _ProfileItem(
                icon: Icons.phone_outlined,
                label: 'Số điện thoại',
                value: '${employee['so_dien_thoai'] ?? 'Chưa cập nhật'}',
              ),
              const Divider(height: 1),
              _ProfileItem(
                icon: Icons.alternate_email_rounded,
                label: 'Email',
                value: '${employee['email'] ?? 'Chưa cập nhật'}',
              ),
              const Divider(height: 1),
              const _ProfileItem(
                icon: Icons.verified_rounded,
                label: 'Trạng thái tài khoản',
                value: 'Đã xác thực',
                valueColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            'Thanh toán',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _InfoPanel(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BankAccountScreen()),
                ),
                child: const _ProfileItem(
                  icon: Icons.account_balance_outlined,
                  label: 'Tài khoản ngân hàng',
                  value: 'Quản lý tài khoản nhận tiền',
                  showArrow: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Đăng xuất khỏi tài khoản'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: colors.error,
              side: BorderSide(color: colors.error.withValues(alpha: .55)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .65)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(children: children),
      ),
    );
  }
}

class _ProfileItem extends StatelessWidget {
  const _ProfileItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.showArrow = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor ?? colors.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (showArrow)
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ],
      ),
    );
  }
}
