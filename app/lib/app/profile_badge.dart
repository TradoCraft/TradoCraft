import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';

/// A coloured label with the profile name and the roles of the signed-in user, so that windows of
/// different profiles (admin, sales, ...) are told apart at a glance. The colour comes from the
/// name, so a profile always looks the same.
class ProfileBadge extends StatelessWidget {
  const ProfileBadge({super.key, required this.profile, this.roles = const []});

  final String profile;
  final List<String> roles;

  static Color colorFor(String name) {
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.55, 0.30).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(profile);
    final roleText = roles.join(', ');
    return Tooltip(
      message: roleText.isEmpty
          ? context.l10n.profileTooltip(profile)
          : '${context.l10n.profileTooltip(profile)}\n$roleText',
      child: Container(
        key: const ValueKey('profile-badge'),
        constraints: const BoxConstraints(maxWidth: 96),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              profile,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            if (roleText.isNotEmpty)
              Text(
                roleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }
}
