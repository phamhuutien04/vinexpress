import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/customer/customer_home_screen.dart';
import 'screens/employee/delivery_home_screen.dart';
import 'screens/transport/transport_driver_home_screen.dart';
import 'screens/warehouse/warehouse_manager_home_screen.dart';
import 'screens/employee/employee_home_screen.dart';
import 'screens/employee/last_mile_staff_screen.dart';
import 'services/customer_auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'VinExpress',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const _SessionGate(),
    );
  }
}

class _SessionGate extends StatefulWidget {
  const _SessionGate();

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  late final Future<LoginResult?> _session = CustomerAuthService()
      .restoreSession();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LoginResult?>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final result = snapshot.data;
        if (result == null) return const LoginScreen();
        if (result.type == AccountType.customer) {
          return const CustomerHomeScreen();
        }
        final role = result.profile['vai_tro'] as String?;
        if (role == 'ADMIN') return const AdminHomeScreen();
        if (role == 'SHIPPER') return const DeliveryHomeScreen();
        if (role == 'NHAN_VIEN_LAY_HANG' || role == 'NHAN_VIEN_GIAO_HANG') {
          return const LastMileStaffScreen();
        }
        if (role == 'VAN_CHUYEN') return const TransportDriverHomeScreen();
        if (role == 'QUAN_LY_KHO') return const WarehouseManagerHomeScreen();
        return const EmployeeHomeScreen();
      },
    );
  }
}
