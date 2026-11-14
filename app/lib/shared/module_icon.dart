import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The artwork of a module or concept from `assets/icons/<name>.svg` (the metallic icon set).
/// The SVGs carry their own colours, so they are not tinted.
class ModuleIcon extends StatelessWidget {
  /// Shows `assets/icons/[name].svg` at [size] logical pixels.
  const ModuleIcon(this.name, {super.key, this.size = 28});

  /// File name without folder and extension, e.g. `quotations`.
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/$name.svg',
    width: size,
    height: size,
    semanticsLabel: name,
  );
}
