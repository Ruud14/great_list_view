import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:great_list_view/great_list_view.dart';

// Drives an AutomaticAnimatedListView the way a realtime feed does: items are
// voted up and down (moves), arrive (inserts), leave (removes) and change
// content, often while the previous changes are still animating.

const int seedCount = int.fromEnvironment('FUZZ_SEEDS', defaultValue: 60);
const int stepsPerSeed = int.fromEnvironment('FUZZ_STEPS', defaultValue: 150);
const int firstSeed = int.fromEnvironment('FUZZ_FIRST_SEED', defaultValue: 0);

class Item {
  Item(this.id, this.votes, this.hasMessage, this.extra);

  Item.from(Item other)
      : id = other.id,
        votes = other.votes,
        hasMessage = other.hasMessage,
        extra = other.extra;

  final int id;
  int votes;
  bool hasMessage;

  /// How much taller the real card is than the size the measuring pass assumes.
  final double extra;

  @override
  String toString() => '#$id($votes${hasMessage ? 'm' : ''})';
}

final Item sentinel = Item(-1, 0, false, 0);

class FeedHarness extends StatefulWidget {
  const FeedHarness({Key? key, required this.initial, required this.controller})
      : super(key: key);

  final List<Item> initial;
  final AnimatedListController controller;

  @override
  FeedHarnessState createState() => FeedHarnessState();
}

class FeedHarnessState extends State<FeedHarness> {
  final ScrollController scrollController = ScrollController();
  late List<Item> items = sorted(widget.initial);

  static List<Item> sorted(List<Item> l) => List.of(l)
    ..sort((a, b) =>
        a.votes != b.votes ? b.votes.compareTo(a.votes) : a.id.compareTo(b.id));

  // Same as the app: a new list, comparator and builder on every build.
  List<Item> get list => items + [sentinel];

  void apply(List<Item> next) => setState(() => items = sorted(next));

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: AutomaticAnimatedListView<Item>(
            scrollController: scrollController,
            clipBehavior: Clip.antiAlias,
            physics: const AlwaysScrollableScrollPhysics()
                .applyTo(const BouncingScrollPhysics()),
            shrinkWrap: true,
            padding: const EdgeInsets.only(top: 8, left: 8, right: 12),
            list: list,
            comparator: AnimatedListDiffListComparator<Item>(
              sameItem: (a, b) => a.id == b.id,
              sameContent: (a, b) =>
                  a.votes == b.votes && a.hasMessage == b.hasMessage,
            ),
            itemBuilder: (context, item, data) {
              if (identical(item, sentinel)) return const SizedBox(height: 160);
              final height = item.hasMessage ? 110.0 : 80.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: data.measuring
                    ? SizedBox(height: height)
                    : SizedBox(
                        height: height + item.extra,
                        child: Text(item.toString()),
                      ),
              );
            },
            listController: widget.controller,
            addFadeTransition: false,
            detectMoves: true,
          ),
        ),
      ),
    );
  }
}

Item newItem(math.Random r, int id) =>
    Item(id, r.nextInt(12), r.nextInt(4) == 0, (r.nextInt(5) - 1) * 10.0);

/// One realtime-style change to the column.
List<Item> mutate(math.Random r, List<Item> current, int Function() nextId,
    List<Item> removed, List<String> log) {
  final next = current.map((e) => Item.from(e)).toList();
  final ops = 1 + r.nextInt(r.nextInt(10) == 0 ? 6 : 2);
  for (var i = 0; i < ops; i++) {
    final roll = r.nextInt(100);
    if (roll < 40 && next.isNotEmpty) {
      final item = next[r.nextInt(next.length)];
      final delta = r.nextBool() ? 1 + r.nextInt(3) : -(1 + r.nextInt(3));
      item.votes += delta;
      log.add('vote ${item.id} $delta');
    } else if (roll < 45) {
      // A re-sort that moves many items at once.
      for (final item in next) {
        if (r.nextInt(3) == 0) item.votes += r.nextInt(7) - 3;
      }
      log.add('rerank');
    } else if (roll < 60) {
      final item = newItem(r, nextId());
      next.add(item);
      log.add('insert $item');
    } else if (roll < 65 && removed.isNotEmpty) {
      // A request that left the column comes back, with the same id.
      final item = removed.removeAt(r.nextInt(removed.length));
      if (!next.any((e) => e.id == item.id)) {
        next.add(item);
        log.add('return $item');
      }
    } else if (roll < 88 && next.isNotEmpty) {
      final item = next.removeAt(r.nextInt(next.length));
      removed.add(item);
      log.add('remove ${item.id}');
    } else if (next.isNotEmpty) {
      final item = next[r.nextInt(next.length)];
      item.hasMessage = !item.hasMessage;
      log.add('message ${item.id}');
    }
  }
  return next;
}

/// Runs [steps] realtime-style changes on a fresh list, failing as soon as the list view
/// throws or stops tracking as many items as the list holds.
Future<void> churn(WidgetTester tester, int seed, int steps,
    List<FlutterErrorDetails> errors, List<String> log) async {
  final r = math.Random(seed);
  var id = 0;
  int nextId() => id++;
  final initial =
      List.generate(20 + r.nextInt(60), (_) => newItem(r, nextId()));
  final removed = <Item>[];
  final controller = AnimatedListController();
  final key = GlobalKey<FeedHarnessState>();
  log.add('seed $seed, ${initial.length} items');

  await tester.pumpWidget(
      FeedHarness(key: key, initial: initial, controller: controller));

  void check(int step) {
    final exception = tester.takeException();
    final expected = key.currentState!.list.length;
    if (exception != null || controller.debugItemCount != expected) {
      fail('seed $seed step $step: tracked ${controller.debugItemCount} '
          'items, list has $expected, exception: $exception\n'
          '${errors.isEmpty ? '' : errors.first.stack}\n'
          '${log.join('\n')}');
    }
  }

  for (var step = 0; step < steps; step++) {
    final state = key.currentState!;
    final roll = r.nextInt(100);
    if (roll < 8) {
      final position = state.scrollController.position;
      final offset = r.nextInt(3) == 0
          ? position.maxScrollExtent
          : r.nextDouble() * position.maxScrollExtent;
      state.scrollController.jumpTo(offset);
      log.add('scroll ${offset.round()}');
    } else if (roll < 12) {
      final dy = (r.nextDouble() - 0.5) * 1600;
      await tester.fling(
          find.byType(Scrollable), Offset(0, dy), 1000 + r.nextDouble() * 2000);
      log.add('fling ${dy.round()}');
    } else {
      state.apply(mutate(r, state.items, nextId, removed, log));
    }

    // Frame by frame, as a device would, so changes land at every point of an animation.
    final frames = r.nextInt(4) == 0 ? 1 : 1 + r.nextInt(40);
    log.add('frames $frames');
    for (var f = 0; f < frames; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      check(step);
    }
  }
}

/// Collects every reported error, so a failure can show the stack of the first one.
List<FlutterErrorDetails> collectErrors() {
  final errors = <FlutterErrorDetails>[];
  final reportError = FlutterError.onError;
  FlutterError.onError = (details) {
    errors.add(details);
    reportError?.call(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
  return errors;
}

void main() {
  testWidgets('item count stays in sync with the list under realtime churn',
      (tester) async {
    final errors = collectErrors();
    for (var seed = firstSeed; seed < firstSeed + seedCount; seed++) {
      final log = <String>[];
      await churn(tester, seed, stepsPerSeed, errors, log);
      // Let every animation finish, so removing the list is not what is tested here.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull, reason: log.join('\n'));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull, reason: log.join('\n'));
    }
  }, timeout: const Timeout(Duration(minutes: 120)));

  testWidgets('the list view can be removed while it is animating',
      (tester) async {
    final errors = collectErrors();
    for (var seed = firstSeed; seed < firstSeed + seedCount ~/ 3; seed++) {
      final log = <String>[];
      await churn(tester, seed, 1 + seed % 40, errors, log);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull, reason: log.join('\n'));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull, reason: log.join('\n'));
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
