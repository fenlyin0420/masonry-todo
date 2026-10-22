import 'package:flutter/material.dart';

/// 左右两列的瀑布流，按条目顺序左一格、右一格地交替摆放：
/// 阅读顺序是行优先（先左后右，再下一行），和列表的顺序完全一致，
/// 于是优先级排出来的顺序在两种展示形态下看到的是同一个。
/// 两列各自往下堆，卡片高度不同，所以行不必对齐。
class MasonryTwoColumn<T> extends StatelessWidget {
  const MasonryTwoColumn({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.spacing = 12,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final List<T> left = <T>[];
    final List<T> right = <T>[];
    for (int i = 0; i < items.length; i++) {
      (i.isEven ? left : right).add(items[i]);
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
