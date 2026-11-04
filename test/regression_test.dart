import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:great_list_view/great_list_view.dart';

void main() {
  testWidgets('a moving group that lost its last item can be moved again',
      (tester) async {
    final items = List.generate(10, (i) => i);
    final controller = AnimatedListController();
    Widget item(int value) => SizedBox(height: 50, child: Text('$value'));

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedListView(
        listController: controller,
        initialItemCount: items.length,
        itemBuilder: (context, index, data) => item(items[index]),
      ),
    ));

    // Items 7 and 8 move up together.
    final group = [items.removeAt(7), items.removeAt(7)];
    items.insertAll(1, group);
    controller.notifyMovedRange(7, 2, 1);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    // While they are still moving, 8 leaves the list...
    final removed = items.removeAt(2);
    controller.notifyRemovedRange(
        2, 1, (context, index, data) => item(removed));
    await tester.pump(const Duration(milliseconds: 16));

    // ...and 7 moves again, which split the group past its last item.
    items.insert(5, items.removeAt(1));
    controller.notifyMovedRange(1, 1, 5);
    await tester.pump(const Duration(milliseconds: 16));

    expect(controller.debugItemCount, items.length);
    await tester.pumpAndSettle();
    expect(controller.debugItemCount, items.length);
    for (final value in items) {
      expect(find.text('$value'), findsOneWidget);
    }
  });

  group('AutomaticAnimatedListView', () {
    late AnimatedListController controller;
    late List<int> list;
    late StateSetter setList;

    Widget harness() => Directionality(
          textDirection: TextDirection.ltr,
          child: StatefulBuilder(builder: (context, setState) {
            setList = setState;
            return AutomaticAnimatedListView<int>(
              list: list,
              listController: controller,
              comparator: AnimatedListDiffListComparator<int>(
                  sameItem: (a, b) => a == b, sameContent: (a, b) => a == b),
              itemBuilder: (context, item, data) =>
                  SizedBox(height: 50, child: Text('$item')),
            );
          }),
        );

    setUp(() {
      controller = AnimatedListController();
      list = List.generate(5, (i) => i);
    });

    testWidgets('is rebuilt from its list when it asks for an item past the end',
        (tester) async {
      await tester.pumpWidget(harness());
      // The list view is told about an item the list does not have.
      controller.notifyInsertedRange(5, 1);
      await tester.pumpAndSettle();

      expect(tester.takeException().toString(),
          contains('asked for item 5 while the list holds 5'));
      expect(controller.debugItemCount, 5);
      for (final value in list) {
        expect(find.text('$value'), findsOneWidget);
      }
    });

    testWidgets('is rebuilt from its list when a new list leaves it out of sync',
        (tester) async {
      await tester.pumpWidget(harness());
      controller.notifyInsertedRange(0, 1);
      setList(() => list = List.generate(6, (i) => i));
      await tester.pump();

      expect(tester.takeException().toString(),
          contains('tracked 7 items while the list holds 6'));
      await tester.pumpAndSettle();
      expect(controller.debugItemCount, 6);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('takes a new controller together with a new list',
        (tester) async {
      await tester.pumpWidget(harness());
      final oldController = controller;
      setList(() {
        controller = AnimatedListController();
        list = [4, 3, 9];
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(oldController.debugItemCount, isNull);
      expect(controller.debugItemCount, 3);
      expect(find.text('9'), findsOneWidget);
    });
  });
}
