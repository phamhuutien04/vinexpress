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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 28),
          const CircleAvatar(
            radius: 44,
            backgroundColor: AppColors.primary,
            child: Icon(
              Icons.delivery_dining_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            employee['vai_tro'] == 'VAN_CHUYEN'
                ? 'Nhân viên vận chuyển'
                : 'Shipper',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _row(
                    Icons.phone_outlined,
                    '${employee['so_dien_thoai'] ?? ''}',
                  ),
                  const Divider(height: 24),
                  _row(Icons.email_outlined, '${employee['email'] ?? ''}'),
                  const Divider(height: 24),
                  _row(Icons.verified_outlined, 'Đã duyệt hoạt động'),
                ],
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BankAccountScreen()),
            ),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Tài khoản ngân hàng'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    );
  }
}
