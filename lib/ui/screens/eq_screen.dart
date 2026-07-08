import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/eq_preset.dart';
import '../../audio/eq_service.dart';
import '../../audio/eq_state.dart';
import '../../data/db/viby_database.dart' show EqPresetRow;
import '../../state/eq_providers.dart';
import '../../state/haptics_providers.dart';
import '../eq/eq_curve.dart';
import '../eq/eq_curve_painter.dart';
import '../theme/tokens.dart';

/// The Equalizer — a flagship Pro screen. Master switch, preset chips, a live
/// frequency-response curve, per-band vertical sliders (0 dB detent, real-time),
/// and a separated loudness enhancer. All audio changes apply as you drag.
class EqScreen extends ConsumerStatefulWidget {
  const EqScreen({super.key});

  @override
  ConsumerState<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends ConsumerState<EqScreen> {
  /// Live gains during a drag, for instant feedback ahead of the stream. Cleared
  /// (falls back to provider state) after a preset apply or a band-layout change.
  List<double>? _editGains;

  EqService get _service => ref.read(eqServiceProvider);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<EqRuntimeState> async = ref.watch(eqStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Equalizer')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) =>
            Center(child: Text('Equalizer unavailable\n$e')),
        data: (EqRuntimeState st) =>
            st.capable ? _buildBody(context, st) : const _UnsupportedBody(),
      ),
    );
  }

  Widget _buildBody(BuildContext context, EqRuntimeState st) {
    // Reconcile local edit gains with the live band layout.
    List<double> gains = _editGains ?? st.gains;
    if (gains.length != st.gains.length) gains = st.gains;

    final List<EqPresetRow> customRows =
        ref.watch(customEqPresetsProvider).valueOrNull ?? const <EqPresetRow>[];

    return ListView(
      padding: const EdgeInsets.only(bottom: Spacing.xxl),
      children: <Widget>[
        _MasterSwitch(
          enabled: st.enabled,
          onChanged: (bool on) {
            ref.read(hapticsServiceProvider).selection();
            _service.setEnabled(on);
          },
        ),
        const SizedBox(height: Spacing.sm),
        _PresetChips(
          state: st,
          customRows: customRows,
          onApply: (EqPreset p) {
            ref.read(hapticsServiceProvider).light();
            setState(() => _editGains = null);
            _service.applyPreset(p);
          },
          onRename: _renamePreset,
          onDelete: (String id) => _service.deletePreset(id),
        ),
        _PresetStatusRow(
          state: st,
          customRows: customRows,
          onSave: _saveCustomPreset,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.lg, Spacing.sm, Spacing.lg, 0),
          child: _CurveCard(gains: gains, state: st),
        ),
        _BandSliders(
          state: st,
          gains: gains,
          onChanged: (int i, double v) {
            final double snapped = snapToDetent(v);
            setState(() {
              final List<double> next = List<double>.of(gains);
              next[i] = snapped;
              _editGains = next;
            });
            _service.setBandGain(i, snapped);
          },
        ),
        const Divider(height: Spacing.xl),
        _LoudnessCard(
          value: st.loudnessGain,
          onChanged: (double v) => _service.setLoudnessTargetGain(v),
        ),
      ],
    );
  }

  Future<void> _saveCustomPreset() async {
    final String? name = await _promptName(context, title: 'Save preset');
    if (name == null || name.trim().isEmpty) return;
    ref.read(hapticsServiceProvider).light();
    await _service.saveCustomPreset(name.trim());
    setState(() => _editGains = null);
  }

  Future<void> _renamePreset(EqPresetRow row) async {
    final String? name =
        await _promptName(context, title: 'Rename preset', initial: row.name);
    if (name == null || name.trim().isEmpty) return;
    await _service.renamePreset(row.id, name.trim());
  }

  Future<String?> _promptName(
    BuildContext context, {
    required String title,
    String initial = '',
  }) {
    final TextEditingController controller =
        TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Preset name'),
          onSubmitted: (String v) => Navigator.pop(c, v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// The large, obvious master switch.
class _MasterSwitch extends StatelessWidget {
  const _MasterSwitch({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
      child: Material(
        color: enabled
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: Radii.brLg,
        child: SwitchListTile(
          shape: const RoundedRectangleBorder(borderRadius: Radii.brLg),
          secondary: Icon(
            Icons.graphic_eq,
            color: enabled ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          ),
          title: Text(
            'Equalizer',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: enabled
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                ),
          ),
          subtitle: Text(
            enabled ? 'On' : 'Off',
            style: TextStyle(
              color: enabled ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            ),
          ),
          value: enabled,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Horizontally-scrolling preset chips: built-ins + custom (long-press custom
/// for rename/delete). The active preset is filled.
class _PresetChips extends StatelessWidget {
  const _PresetChips({
    required this.state,
    required this.customRows,
    required this.onApply,
    required this.onRename,
    required this.onDelete,
  });

  final EqRuntimeState state;
  final List<EqPresetRow> customRows;
  final ValueChanged<EqPreset> onApply;
  final ValueChanged<EqPresetRow> onRename;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        children: <Widget>[
          for (final EqPreset p in kBuiltInPresets)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: ChoiceChip(
                label: Text(p.name),
                selected: state.activePresetId == p.id && !state.modified,
                onSelected: (_) => onApply(p),
              ),
            ),
          for (final EqPresetRow row in customRows)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: GestureDetector(
                onLongPress: () => _showCustomMenu(context, row),
                child: ChoiceChip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text(row.name),
                  selected: state.activePresetId == row.id && !state.modified,
                  onSelected: (_) => onApply(
                    EqPreset.fromGainMap(
                      id: row.id,
                      name: row.name,
                      gains: decodeGainMap(row.gainsJson),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCustomMenu(BuildContext context, EqPresetRow row) {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(c);
                onRename(row);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(c);
                onDelete(row.id);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Custom (based on Rock)" status line + a Save affordance when modified.
class _PresetStatusRow extends StatelessWidget {
  const _PresetStatusRow({
    required this.state,
    required this.customRows,
    required this.onSave,
  });

  final EqRuntimeState state;
  final List<EqPresetRow> customRows;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String label = eqStatusLabel(
      activePresetId: state.activePresetId,
      activePresetName: _activeName(),
      modified: state.modified,
    );
    final bool showSave = state.modified || state.activePresetId == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.lg, Spacing.xs, Spacing.sm, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (showSave)
            TextButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Save preset'),
            ),
        ],
      ),
    );
  }

  String? _activeName() {
    final String? id = state.activePresetId;
    if (id == null) return null;
    final EqPreset? builtIn = builtInPresetById(id);
    if (builtIn != null) return builtIn.name;
    for (final EqPresetRow r in customRows) {
      if (r.id == id) return r.name;
    }
    return null;
  }
}

/// The frequency-response curve card.
class _CurveCard extends StatelessWidget {
  const _CurveCard({required this.gains, required this.state});

  final List<double> gains;
  final EqRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.brLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: EqCurvePainter(
          gains: gains,
          minDb: state.minDb,
          maxDb: state.maxDb,
          primary: scheme.primary,
          gridColor: scheme.outlineVariant.withValues(alpha: 0.5),
          enabled: state.enabled,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The row of per-band vertical sliders (0 dB center detent, real-time).
class _BandSliders extends StatelessWidget {
  const _BandSliders({
    required this.state,
    required this.gains,
    required this.onChanged,
  });

  final EqRuntimeState state;
  final List<double> gains;
  final void Function(int index, double gain) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Spacing.sm, Spacing.md, Spacing.sm, 0),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int n = state.bands.length;
          if (n == 0) return const SizedBox.shrink();
          const double minBandWidth = 46;
          final bool scroll = constraints.maxWidth / n < minBandWidth;
          final List<Widget> bands = <Widget>[
            for (int i = 0; i < n; i++)
              _BandSlider(
                width: scroll ? minBandWidth : constraints.maxWidth / n,
                band: state.bands[i],
                gain: i < gains.length ? gains[i] : 0,
                minDb: state.minDb,
                maxDb: state.maxDb,
                enabled: state.enabled,
                onChanged: (double v) => onChanged(i, v),
              ),
          ];
          if (scroll) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: bands),
            );
          }
          return Row(
            children: <Widget>[for (final Widget b in bands) Expanded(child: b)],
          );
        },
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.width,
    required this.band,
    required this.gain,
    required this.minDb,
    required this.maxDb,
    required this.enabled,
    required this.onChanged,
  });

  final double width;
  final EqBandState band;
  final double gain;
  final double minDb;
  final double maxDb;
  final bool enabled;
  final ValueChanged<double> onChanged;

  static const double _trackLength = 170;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _fmtGain(gain),
            style: theme.textTheme.labelSmall?.copyWith(
              color: enabled ? scheme.primary : scheme.onSurfaceVariant,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: Spacing.xs),
          SizedBox(
            height: _trackLength,
            child: RotatedBox(
              quarterTurns: 3,
              child: SizedBox(
                width: _trackLength,
                child: Slider(
                  min: minDb,
                  max: maxDb,
                  value: gain.clamp(minDb, maxDb),
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            formatFrequency(band.centerFrequency),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _fmtGain(double db) {
    final int r = db.round();
    if (r == 0) return '0';
    return r > 0 ? '+$r' : '$r';
  }
}

/// The loudness enhancer: a single horizontal slider, clearly separated, with a
/// caption explaining what it does.
class _LoudnessCard extends StatelessWidget {
  const _LoudnessCard({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const double _maxDb = 12;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.volume_up_outlined),
              const SizedBox(width: Spacing.md),
              Text('Loudness', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                '+${value.round()} dB',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          Slider(
            min: 0,
            max: _maxDb,
            value: value.clamp(0, _maxDb),
            onChanged: onChanged,
          ),
          Padding(
            padding: const EdgeInsets.only(left: Spacing.xs, bottom: Spacing.sm),
            child: Text(
              'Boosts overall volume for quiet tracks. Use sparingly — high '
              'settings can distort.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the platform has no equalizer (e.g. iOS today).
class _UnsupportedBody extends StatelessWidget {
  const _UnsupportedBody();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.graphic_eq,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: Spacing.lg),
            Text(
              'Equalizer not available on this device',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'The system equalizer is only available on Android.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
