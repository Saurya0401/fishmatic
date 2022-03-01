import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

import 'package:fishmatic/backend/data_models.dart';

class GenericDAO<T> {
  late final DatabaseReference baseRef;

  GenericDAO(String userID, String dataNode) {
    baseRef = FirebaseDatabase.instance
        .ref()
        .child('users_test')
        .child(userID)
        .child(dataNode);
  }

  Future<void> init(T initValue, [String? childNode]) async {
    DatabaseReference ref =
        childNode == null ? baseRef : baseRef.child(childNode);
    if ((await ref.once()).snapshot.value == null) ref.set(initValue);
  }

  Future<T> getValue([String? childNode]) async {
    DatabaseReference ref =
        childNode == null ? baseRef : baseRef.child(childNode);
    return (await ref.once()).snapshot.value! as T;
  }

  Stream<DatabaseEvent> getStream([String? childNode]) {
    DatabaseReference ref =
        childNode == null ? baseRef : baseRef.child(childNode);
    return ref.onValue;
  }

  Future<void> setChildValue(String dataNode, T value) async =>
      await baseRef.child(dataNode).set(value);

  Future<void> setValue(T value) async => await baseRef.set(value);
}

class StatusDAO extends GenericDAO<double> {
  StatusDAO(String userID) : super(userID, 'status');

  Stream<DatabaseEvent> getStatusStream(String dataNode) => getStream(dataNode);
}

class ScheduleDAO {
  final String userID;
  late final DatabaseReference schedulesRef;
  late final DatabaseReference activeRef;

  ScheduleDAO(this.userID) {
    schedulesRef = FirebaseDatabase.instance
        .ref()
        .child('users_test')
        .child(userID)
        .child('schedules');
    activeRef = FirebaseDatabase.instance
        .ref()
        .child('users_test')
        .child(userID)
        .child('active_schedule');
  }

  Future<Map<String, Schedule>> get scheduleMap async {
    final DatabaseEvent event = await schedulesRef.once();
    if (event.snapshot.value == null) return {};
    final Map scheduleInfo = event.snapshot.value as Map<Object?, Object?>;
    return (scheduleInfo).map((scheduleName, scheduleJson) => MapEntry(
        scheduleName as String,
        Schedule.fromJson(scheduleName,
            Map<String, dynamic>.from(scheduleJson as Map<Object?, Object?>))));
  }

  Future<String?> get activeName async =>
      (await activeRef.once()).snapshot.value as String?;

  Future<void> addActive(String dataName) async =>
      await activeRef.set(dataName);

  Future<void> addSchedule(Schedule newSchedule) async =>
      await schedulesRef.child(newSchedule.name).set(newSchedule.toJson());

  Future<void> deleteActive() async {
    String? _activeName = await activeName;
    if (_activeName != null) await activeRef.child(_activeName).remove();
  }

  Future<void> deleteSchedule(String scheduleName) async =>
      await schedulesRef.child(scheduleName).remove();

  Future<void> updateData(
          String scheduleName, Map<String, dynamic> updateFields) async =>
      await schedulesRef.child(scheduleName).update(updateFields);
}
