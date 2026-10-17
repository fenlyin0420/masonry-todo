import 'package:flutter/material.dart';

/// 左右两列、彼此不对齐的瀑布流：按预估高度把条目丢进当前更矮的一列。
class MasonryTwoColumn<T> extends StatelessWidget {
  const MasonryTwoColumn({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.heightEstimator,
    this.spacing = 12,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final double Function(T item) heightEstimator;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final List<T> left = <T>[];
    final List<T> right = <T>[];
    var leftHeight = 0.0;
    var rightHeight = 0.0;
    for (final T item in items) {
      final double height = heightEstimator(item);
      if (leftHeight <= rightHeight) {
        left.add(item);
        leftHeight += height + spacing;
      } else {
        right.add(item);
        rightHeight += height + spacing;
      }
    }

    Widget column(List<T> columnItems) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final T item in columnItems)
            Padding(
              padding: EdgeInsets.only(bottom: spacing),
              child: itemBuilder(context, item),
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: column(left)),
        SizedBox(width: spacing),
        Expanded(child: column(right)),
      ],
    );
  }
}
