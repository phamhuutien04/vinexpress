import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../core/constants/app_colors.dart';

class AdministrativeAddressSelection {
  const AdministrativeAddressSelection({
    required this.address,
    required this.province,
    required this.ward,
  });

  final String address;
  final String province;
  final String ward;
}

class AddressInput extends StatefulWidget {
  const AddressInput({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.allowCurrentLocation = false,
    this.onCurrentLocationSelected,
    this.onAddressChanged,
    this.onAddressSelected,
    this.onAdministrativeAddressSelected,
    this.fixedProvince,
    this.includeSubArea = true,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool allowCurrentLocation;
  final void Function(double latitude, double longitude)?
  onCurrentLocationSelected;
  final VoidCallback? onAddressChanged;
  final VoidCallback? onAddressSelected;
  final ValueChanged<AdministrativeAddressSelection>?
  onAdministrativeAddressSelected;
  final String? fixedProvince;
  final bool includeSubArea;
  final String? Function(String?)? validator;

  @override
  State<AddressInput> createState() => _AddressInputState();
}

class _AddressInputState extends State<AddressInput> {
  bool _locating = false;
  bool _hasAdministrativeSelection = false;

  Future<void> _showLocationPermissionHelp({
    required bool permanentlyDenied,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cần quyền truy cập vị trí'),
        content: Text(
          kIsWeb
              ? 'Quyền vị trí chưa được trình duyệt xác nhận hoặc vừa bị từ chối. Hãy chọn Cho phép, bấm Xong (Done), đóng hộp thoại này rồi thử lại. Nếu vẫn lỗi, tải lại trang.'
              : permanentlyDenied
              ? 'Quyền vị trí đã bị từ chối vĩnh viễn. Hãy mở Cài đặt, chọn Quyền và bật Vị trí cho ứng dụng.'
              : 'Hãy chọn Cho phép khi điện thoại hỏi quyền vị trí rồi thử lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Đóng'),
          ),
          if (!kIsWeb && permanentlyDenied)
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await Geolocator.openAppSettings();
              },
              child: const Text('Mở cài đặt'),
            ),
        ],
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Vui lòng bật dịch vụ vị trí trên thiết bị.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        try {
          permission = await Geolocator.requestPermission();
        } on PermissionDeniedException {
          await _showLocationPermissionHelp(permanentlyDenied: false);
          return;
        }
      }
      if (permission == LocationPermission.denied) {
        await _showLocationPermissionHelp(permanentlyDenied: false);
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        await _showLocationPermissionHelp(permanentlyDenied: true);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 20),
        ),
      );

      // Lưu tọa độ GPS ngay, không phụ thuộc API đổi tọa độ thành tên đường.
      widget.onCurrentLocationSelected?.call(
        position.latitude,
        position.longitude,
      );

      final selectedAddress = _hasAdministrativeSelection
          ? widget.controller.text.trim()
          : '';
      final address = selectedAddress.isNotEmpty
          ? selectedAddress
          : await _reverseAddressFromPhoton(
                  position.latitude,
                  position.longitude,
                ) ??
                'Vị trí hiện tại (${position.latitude.toStringAsFixed(6)}, '
                    '${position.longitude.toStringAsFixed(6)})';
      widget.controller.text = address;
      widget.onAddressSelected?.call();
    } on PermissionDeniedException {
      await _showLocationPermissionHelp(permanentlyDenied: false);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<String?> _reverseAddressFromPhoton(
    double latitude,
    double longitude,
  ) async {
    try {
      final uri = Uri.https('photon.komoot.io', '/reverse', {
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'limit': '1',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['features'] is! List) return null;
      final features = decoded['features'] as List;
      if (features.isEmpty) return null;
      final feature = Map<String, dynamic>.from(features.first as Map);
      final properties = Map<String, dynamic>.from(
        feature['properties'] as Map? ?? const {},
      );
      final oldWard = _firstAddressValue(properties, const [
        'district',
        'locality',
        'city',
      ]);
      final oldProvince = _firstAddressValue(properties, const [
        'state',
        'city',
      ]);
      if (oldWard.isEmpty || oldProvince.isEmpty) return null;
      return await _mapLegacyWard(oldWard) ?? '$oldWard, $oldProvince';
    } catch (_) {
      return null;
    }
  }

  String _firstAddressValue(Map<String, dynamic> values, List<String> keys) {
    for (final key in keys) {
      final value = '${values[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<String?> _mapLegacyWard(String legacyName) async {
    try {
      final mappingUri = Uri.https(
        'provinces.open-api.vn',
        '/api/v2/w/from-legacy/',
        {'legacy_name': legacyName},
      );
      final mappingResponse = await http
          .get(mappingUri)
          .timeout(const Duration(seconds: 10));
      if (mappingResponse.statusCode != 200) return null;
      final mappings = jsonDecode(utf8.decode(mappingResponse.bodyBytes));
      if (mappings is! List || mappings.isEmpty) return null;
      final mapping = Map<String, dynamic>.from(mappings.first as Map);
      final wardValue = mapping['ward'];
      if (wardValue is! Map) return null;
      final ward = Map<String, dynamic>.from(wardValue);
      final wardName = '${ward['name'] ?? ''}'.trim();
      final provinceCode = ward['province_code'];
      if (wardName.isEmpty || provinceCode == null) return null;

      final provinceResponse = await http
          .get(Uri.parse('https://provinces.open-api.vn/api/v2/?depth=1'))
          .timeout(const Duration(seconds: 10));
      if (provinceResponse.statusCode != 200) return wardName;
      final provinces = jsonDecode(utf8.decode(provinceResponse.bodyBytes));
      if (provinces is! List) return wardName;
      for (final value in provinces) {
        final province = Map<String, dynamic>.from(value as Map);
        if ('${province['code']}' == '$provinceCode') {
          return '$wardName, ${province['name']}';
        }
      }
      return wardName;
    } catch (_) {
      return null;
    }
  }

  Future<void> _selectAddress() async {
    final selection =
        await showModalBottomSheet<AdministrativeAddressSelection>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _AdministrativeAddressPicker(
            fixedProvince: widget.fixedProvince,
            includeSubArea: widget.includeSubArea,
          ),
        );
    if (selection != null && selection.address.isNotEmpty) {
      _hasAdministrativeSelection = true;
      widget.controller.text = selection.address;
      widget.onAddressChanged?.call();
      widget.onAddressSelected?.call();
      widget.onAdministrativeAddressSelected?.call(selection);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          onChanged: (_) {
            _hasAdministrativeSelection = false;
            widget.onAddressChanged?.call();
          },
          maxLines: 2,
          validator: widget.validator,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.location_on_outlined),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _selectAddress,
              icon: const Icon(Icons.account_tree_outlined, size: 18),
              label: const Text('Chọn Tỉnh/Thành, Phường/Xã'),
            ),
            if (widget.allowCurrentLocation)
              OutlinedButton.icon(
                onPressed: _locating ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_rounded, size: 18),
                label: const Text('Vị trí hiện tại'),
              ),
          ],
        ),
      ],
    );
  }
}

class _AdministrativeAddressPicker extends StatefulWidget {
  const _AdministrativeAddressPicker({
    this.fixedProvince,
    required this.includeSubArea,
  });

  final String? fixedProvince;
  final bool includeSubArea;

  @override
  State<_AdministrativeAddressPicker> createState() =>
      _AdministrativeAddressPickerState();
}

class _AdministrativeAddressPickerState
    extends State<_AdministrativeAddressPicker> {
  static List<Map<String, dynamic>>? _cachedProvinces;
  final _street = TextEditingController();
  final _subArea = TextEditingController();
  List<Map<String, dynamic>> _provinces = [];
  Map<String, dynamic>? _province;
  Map<String, dynamic>? _ward;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAdministrativeData();
  }

  Future<void> _loadAdministrativeData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cached = _cachedProvinces;
      if (cached != null) {
        _setData(cached);
        return;
      }

      final response = await http
          .get(Uri.parse('https://provinces.open-api.vn/api/v2/?depth=2'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Máy chủ địa chỉ trả về lỗi ${response.statusCode}.');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      final provinces =
          decoded.map((item) => Map<String, dynamic>.from(item as Map)).toList()
            ..sort(
              (a, b) => (a['name'] as String).compareTo(b['name'] as String),
            );
      _cachedProvinces = provinces;
      _setData(provinces);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Không tải được danh sách địa chỉ toàn quốc.';
      });
    }
  }

  void _setData(List<Map<String, dynamic>> provinces) {
    if (!mounted) return;
    final fixedName = widget.fixedProvince?.trim().toLowerCase();
    final fixedProvince = fixedName == null || fixedName.isEmpty
        ? null
        : provinces.where((item) {
            final name = '${item['name']}'.trim().toLowerCase();
            return name == fixedName ||
                name.contains(fixedName) ||
                fixedName.contains(name);
          }).firstOrNull;
    setState(() {
      _provinces = provinces;
      _province = fixedProvince ?? (provinces.isEmpty ? null : provinces.first);
      _ward = _wards.isEmpty ? null : _wards.first;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _wards {
    final wards = _province?['wards'];
    if (wards is! List) return [];
    return wards.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<void> _pickProvince() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddressSearchSheet(
        title: 'Tìm Tỉnh/Thành phố',
        hint: 'Gõ tên tỉnh hoặc thành phố...',
        items: _provinces,
      ),
    );
    if (selected == null) return;
    setState(() {
      _province = selected;
      _ward = _wards.isEmpty ? null : _wards.first;
    });
  }

  Future<void> _pickWard() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddressSearchSheet(
        title: 'Tìm Phường/Xã/Đặc khu',
        hint: 'Gõ tên phường, xã hoặc đặc khu...',
        items: _wards,
      ),
    );
    if (selected != null) setState(() => _ward = selected);
  }

  @override
  void dispose() {
    _street.dispose();
    _subArea.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.fixedProvince == null
                  ? 'Chọn địa chỉ toàn quốc'
                  : 'Chọn phường/xã tại ${widget.fixedProvince}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Dữ liệu hành chính 34 tỉnh/thành sau sáp nhập 07/2025',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Column(
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 42,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 10),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loadAdministrativeData,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Thử lại'),
                  ),
                ],
              )
            else ...[
              if (widget.fixedProvince == null) ...[
                _SearchSelectionField(
                  label: 'Tỉnh/Thành phố',
                  value: _province?['name'] as String?,
                  onTap: _pickProvince,
                ),
                const SizedBox(height: 12),
              ],
              _SearchSelectionField(
                label: 'Phường/Xã/Đặc khu',
                value: _ward?['name'] as String?,
                onTap: _pickWard,
              ),
              if (widget.includeSubArea) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _subArea,
                  decoration: InputDecoration(
                    labelText: _isCommune ? 'Ấp/thôn' : 'Khu phố',
                    hintText: _isCommune
                        ? 'Ví dụ: Ấp 1 hoặc Thôn Đông'
                        : 'Ví dụ: Khu phố 3',
                    prefixIcon: const Icon(Icons.map_outlined),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _street,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Số nhà, tên đường',
                  hintText: 'Ví dụ: 12 Nguyễn Huệ',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final street = _street.text.trim();
                  final subArea = _subArea.text.trim();
                  if (street.isEmpty ||
                      (widget.includeSubArea && subArea.isEmpty) ||
                      _province == null ||
                      _ward == null) {
                    return;
                  }
                  Navigator.pop(
                    context,
                    AdministrativeAddressSelection(
                      address: widget.includeSubArea
                          ? '$street, $subArea, ${_ward!['name']}, ${_province!['name']}'
                          : '$street, ${_ward!['name']}, ${_province!['name']}',
                      province: '${_province!['name']}',
                      ward: '${_ward!['name']}',
                    ),
                  );
                },
                child: const Text('Sử dụng địa chỉ này'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _isCommune {
    final name = '${_ward?['name'] ?? ''}'.toLowerCase();
    return name.startsWith('xã ');
  }
}

class _SearchSelectionField extends StatelessWidget {
  const _SearchSelectionField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          value ?? 'Chạm để tìm kiếm',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _AddressSearchSheet extends StatefulWidget {
  const _AddressSearchSheet({
    required this.title,
    required this.hint,
    required this.items,
  });

  final String title;
  final String hint;
  final List<Map<String, dynamic>> items;

  @override
  State<_AddressSearchSheet> createState() => _AddressSearchSheetState();
}

class _AddressSearchSheetState extends State<_AddressSearchSheet> {
  final _search = TextEditingController();
  late List<Map<String, dynamic>> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.items;
    _search.addListener(_filter);
  }

  void _filter() {
    final keyword = _search.text.trim().toLowerCase();
    setState(() {
      _filtered = keyword.isEmpty
          ? widget.items
          : widget.items.where((item) {
              final name = (item['name'] as String).toLowerCase();
              final codename = (item['codename'] as String? ?? '').replaceAll(
                '_',
                ' ',
              );
              return name.contains(keyword) || codename.contains(keyword);
            }).toList();
    });
  }

  @override
  void dispose() {
    _search
      ..removeListener(_filter)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_filtered.length} kết quả',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(child: Text('Không tìm thấy địa chỉ phù hợp'))
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final item = _filtered[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.location_on_outlined,
                            color: AppColors.primary,
                          ),
                          title: Text(item['name'] as String),
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
