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
  bool? _receivingOrders;
  bool _updatingStatus = false;
  String? _statusError;
  Timer? _offerTimer;
  bool _refreshingExpiredOffer = false;
  int _offerTicks = 0;

  @override
  void initState() {
    super.initState();
    _offerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _activeOrders.isNotEmpty || _receivingOrders != true) {
        return;
      }
      _offerTicks++;
      final expiredIds = _orders
          .where((order) {
            final expiresAt = DateTime.tryParse(
              '${order['loi_moi_het_han_luc'] ?? ''}',
            )?.toLocal();
            return expiresAt != null && !expiresAt.isAfter(DateTime.now());
          })
          .map((order) => order['id'])
          .toSet();

      if (expiredIds.isNotEmpty) {
        setState(
          () =>
              _orders.removeWhere((order) => expiredIds.contains(order['id'])),
        );
        unawaited(_refreshExpiredOffer());
      } else if (_orders.isNotEmpty) {
        setState(() {});
      }

      // Tự lấy lời mời mới, không bắt shipper phải nhấn cập nhật vị trí.
      if (_locationReady && _offerTicks % 5 == 0) {
        unawaited(_refreshExpiredOffer());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadActiveOrders();
      _loadReceivingStatus();
    });
  }

  @override
  void dispose() {
    _offerTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshExpiredOffer() async {
    if (_refreshingExpiredOffer) return;
    _refreshingExpiredOffer = true;
    try {
      await _refreshOrdersFromSavedLocation();
    } finally {
      _refreshingExpiredOffer = false;
    }
  }

  Future<void> _loadActiveOrders() async {
    try {
      final orders = await _service.getActiveOrders();
      if (mounted) {
        setState(() {
          _activeOrders = orders;
          if (orders.isNotEmpty) _orders = [];
        });
      }
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _loadReceivingStatus() async {
    try {
      final enabled = await _service.getReceivingStatus();
      if (!mounted) return;
      setState(() {
        _receivingOrders = enabled;
        _statusError = null;
        if (!enabled) _orders = [];
      });
      if (enabled && widget.embedded && !_locationReady) {
        unawaited(_updateLocationAndLoad());
      } else if (enabled && _locationReady) {
        unawaited(_refreshOrdersFromSavedLocation());
      }
    } on ShipperServiceException catch (error) {
      if (mounted) setState(() => _statusError = error.message);
    }
  }

  Future<void> _setReceivingStatus(bool enabled) async {
    setState(() => _updatingStatus = true);
    try {
      await _service.setReceivingStatus(enabled);
      if (!mounted) return;
      setState(() {
        _receivingOrders = enabled;
        if (!enabled) _orders = [];
      });
      if (enabled) unawaited(_updateLocationAndLoad());
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  Future<void> _refreshOrdersFromSavedLocation() async {
    try {
      final results = await Future.wait([
        _service.getActiveOrders(),
        if (_receivingOrders == true)
          _service.getNearbyOrders()
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);
      final active = results[0];
      final nearby = active.isEmpty ? results[1] : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _activeOrders = active;
        _orders = _receivingOrders == true ? nearby : [];
      });
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    }
  }

  Future<void> _updateLocationAndLoad() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _service.updateCurrentLocation();
      final results = await Future.wait([
        _service.getActiveOrders(),
        if (_receivingOrders == true)
          _service.getNearbyOrders()
        else
          Future.value(<Map<String, dynamic>>[]),
      ]);
      final active = results[0];
      final nearby = active.isEmpty ? results[1] : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _locationReady = true;
        _activeOrders = active;
        _orders = _receivingOrders == true ? nearby : [];
      });
    } on ShipperServiceException catch (error) {
      if (mounted) _showError(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(Map<String, dynamic> order) async {
    if (_receivingOrders != true) return;
    setState(() => _loading = true);
    try {
      await _service.updateCurrentLocation();
      await _service.acceptOrder(order['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã nhận đơn ${order['ma_van_don']}')),
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
      if (!mounted) return;
      final expired =
          error.message.contains('hết 30 giây') ||
          error.message.contains('không còn khả dụng');
      if (expired) {
        setState(
          () => _orders.removeWhere((item) => item['id'] == order['id']),
        );
        unawaited(_refreshExpiredOffer());
      } else {
        _showError(error.message);
      }
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
      color: AppColors.primary,
      backgroundColor: Theme.of(context).colorScheme.surface,
      onRefresh: _updateLocationAndLoad,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: _buildContent(context),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text(
          'Đơn gần bạn',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: content,
    );
  }

  List<Widget> _buildContent(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final receiving = _receivingOrders == true;

    // Tinh chỉnh màu sắc theo chủ đề
    final statusBgColor = receiving
        ? AppColors.primary.withValues(alpha: 0.1)
        : colors.surfaceContainerHigh;
    final statusBorderColor = receiving
        ? AppColors.primary.withValues(alpha: 0.3)
        : colors.outlineVariant;
    final statusIconColor = receiving
        ? AppColors.primary
        : colors.onSurfaceVariant;

    return [
      // THẺ TRẠNG THÁI HOẠT ĐỘNG
      AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: statusBgColor,
          border: Border.all(color: statusBorderColor),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: receiving
                        ? AppColors.primary
                        : colors.onSurfaceVariant.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    receiving
                        ? Icons.power_settings_new_rounded
                        : Icons.power_settings_new_rounded,
                    color: colors.surface,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Trạng thái hoạt động',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _receivingOrders == null
                            ? 'Đang tải...'
                            : receiving
                            ? 'Đang sẵn sàng nhận đơn'
                            : 'Tạm ngừng nhận đơn',
                        style: TextStyle(
                          color: receiving
                              ? AppColors.primary
                              : colors.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: receiving
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.embedded)
                  Switch.adaptive(
                    value: receiving,
                    activeThumbColor: AppColors.primary,
                    activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
                    onChanged: _receivingOrders == null || _updatingStatus
                        ? null
                        : _setReceivingStatus,
                  ),
              ],
            ),
            if (_updatingStatus) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
                color: AppColors.primary,
              ),
            ],
            if (_statusError != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loadReceivingStatus,
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 18,
                    color: AppColors.error,
                  ),
                  label: Text(
                    'Thử lại',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
              ),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Icon(
                  _locationReady
                      ? Icons.my_location_rounded
                      : Icons.location_off_outlined,
                  color: statusIconColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _locationReady
                            ? 'Vị trí đã cập nhật'
                            : 'Chưa có vị trí',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _locationReady
                            ? 'Đang quét đơn trong bán kính 10km'
                            : 'Bật vị trí để xem đơn gần bạn',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _loading ? null : _updateLocationAndLoad,
                  style: IconButton.styleFrom(
                    backgroundColor: colors.surface,
                    foregroundColor: AppColors.primary,
                  ),
                  tooltip: _locationReady ? 'Cập nhật vị trí' : 'Bật vị trí',
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),

      // DANH SÁCH ĐƠN ĐANG GIAO
      if (_activeOrders.isNotEmpty) ...[
        _SectionHeader(title: 'Đơn đang giao', count: _activeOrders.length),
        const SizedBox(height: 12),
        ..._activeOrders.map(
          (order) =>
              _ActiveOrderCard(order: order, onResume: () => _resume(order)),
        ),
        const SizedBox(height: 20),
      ],

      // DANH SÁCH ĐƠN GẦN ĐÂY
      _SectionHeader(
        title: 'Đơn có thể nhận',
        count: _activeOrders.isNotEmpty ? null : _orders.length,
        trailingText: _activeOrders.isNotEmpty ? 'Đang khóa' : null,
      ),
      const SizedBox(height: 12),

      // CÁC TRẠNG THÁI TRỐNG (EMPTY STATES)
      if (_activeOrders.isNotEmpty)
        const _EmptyState(
          icon: Icons.lock_clock_outlined,
          title: 'Đang bận giao hàng',
          text: 'Hoàn thành đơn hiện tại để mở khóa nhận đơn mới',
        )
      else if (_receivingOrders == false)
        const _EmptyState(
          icon: Icons.pause_circle_filled_rounded,
          title: 'Đang tạm nghỉ',
          text: 'Bật Trạng thái hoạt động để bắt đầu nhận đơn',
        )
      else if (_loading)
        const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        )
      else if (!_locationReady)
        const _EmptyState(
          icon: Icons.location_disabled_rounded,
          title: 'Chưa có vị trí',
          text: 'Vui lòng cập nhật vị trí để tìm đơn xung quanh',
        )
      else if (_orders.isEmpty)
        const _EmptyState(
          icon: Icons.inventory_2_rounded,
          title: 'Chưa có đơn hàng',
          text: 'Hiện tại chưa có đơn hàng nào quanh khu vực của bạn',
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

// ==========================================
// THÀNH PHẦN GIAO DIỆN PHỤ TRỢ (WIDGETS)
// ==========================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count, this.trailingText});
  final String title;
  final int? count;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (trailingText != null)
          Text(
            trailingText!,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          )
        else if (count != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count đơn',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order, required this.onResume});

  final Map<String, dynamic> order;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final pickedUp = order['trang_thai'] != 'CHO_LAY_HANG';
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Thanh màu nhấn bên trái
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 5,
              child: Container(color: AppColors.primary),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.local_shipping_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Đơn hàng ${order['ma_van_don']}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              pickedUp
                                  ? 'Đang giao tới người nhận'
                                  : 'Đang đến điểm lấy hàng',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Thu nhập dự kiến:',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      Text(
                        _formatMoney(order['tien_shipper_du_kien']),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onResume,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text(
                      'Tiếp tục giao hàng',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
    final colors = Theme.of(context).colorScheme;
    final distance = (order['khoang_cach_den_diem_lay_km'] as num).toDouble();
    final expiresAt = DateTime.tryParse(
      '${order['loi_moi_het_han_luc'] ?? ''}',
    )?.toLocal();
    final secondsLeft = expiresAt == null
        ? 0
        : ((expiresAt.difference(DateTime.now()).inMilliseconds + 999) ~/ 1000)
              .clamp(0, 30);

    // Đổi màu đỏ nếu thời gian sắp hết (dưới 10 giây)
    final isUrgent = secondsLeft <= 10;
    final timerColor = isUrgent ? colors.error : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề & Đồng hồ
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order['ma_van_don'] as String,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.directions_bike_rounded,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${distance.toStringAsFixed(1)} km tới điểm lấy',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: timerColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: timerColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 16, color: timerColor),
                      const SizedBox(width: 4),
                      Text(
                        '${secondsLeft}s',
                        style: TextStyle(
                          color: timerColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),

            // Thông tin địa chỉ
            _LocationLine(
              icon: Icons.storefront_rounded,
              iconColor: Colors.blue,
              title: order['nguoi_gui_ten'] as String,
              subtitle: order['nguoi_gui_dia_chi'] as String,
            ),
            const SizedBox(height: 12),
            _LocationLine(
              icon: Icons.location_on_rounded,
              iconColor: AppColors.primary,
              title: 'Người nhận', // Hoặc tên người nhận nếu có trong map
              subtitle: order['nguoi_nhan_dia_chi'] as String,
            ),

            const SizedBox(height: 16),

            // Thu nhập
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Thu nhập shipper',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    _formatMoney(order['tien_shipper_du_kien']),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Nút bấm
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: secondsLeft > 0 ? onReject : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: BorderSide(color: colors.outlineVariant),
                    ),
                    child: Text(
                      'Bỏ qua',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: secondsLeft > 0 ? onAccept : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'NHẬN ĐƠN NGAY',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Widget rút gọn hiển thị địa chỉ đẹp hơn
class _LocationLine extends StatelessWidget {
  const _LocationLine({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Hàm format tiền dùng chung
String _formatMoney(dynamic value) {
  final number = (value as num?)?.round() ?? 0;
  final formatted = number.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]}.',
  );
  return '$formattedđ';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}
