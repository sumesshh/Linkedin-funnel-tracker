import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

final numberFormat = NumberFormat.decimalPattern('en_IN');
String fmt(num v) => numberFormat.format(v);

bool isMobile(BuildContext context) =>
    MediaQuery.sizeOf(context).width < Breakpoints.mobile;

/// White card, 12px radius, subtle border + shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color = AppColors.background,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: shadow
            ? const [
                BoxShadow(
                    color: AppColors.shadow, blurRadius: 2, offset: Offset(0, 1)),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class CardTitle extends StatelessWidget {
  const CardTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      text,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: Color(0xFF424242),
      ),
    );
    if (trailing == null) return title;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [title, trailing!],
    );
  }
}

/// Standard page: title + content capped at 1100px and centred.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.title,
    required this.children,
    this.action,
    this.bottomPadding = 32,
  });

  final String title;
  final List<Widget> children;
  final Widget? action;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final pad = isMobile(context) ? 16.0 : 32.0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, pad, pad, bottomPadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageTitle(title, action: action),
              const SizedBox(height: 24),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        ?action,
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.cardBorder),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Coloured dot + label, used by chart legends and tooltips.
class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style:
                const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }
}

void showSuccess(BuildContext context, String message) =>
    _snack(context, message, AppColors.success, Icons.check_circle_outline);

void showError(BuildContext context, String message) =>
    _snack(context, message, AppColors.error, Icons.error_outline);

void _snack(BuildContext context, String message, Color color, IconData icon) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: color,
      content: Row(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ]),
    ));
}

/// Runs [action], showing a red snackbar if it throws. Returns success.
Future<bool> guard(BuildContext context, Future<void> Function() action,
    {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) showSuccess(context, success);
    return true;
  } catch (e) {
    if (context.mounted) showError(context, 'Something went wrong: $e');
    return false;
  }
}

/// White modal with a single text field. Returns the trimmed value.
Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String actionLabel,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  void submit(BuildContext ctx) {
    if (formKey.currentState!.validate()) {
      Navigator.pop(ctx, controller.text.trim());
    }
  }

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Please enter a name' : null,
            onFieldSubmitted: (_) => submit(ctx),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => submit(ctx), child: Text(actionLabel)),
      ],
    ),
  );
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 360, child: Text(message)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Small pill badge (Active / Inactive).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    );
  }
}
