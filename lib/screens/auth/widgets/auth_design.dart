import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';

class AuthPageShell extends StatelessWidget {
  const AuthPageShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.form,
    this.showBackButton = false,
  });

  final String title;
  final String subtitle;
  final Widget form;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF123D39),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;
            if (isWide) {
              return Row(
                children: [
                  const Expanded(flex: 5, child: _AuthBrandPanel()),
                  Expanded(
                    flex: 6,
                    child: ColoredBox(
                      color: colors.surface,
                      child: _ScrollableForm(
                        maxWidth: 520,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 52,
                          vertical: 40,
                        ),
                        child: _FormContent(
                          title: title,
                          subtitle: subtitle,
                          showBackButton: showBackButton,
                          form: form,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return _MobileAuthLayout(
              title: title,
              subtitle: subtitle,
              form: form,
              showBackButton: showBackButton,
              availableHeight: constraints.maxHeight,
              compact: constraints.maxWidth < 360,
            );
          },
        ),
      ),
    );
  }
}

class _MobileAuthLayout extends StatelessWidget {
  const _MobileAuthLayout({
    required this.title,
    required this.subtitle,
    required this.form,
    required this.showBackButton,
    required this.availableHeight,
    required this.compact,
  });

  final String title;
  final String subtitle;
  final Widget form;
  final bool showBackButton;
  final double availableHeight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final horizontalPadding = compact ? 16.0 : 22.0;
    final headerHeight = showBackButton ? 232.0 : 218.0;
    final minimumFormHeight = availableHeight > headerHeight
        ? availableHeight - headerHeight
        : 0.0;

    return ColoredBox(
      color: const Color(0xFF123D39),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                30,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (showBackButton) ...[
                            IconButton(
                              tooltip: 'Quay lại',
                              onPressed: () => Navigator.maybePop(context),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.1,
                                ),
                                foregroundColor: const Color(0xFFF2FBF9),
                              ),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 12),
                          ],
                          const Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: AuthWordmark(onDark: true, compact: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: const Color(0xFFF2FBF9),
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              height: 1.15,
                            ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFB9D8D3),
                          height: 1.42,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              constraints: BoxConstraints(minHeight: minimumFormHeight),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                28,
                horizontalPadding,
                34,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: form,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollableForm extends StatelessWidget {
  const _ScrollableForm({
    required this.maxWidth,
    required this.padding,
    required this.child,
  });

  final double maxWidth;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: padding,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

class _FormContent extends StatelessWidget {
  const _FormContent({
    required this.title,
    required this.subtitle,
    required this.showBackButton,
    required this.form,
  });

  final String title;
  final String subtitle;
  final bool showBackButton;
  final Widget form;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showBackButton)
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton.filledTonal(
            tooltip: 'Quay lại',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
      if (showBackButton) const SizedBox(height: 24),
      _FormHeading(title: title, subtitle: subtitle),
      const SizedBox(height: 30),
      form,
    ],
  );
}

class _FormHeading extends StatelessWidget {
  const _FormHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _AuthBrandPanel extends StatelessWidget {
  const _AuthBrandPanel();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF123D39),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthWordmark(onDark: true),
          const Spacer(),
          const Text(
            'Giao hàng rõ ràng,\ntừng chặng an tâm.',
            style: TextStyle(
              color: Color(0xFFF2FBF9),
              fontSize: 38,
              height: 1.13,
              letterSpacing: -1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Tạo đơn, theo dõi hành trình và quản lý thanh toán trong một ứng dụng.',
            style: TextStyle(
              color: Color(0xFFB9D8D3),
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 34),
          const _BrandBenefit(
            icon: Icons.route_outlined,
            text: 'Theo dõi đơn hàng theo từng chặng',
          ),
          const SizedBox(height: 15),
          const _BrandBenefit(
            icon: Icons.verified_user_outlined,
            text: 'Minh chứng giao nhận rõ ràng',
          ),
          const SizedBox(height: 15),
          const _BrandBenefit(
            icon: Icons.account_balance_wallet_outlined,
            text: 'Thanh toán và đối soát thuận tiện',
          ),
          const Spacer(),
          const Text(
            'Giao nhanh, an tâm mọi hành trình',
            style: TextStyle(color: Color(0xFF89BDB6), fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _BrandBenefit extends StatelessWidget {
  const _BrandBenefit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: const Color(0xFF72D7CA), size: 21),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFFE0F1EE),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class AuthWordmark extends StatelessWidget {
  const AuthWordmark({super.key, this.onDark = false, this.compact = false});

  final bool onDark;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: compact ? 42 : 48,
        height: compact ? 42 : 48,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(compact ? 13 : 15),
        ),
        child: const Icon(
          Icons.local_shipping_rounded,
          color: Colors.white,
          size: 25,
        ),
      ),
      const SizedBox(width: 12),
      Text(
        'VinExpress',
        style: TextStyle(
          color: onDark
              ? const Color(0xFFF2FBF9)
              : Theme.of(context).colorScheme.onSurface,
          fontSize: compact ? 23 : 25,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
        ),
      ),
    ],
  );
}

class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.hint,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
    this.obscureText = false,
    this.suffixIcon,
    this.maxLines = 1,
    this.autofillHints,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final bool obscureText;
  final Widget? suffixIcon;
  final int maxLines;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fieldFill = dark
        ? colors.surfaceContainerHighest
        : const Color(0xFFF5F9F8);
    final fieldBorder = dark ? colors.outlineVariant : const Color(0xFFC6D8D4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          onFieldSubmitted: onFieldSubmitted,
          obscureText: obscureText,
          maxLines: obscureText ? 1 : maxLines,
          autofillHints: autofillHints,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: fieldFill,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 17,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.6,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.error, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon = Icons.arrow_forward_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFF082F2B),
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.3,
                color: Color(0xFF082F2B),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Icon(icon, size: 20),
              ],
            ),
    ),
  );
}

class AuthInfoStrip extends StatelessWidget {
  const AuthInfoStrip({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
