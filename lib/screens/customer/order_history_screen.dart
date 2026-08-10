import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/order_service.dart';
import 'order_tracking_screen.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({
    super.key,
    this.title = 'Lịch sử đơn hàng',
    this.statuses,
  });

  final String title;
  final Set<String>? statuses;

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final _service = OrderService();
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _orders = [];
  Set<String>? _statusFilter;
  DateTimeRange? _dateRange;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.statuses;
    _searchController.addListener(_applyFilters);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() => setState(() {});

  List<Map<String, dynamic>> get _filteredOrders {
    final query = _searchController.text.trim().toLowerCase();
    return _orders.where((order) {
      final statusMatches =
          _statusFilter == null ||
          _statusFilter!.contains('${order['trang_thai']}');
      final createdAt = DateTime.tryParse('${order['ngay_tao']}')?.toLocal();
      final dateMatches =
          _dateRange == null ||
          (createdAt != null &&
              !createdAt.isBefore(_dateRange!.start) &&
              createdAt.isBefore(_dateRange!.end.add(const Duration(days: 1))));
      final searchable = [
        order['ma_van_don'],
        order['nguoi_gui_dia_chi'],
        order['nguoi_nhan_dia_chi'],
        order['nguoi_nhan_ten'],
        order['nguoi_nhan_sdt'],
      ].join(' ').toLowerCase();
      return statusMatches &&
          dateMatches &&
          (query.isEmpty || searchable.contains(query));
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final orders = await _service.getCustomerOrders();
      if (mounted) setState(() => _orders = orders);
    } on OrderServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _filteredOrders;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 160),
                  const Icon(Icons.cloud_off_outlined, size: 52),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredOrders.length + 1,
                itemBuilder: (_, index) {
                  if (index == 0) {
                    return _OrderFilters(
                      searchController: _searchController,
                      selectedStatuses: _statusFilter,
                      dateRange: _dateRange,
                      onStatusesChanged: (value) {
                        setState(() => _statusFilter = value);
                      },
                      onPickDate: _pickDateRange,
                      onClearDate: () => setState(() => _dateRange = null),
                      resultCount: filteredOrders.length,
                    );
                  }
                  return _OrderHistoryCard(order: filteredOrders[index - 1]);
                },
              ),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange,
      helpText: 'Chọn khoảng ngày tạo đơn',
      saveText: 'Lọc',
    );
    if (picked != null && mounted) setState(() => _dateRange = picked);
  }
}

class _OrderFilters extends StatelessWidget {
  const _OrderFilters({
    required this.searchController,
    required this.selectedStatuses,
    required this.dateRange,
    required this.onStatusesChanged,
    required this.onPickDate,
    required this.onClearDate,
    required this.resultCount,
  });

  final TextEditingController searchController;
  final Set<String>? selectedStatuses;
  final DateTimeRange? dateRange;
  final ValueChanged<Set<String>?> onStatusesChanged;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final int resultCount;

  static const _delivering = {
    'DA_LAY_HANG',
    'DANG_VAN_CHUYEN',
    'GIAO_CHO_SHIPPER',
    'DANG_GIAO_HANG',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Tìm mã vận đơn, người nhận, địa chỉ...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('Tất cả', null),
                _chip('Chờ lấy', const {'CHO_LAY_HANG'}),
                _chip('Đang giao', _delivering),
                _chip('Đã giao', const {'DA_GIAO_HANG'}),
                _chip('Đã hủy', const {'DA_HUY'}),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickDate,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(
                    dateRange == null
                        ? 'Chọn khoảng ngày'
                        : '${_date(dateRange!.start)} – ${_date(dateRange!.end)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (dateRange != null)
                IconButton(
                  tooltip: 'Bỏ lọc ngày',
                  onPressed: onClearDate,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          Text(
            resultCount == 0
                ? 'Không tìm thấy đơn phù hợp'
                : '$resultCount đơn hàng',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Set<String>? statuses) {
    final selected = _sameStatuses(selectedStatuses, statuses);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onStatusesChanged(statuses),
      ),
    );
  }

  static bool _sameStatuses(Set<String>? first, Set<String>? second) {
    if (first == null || second == null) return first == null && second == null;
    return first.length == second.length && first.containsAll(second);
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}

class _OrderHistoryCard extends StatelessWidget {
  const _OrderHistoryCard({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final status = '${order['trang_thai']}';
    final statusInfo = _status(status);
    final createdAt = DateTime.tryParse('${order['ngay_tao']}')?.toLocal();
    final canTrack = const {
      'CHO_LAY_HANG',
      'DA_LAY_HANG',
      'GIAO_CHO_SHIPPER',
      'DANG_GIAO_HANG',
    }.contains(status);
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
                    '${order['ma_van_don']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusInfo.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusInfo.label,
                    style: TextStyle(
                      color: statusInfo.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                _date(createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const Divider(height: 24),
            _line(
              Icons.radio_button_checked,
              '${order['nguoi_gui_dia_chi']}',
              AppColors.primary,
            ),
            _line(
              Icons.location_on,
              '${order['nguoi_nhan_dia_chi']}',
              Colors.red,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_distance(order['khoang_cach_km'])} km'),
                Text(
                  _money(order['phi_van_chuyen']),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (canTrack) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OrderTrackingScreen(
                        orderId: (order['id'] as num).toInt(),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.my_location),
                  label: const Text('Theo dõi đơn hàng'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );

  static String _money(dynamic value) {
    final number = (value as num?)?.round() ?? 0;
    return '${number.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]}.')}đ';
  }

  static String _distance(dynamic value) {
    final distance = (value as num?)?.toDouble() ?? 0;
    return distance.toStringAsFixed(2).replaceFirst('.', ',');
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static _StatusInfo _status(String status) {
    switch (status) {
      case 'CHO_LAY_HANG':
        return const _StatusInfo('Chờ lấy hàng', Colors.orange);
      case 'DA_LAY_HANG':
      case 'DANG_VAN_CHUYEN':
      case 'GIAO_CHO_SHIPPER':
      case 'DANG_GIAO_HANG':
        return const _StatusInfo('Đang giao', Colors.blue);
      case 'DA_GIAO_HANG':
        return const _StatusInfo('Đã giao', AppColors.success);
      case 'DA_HUY':
        return const _StatusInfo('Đã hủy', AppColors.error);
      default:
        return _StatusInfo(status.replaceAll('_', ' '), Colors.grey);
    }
  }
}

class _StatusInfo {
  const _StatusInfo(this.label, this.color);
  final String label;
  final Color color;
}
