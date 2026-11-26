import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Ob für die eingestellte Schriftgröße wenig Platz in der Breite ist, etwa
/// bei sehr großer Schrift oder vergrößerter Anzeige. Dann rücken Felder
/// untereinander statt nebeneinander, und Knöpfe in Kopfzeilen wandern ins
/// Menü, damit Texte nicht Buchstabe für Buchstabe umbrechen.
bool isCramped(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return MediaQuery.sizeOf(context).width / scale < 300;
}

/// Ein Text mit etwas Kurzem dahinter (Preis, Knopf): nebeneinander, solange
/// das längste Wort des Texts daneben noch Platz hat, sonst das Kurze
/// rechtsbündig darunter. So bricht ein Name mit großer Schrift nicht mitten
/// im Wort um, nur weil rechts daneben der Preis steht.
///
/// Nebeneinander stehen beide auf derselben Grundlinie, wenn [baseline]
/// gesetzt ist, sonst mittig.
class TrailingOrBelow extends MultiChildRenderObjectWidget {
  TrailingOrBelow({
    super.key,
    required Widget main,
    required Widget trailing,
    this.gap = 8,
    this.baseline = TextBaseline.alphabetic,
  }) : super(children: [main, trailing]);

  final double gap;
  final TextBaseline? baseline;

  @override
  RenderTrailingOrBelow createRenderObject(BuildContext context) =>
      RenderTrailingOrBelow(gap, baseline);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTrailingOrBelow renderObject,
  ) {
    renderObject
      ..gap = gap
      ..baseline = baseline;
  }
}

class _TrailingParentData extends ContainerBoxParentData<RenderBox> {}

class RenderTrailingOrBelow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TrailingParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TrailingParentData> {
  RenderTrailingOrBelow(this._gap, this._baseline);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  TextBaseline? _baseline;
  set baseline(TextBaseline? value) {
    if (value == _baseline) return;
    _baseline = value;
    markNeedsLayout();
  }

  RenderBox get _main => firstChild!;
  RenderBox get _trailing => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TrailingParentData) {
      child.parentData = _TrailingParentData();
    }
  }

  bool _fitsBeside(double width, double trailingWidth) =>
      width - trailingWidth - _gap >=
      _main.getMinIntrinsicWidth(double.infinity);

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _main.getMinIntrinsicWidth(height),
    _trailing.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _main.getMaxIntrinsicWidth(height) +
      _gap +
      _trailing.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _layoutFor(BoxConstraints(maxWidth: width), dry: true).size.height;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layoutFor(constraints, dry: true).size;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final (:size, :mainTop) = _layoutFor(constraints, dry: true);
    final width = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: width);
    final trailingWidth = _trailing.getDryLayout(loose).width;
    final beside = width.isFinite && _fitsBeside(width, trailingWidth);
    final mainWidth = beside ? width - trailingWidth - _gap : width;
    final base = _main.getDryBaseline(
      BoxConstraints.tightFor(width: mainWidth),
      baseline,
    );
    return base == null ? null : base + mainTop;
  }

  @override
  void performLayout() {
    size = _layoutFor(constraints, dry: false).size;
  }

  ({Size size, double mainTop}) _layoutFor(
    BoxConstraints constraints, {
    required bool dry,
  }) {
    final width = constraints.maxWidth;
    final loose = BoxConstraints(maxWidth: width);
    final trailingSize = dry
        ? _trailing.getDryLayout(loose)
        : (_trailing..layout(loose, parentUsesSize: true)).size;
    final beside = width.isFinite && _fitsBeside(width, trailingSize.width);
    final mainConstraints = BoxConstraints(
      minWidth: beside ? width - trailingSize.width - _gap : width,
      maxWidth: beside ? width - trailingSize.width - _gap : width,
    );
    final mainSize = dry
        ? _main.getDryLayout(mainConstraints)
        : (_main..layout(mainConstraints, parentUsesSize: true)).size;
    final Size result;
    var mainTop = 0.0;
    if (beside) {
      var trailingTop = 0.0;
      final b = _baseline;
      if (b != null) {
        final mainBase =
            (dry
                ? _main.getDryBaseline(mainConstraints, b)
                : _main.getDistanceToBaseline(b)) ??
            0;
        final trailingBase =
            (dry
                ? _trailing.getDryBaseline(loose, b)
                : _trailing.getDistanceToBaseline(b)) ??
            0;
        final base = math.max(mainBase, trailingBase);
        mainTop = base - mainBase;
        trailingTop = base - trailingBase;
      } else {
        final h = math.max(mainSize.height, trailingSize.height);
        mainTop = (h - mainSize.height) / 2;
        trailingTop = (h - trailingSize.height) / 2;
      }
      result = constraints.constrain(
        Size(
          width,
          math.max(
            mainTop + mainSize.height,
            trailingTop + trailingSize.height,
          ),
        ),
      );
      if (!dry) {
        (_main.parentData! as _TrailingParentData).offset = Offset(0, mainTop);
        (_trailing.parentData! as _TrailingParentData).offset = Offset(
          width - trailingSize.width,
          trailingTop,
        );
      }
    } else {
      result = constraints.constrain(
        Size(width, mainSize.height + trailingSize.height),
      );
      if (!dry) {
        (_main.parentData! as _TrailingParentData).offset = Offset.zero;
        (_trailing.parentData! as _TrailingParentData).offset = Offset(
          width - trailingSize.width,
          mainSize.height,
        );
      }
    }
    return (size: result, mainTop: mainTop);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Zwei Eingabefelder nebeneinander, bei wenig Platz ([isCramped])
/// untereinander, jeweils mit [gap] Abstand.
class FieldPair extends StatelessWidget {
  const FieldPair({
    super.key,
    required this.first,
    required this.second,
    this.gap = 12,
  });

  final Widget first;
  final Widget second;
  final double gap;

  @override
  Widget build(BuildContext context) => isCramped(context)
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            first,
            SizedBox(height: gap),
            second,
          ],
        )
      : Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            SizedBox(width: gap),
            Expanded(child: second),
          ],
        );
}
