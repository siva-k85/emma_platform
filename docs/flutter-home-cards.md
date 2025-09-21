# EMMA Home Card Flow (Production Schema)

This guide translates the high-level product spec into concrete Firestore queries and Flutter patterns for the rebooted EMMA app. It assumes the schedule backfill has run so every document uses snake_case fields (`scheduled_date`, `evaluation_data.attendee_evaluation`, etc.).

---

## 1. Role Detection

```dart
final user = FirebaseAuth.instance.currentUser!;
final userDoc = await FirebaseFirestore.instance
    .collection('users')
    .doc(user.uid)
    .get();
final userData = userDoc.data()!;
final role = userData['role'] as String; // 'physician' | 'resident' | 'admin'
```

Admins will see their dashboard; only physicians and residents render the evaluation cards.

---

## 2. Query Construction

We query the `schedules` collection using the new snake_case fields populated by the matcher and backfill.

```dart
Query<Map<String, dynamic>> buildScheduleQuery({
  required String role,
  required String uid,
  required DateTime day,
}) {
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
  final collection = FirebaseFirestore.instance.collection('schedules');
  final startTs = Timestamp.fromDate(start);
  final endTs = Timestamp.fromDate(end);

  if (role == 'physician') {
    return collection
        .where('attendee_ref', isEqualTo: '/users/$uid')
        .where('scheduled_date', isGreaterThanOrEqualTo: startTs)
        .where('scheduled_date', isLessThanOrEqualTo: endTs)
        .where('evaluation_data.attendee_evaluation.status.status', whereIn: ['evaluate', 'pending', 'draft'])
        .orderBy('scheduled_date');
  }

  return collection
      .where('resident_ref', isEqualTo: '/users/$uid')
      .where('scheduled_date', isGreaterThanOrEqualTo: startTs)
      .where('scheduled_date', isLessThanOrEqualTo: endTs)
      .where('evaluation_data.resident_evaluation.status.status', whereIn: ['evaluate', 'pending', 'draft'])
      .orderBy('scheduled_date');
}
```

> 🔔 **Index reminder:** keep the composite indexes suggested in `docs/firestore-schema.md` so the `whereIn` + `orderBy` queries stay fast.

---

## 3. Stream Consumption

```dart
Stream<List<ScheduleCardModel>> homeCardsStream({
  required String role,
  required String uid,
  DateTime? day,
}) {
  final query = buildScheduleQuery(
    role: role,
    uid: uid,
    day: day ?? DateTime.now(),
  );

  return query.snapshots().asyncMap((snapshot) async {
    final cards = <ScheduleCardModel>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();

      final residentRef = data['resident'] as DocumentReference?;
      final attendeeRef = data['attendee'] as DocumentReference?;
      final resident = residentRef != null ? await residentRef.get() : null;
      final attendee = attendeeRef != null ? await attendeeRef.get() : null;

      final evalKey = role == 'physician'
          ? 'attendee_evaluation'
          : 'resident_evaluation';
      final evalData = (data['evaluation_data'] as Map<String, dynamic>?)?[evalKey] as Map<String, dynamic>?;

      final status = evalData?['status'] != null
          ? (evalData!['status'] as Map<String, dynamic>)['status'] as String? ?? 'evaluate'
          : 'evaluate';

      if (status == 'done') {
        continue; // hide completed cards
      }

      cards.add(ScheduleCardModel(
        scheduleId: doc.id,
        status: status,
        shiftStart: (data['shift_timings'] as Map<String, dynamic>)['start_time'] as Timestamp,
        shiftEnd: (data['shift_timings'] as Map<String, dynamic>)['end_time'] as Timestamp,
        topic: (data['assigned_topic'] as Map<String, dynamic>?)?['topic_title'] as String? ?? 'General Emergency Medicine',
        resident: resident?.data(),
        attendee: attendee?.data(),
      ));
    }
    return cards;
  });
}
```

---

## 4. Status Bucketing

```dart
Map<String, List<ScheduleCardModel>> bucketCards(List<ScheduleCardModel> cards, String role) {
  final result = <String, List<ScheduleCardModel>>{
    'evaluate': [],
    'pending': [],
  };

  for (final card in cards) {
    switch (card.status) {
      case 'evaluate':
      case 'pending':
        result['evaluate']!.add(card);
        break;
      case 'draft':
        result['pending']!.add(card);
        break;
      default:
        break; // hidden statuses
    }
  }

  return result;
}
```

Add an `overdue` badge by comparing `shift_timings.end_time` with `DateTime.now()` plus a tolerance (e.g. 6 hours) and checking `status != 'done'`.

---

## 5. Card View Model

```dart
class ScheduleCardModel {
  ScheduleCardModel({
    required this.scheduleId,
    required this.status,
    required this.shiftStart,
    required this.shiftEnd,
    required this.topic,
    this.resident,
    this.attendee,
  });

  final String scheduleId;
  final String status; // evaluate | pending | draft | done
  final Timestamp shiftStart;
  final Timestamp shiftEnd;
  final String topic;
  final Map<String, dynamic>? resident;
  final Map<String, dynamic>? attendee;

  String get residentDisplayName => resident?['display_name'] as String? ?? 'Resident';
  String get residentPhoto => (resident?['profile_photo'] as Map<String, dynamic>?)?['url'] as String? ?? '';
  String get residentLevel => resident?['pgy_level'] as String? ?? '';
}
```

---

## 6. Actions & Status Updates

When the physician completes an evaluation, invoke the callable function (`api` handler) with `callName = 'createEvaluation'`. The Cloud Function already flips the schedule fields:

- `evaluation_data.attendee_evaluation.status.status = 'done'`
- `evaluation_data.attendee_evaluation.completed_at = serverTimestamp`
- `attending_evaluation_completed = true`

The home feed stream automatically drops the card after Firestore updates.

---

## 7. Required Composite Indexes

Keep these indexes (already captured by `scripts/fetch_firebase_web_config.sh`):

1. `schedules(attendee ASC, evaluation_data.attendee_evaluation.status.status ASC)`
2. `schedules(attendee ASC, scheduled_date ASC)`
3. `schedules(attendee ASC, scheduled_date DESC)`

Add the resident-focused counterparts before shipping the Flutter client:

- `schedules(resident_ref ASC, scheduled_date ASC, evaluation_data.resident_evaluation.status.status ASC)`
- `schedules(attendee_ref ASC, scheduled_date ASC, evaluation_data.attendee_evaluation.status.status ASC)`

Use `firebase firestore:indexes` to verify they are deployed.

---

## 8. Caching User Docs

Avoid re-fetching user documents for every frame by caching references:

```dart
final _userCache = <String, DocumentSnapshot>{};

Future<DocumentSnapshot?> getUserCached(DocumentReference? ref) async {
  if (ref == null) return null;
  final id = ref.id;
  if (_userCache.containsKey(id)) return _userCache[id];
  final snap = await ref.get();
  _userCache[id] = snap;
  return snap;
}
```

Clear the cache when signing out or when user switches accounts.

---

## 9. Security Rules Reminder

Ensure Firestore rules mirror the data model (pseudo-example):

```text
match /schedules/{scheduleId} {
  allow read: if request.auth != null && (
    resource.data.attendee_ref == '/users/' + request.auth.uid ||
    resource.data.resident_ref == '/users/' + request.auth.uid ||
    request.auth.token.admin == true
  );
}
```

---

## 10. QA Checklist

- [ ] Backfill script executed (`./scripts/backfill_schedule_schema.mjs --force`)
- [ ] Resident/attending indexes confirmed in Firestore console
- [ ] Flutter queries updated to use `scheduled_date` + `evaluation_data.*`
- [ ] Status colours map to new enum values (`evaluate`, `pending`, `draft`, `done`, `overdue`)
- [ ] Profile fallbacks use `profile_photo.url` or initials when missing

With these adjustments the Flutter UI stays tightly aligned with the backend schema and performs well for real-time updates.
