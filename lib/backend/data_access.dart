import 'dart:async';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:cloud_firestore/cloud_firestore.dart';

import './data_models.dart';

class GenericDAO<T> {
  late final DatabaseReference baseRef;

  GenericDAO(String userID, String dataNode, {FirebaseDatabase? testDB}) {
    baseRef = (testDB ?? FirebaseDatabase.instance)
        .ref()
        .child('users')
        .child(userID)
        .child(dataNode);
  }

  Future<void> init(T initValue, [String? childNode]) async {
    DatabaseReference ref =
        childNode == null ? baseRef : baseRef.child(childNode);
    if ((await ref.get()).value == null) await ref.set(initValue);
  }

  Future<T> getValue([String? childNode]) async {
    DatabaseReference ref =
        childNode == null ? baseRef : baseRef.child(childNode);
    return (await ref.get()).value! as T;
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

  ScheduleDAO(this.userID, {FirebaseDatabase? testDB}) {
    schedulesRef = (testDB ?? FirebaseDatabase.instance)
        .ref()
        .child('users')
        .child(userID)
        .child('schedules');
    activeRef = (testDB ?? FirebaseDatabase.instance)
        .ref()
        .child('users')
        .child(userID)
        .child('active_schedule');
  }

  Future<Map<String, Schedule>> get scheduleMap async {
    final DataSnapshot snapshot = await schedulesRef.get();
    if (snapshot.value == null) return {};
    final Map scheduleInfo = snapshot.value as Map<Object?, Object?>;
    return (scheduleInfo).map((scheduleName, scheduleJson) => MapEntry(
        scheduleName.toString(),
        Schedule.fromJson(scheduleName.toString(),
            Map<String, dynamic>.from(scheduleJson as Map<Object?, Object?>))));
  }

  Future<String?> get activeName async =>
      (await activeRef.get()).value as String?;

  Future<void> addActive(String scheduleName) async =>
      await activeRef.set(scheduleName);

  Future<void> addSchedule(Schedule newSchedule) async =>
      await schedulesRef.child(newSchedule.name).set(newSchedule.toJson());

  Future<void> deleteActive() async {
    String? _activeName = await activeName;
    if (_activeName != null) await activeRef.remove();
  }

  Future<void> deleteSchedule(String scheduleName) async =>
      await schedulesRef.child(scheduleName).remove();

  Future<void> updateData(
          String scheduleName, Map<String, dynamic> updateFields) async =>
      await schedulesRef.child(scheduleName).update(updateFields);
}

class FoodRecordDAO {
  final String userID;
  late final CollectionReference foodRecordsRef;

  FoodRecordDAO(this.userID, {FirebaseFirestore? testDB}) {
    foodRecordsRef = (testDB ?? FirebaseFirestore.instance)
        .collection('users')
        .doc(userID)
        .collection('food_records')
        .withConverter<FoodRecord>(
          fromFirestore: (snapshot, _) => FoodRecord.fromJson(snapshot.data()!),
          toFirestore: (foodRecord, _) => foodRecord.toJson(),
        );
  }

  Future<List<double>> getRecords() async {
    List<QueryDocumentSnapshot> records =
        (await foodRecordsRef.orderBy('timestamp').limitToLast(100).get()).docs;
    return List.generate(
      records.length,
      (index) => (records[index].data()! as FoodRecord).amount,
      growable: false,
    );
  }

  Future<void> addRecord(double amount) async =>
      await foodRecordsRef.add(FoodRecord(amount));

  Future<void> deleteAllRecords() async {
    List<QueryDocumentSnapshot> records =
        (await foodRecordsRef.orderBy('timestamp').get()).docs;
    for (QueryDocumentSnapshot doc in records) {
      doc.reference.delete();
    }
  }
}
