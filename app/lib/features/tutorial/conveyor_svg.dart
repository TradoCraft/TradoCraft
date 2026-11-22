import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Builds a clean schematic SVG of a conveyor belt assembly, optionally with a mounted
/// 1-phase or 3-phase (+ VFD) motor.
String buildConveyorAssemblySvg({
  required bool withMotor,
  bool threePhase = true,
}) {
  final motorGroup = !withMotor
      ? ''
      : threePhase
      ? '''
  <g id="motor-3p">
    <rect x="238" y="88" width="54" height="34" rx="4" fill="#1e88e5" stroke="#0d47a1" stroke-width="2"/>
    <line x1="246" y1="94" x2="246" y2="116" stroke="#bbdefb" stroke-width="2"/>
    <line x1="254" y1="94" x2="254" y2="116" stroke="#bbdefb" stroke-width="2"/>
    <line x1="262" y1="94" x2="262" y2="116" stroke="#bbdefb" stroke-width="2"/>
    <rect x="292" y="99" width="12" height="12" fill="#546e7a" stroke="#263238" stroke-width="1.5"/>
    <rect x="308" y="82" width="38" height="44" rx="3" fill="#43a047" stroke="#1b5e20" stroke-width="2"/>
    <text x="327" y="108" font-family="sans-serif" font-size="10" font-weight="bold" fill="#ffffff" text-anchor="middle">VFD</text>
    <text x="265" y="136" font-family="sans-serif" font-size="10" fill="#0d47a1" text-anchor="middle">MOT-3P-055</text>
  </g>'''
      : '''
  <g id="motor-1p">
    <rect x="242" y="90" width="48" height="30" rx="4" fill="#fb8c00" stroke="#e65100" stroke-width="2"/>
    <rect x="290" y="99" width="12" height="12" fill="#546e7a" stroke="#263238" stroke-width="1.5"/>
    <text x="266" y="136" font-family="sans-serif" font-size="10" fill="#e65100" text-anchor="middle">MOT-1P-037</text>
  </g>''';

  final subtitle = withMotor
      ? (threePhase ? 'CONV-BELT-1M + MOT-3P-055 + VFD' : 'CONV-BELT-1M + MOT-1P-037')
      : 'CONV-BELT-1M (without motor)';

  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 150">
  <rect x="2" y="2" width="376" height="146" rx="8" fill="#f8fafc" stroke="#cbd5e1" stroke-width="1.5"/>
  <text x="16" y="22" font-family="sans-serif" font-size="11" font-weight="bold" fill="#334155">$subtitle</text>
  <!-- Conveyor frame & belt -->
  <rect x="28" y="48" width="210" height="24" rx="12" fill="#475569" stroke="#1e293b" stroke-width="2"/>
  <rect x="40" y="53" width="186" height="14" rx="7" fill="#94a3b8"/>
  <circle cx="42" cy="60" r="8" fill="#e2e8f0" stroke="#1e293b" stroke-width="2"/>
  <circle cx="224" cy="60" r="8" fill="#e2e8f0" stroke="#1e293b" stroke-width="2"/>
  <!-- Support legs -->
  <line x1="56" y1="72" x2="56" y2="122" stroke="#64748b" stroke-width="4"/>
  <line x1="208" y1="72" x2="208" y2="122" stroke="#64748b" stroke-width="4"/>
  <line x1="44" y1="122" x2="68" y2="122" stroke="#475569" stroke-width="3"/>
  <line x1="196" y1="122" x2="220" y2="122" stroke="#475569" stroke-width="3"/>
  $motorGroup
</svg>
''';
}

/// Returns UTF-8 bytes of the conveyor assembly SVG for uploading as `image/svg+xml` Product Media.
Uint8List conveyorAssemblySvgBytes({
  required bool withMotor,
  bool threePhase = true,
}) => Uint8List.fromList(
  utf8.encode(buildConveyorAssemblySvg(withMotor: withMotor, threePhase: threePhase)),
);

/// Interactive SVG preview of a conveyor belt assembly (with or without motor).
class ConveyorAssemblySvg extends StatefulWidget {
  /// Creates the preview widget.
  const ConveyorAssemblySvg({super.key, this.initialWithMotor = true});

  /// Whether the motor is initially shown.
  final bool initialWithMotor;

  @override
  State<ConveyorAssemblySvg> createState() => _ConveyorAssemblySvgState();
}

class _ConveyorAssemblySvgState extends State<ConveyorAssemblySvg> {
  late bool _withMotor = widget.initialWithMotor;
  bool _threePhase = true;

  @override
  Widget build(BuildContext context) {
    final svg = buildConveyorAssemblySvg(
      withMotor: _withMotor,
      threePhase: _threePhase,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 132,
          child: SvgPicture.string(svg, fit: BoxFit.contain),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            FilterChip(
              label: const Text('With motor'),
              selected: _withMotor,
              onSelected: (v) => setState(() => _withMotor = v),
            ),
            if (_withMotor)
              ChoiceChip(
                label: Text(_threePhase ? '3-Phase + VFD' : '1-Phase'),
                selected: true,
                onSelected: (_) => setState(() => _threePhase = !_threePhase),
              ),
          ],
        ),
      ],
    );
  }
}
