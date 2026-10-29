import 'package:flutter_test/flutter_test.dart';
import 'package:glemtdet/domain/models/observation.dart';
import 'package:glemtdet/vision/sampling/observation_debouncer.dart';

ObservationDraft draft({
  String object = 'airpods',
  String? place = 'desk',
  double confidence = 0.8,
  required DateTime at,
}) =>
    ObservationDraft(
      objectKey: object,
      objectLabel: 'AirPods',
      confidence: confidence,
      seenAt: at,
      placeKey: place,
      placeLabel: place,
    );

void main() {
  final t0 = DateTime(2026, 9, 4, 18, 42);

  test('første observation gemmes', () {
    final debouncer = ObservationDebouncer();
    expect(debouncer.evaluate(draft(at: t0)).action, DebounceAction.store);
  });

  test('samme ting samme sted få sekunder senere bliver ikke en ny række', () {
    final debouncer = ObservationDebouncer();
    debouncer.commit(draft(at: t0), 1);

    final verdict = debouncer.evaluate(draft(at: t0.add(const Duration(seconds: 4))));
    expect(verdict.action, DebounceAction.refresh);
    expect(verdict.previousId, 1);
  });

  test('en flytning gemmes altid', () {
    final debouncer = ObservationDebouncer();
    debouncer.commit(draft(at: t0), 1);

    final verdict = debouncer.evaluate(
      draft(place: 'sofa', at: t0.add(const Duration(seconds: 4))),
    );
    expect(verdict.action, DebounceAction.store);
  });

  test('efter afkølingsperioden gemmes en ny observation', () {
    final debouncer = ObservationDebouncer(cooldown: const Duration(seconds: 90));
    debouncer.commit(draft(at: t0), 1);

    expect(
      debouncer.evaluate(draft(at: t0.add(const Duration(seconds: 91)))).action,
      DebounceAction.store,
    );
  });

  test('seeding fra databasen forhindrer dubletter efter genstart', () {
    final debouncer = ObservationDebouncer();
    debouncer.seed([
      Observation(
        id: 42,
        objectKey: 'airpods',
        objectLabel: 'AirPods',
        confidence: 0.9,
        seenAt: t0,
        placeKey: 'desk',
        placeLabel: 'Skrivebord',
      ),
    ]);

    final verdict = debouncer.evaluate(draft(at: t0.add(const Duration(seconds: 10))));
    expect(verdict.action, DebounceAction.refresh);
    expect(verdict.previousId, 42);
  });

  test('et helt scanningsforløb giver få rækker, ikke hundredvis', () {
    // 20 minutes of a phone sitting on a desk, analysed every 8 seconds.
    final debouncer = ObservationDebouncer();
    var stored = 0;
    var t = t0;
    for (var i = 0; i < 150; i++) {
      final d = draft(object: 'phone', at: t);
      final verdict = debouncer.evaluate(d);
      if (verdict.action == DebounceAction.store) stored++;
      debouncer.commit(d, stored);
      t = t.add(const Duration(seconds: 8));
    }
    expect(stored, 1);
  });
}
