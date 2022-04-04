import 'dart:math';

import 'package:fishmatic/backend/data_models.dart';
import 'package:test/test.dart';
import 'package:firebase_database_mocks/firebase_database_mocks.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

import 'package:fishmatic/backend/data_access.dart';

void initTestRTDB(String userID) {
  final Map<String, dynamic> testData = {
    'users': {
      userID: {
        DataNodes.autoLightOn: false,
        DataNodes.feederServo: 0,
        DataNodes.filterServo: 0,
        DataNodes.lightOn: false,
        DataNodes.noCnxnActuator: true,
        DataNodes.noCnxnSensor: true,
        DataNodes.setupActuator: true,
        DataNodes.setupSensor: true,
        'status': {
          DataNodes.foodLevel: 0,
          DataNodes.lightLevel: 0,
          DataNodes.waterTemp: 0,
        }
      },
    },
  };
  MockFirebaseDatabase.instance.ref().set(testData);
  print('Test database initialised');
}

void main() {
  final String userID = 'test_user';

  group('RTDB tests:', () {
    initTestRTDB(userID);
    final GenericDAO<double> doubleDAO = GenericDAO<double>(
      userID,
      DataNodes.feederServo,
      testDB: MockFirebaseDatabase.instance,
    );
    final double value = Random().nextDouble();

    test('database write', () async {
      await doubleDAO.setValue(value);
      expect(
          (await MockFirebaseDatabase.instance
                  .ref()
                  .child('users')
                  .child(userID)
                  .child(DataNodes.feederServo)
                  .once())
              .snapshot
              .value,
          value);
    });

    test(
        'database read',
        () async =>
            expect((await doubleDAO.baseRef.once()).snapshot.value, value));
  });

  group('Firestore tests', () {
    List<double> foodAmounts =
        List.generate(100, (index) => 1.1, growable: false);
    FoodRecordDAO foodRecordDAO =
        FoodRecordDAO(userID, testDB: FakeFirebaseFirestore());

    test('firestore write', () async {
      for (double amount in foodAmounts) {
        await foodRecordDAO.addRecord(amount);
      }
      expect(await foodRecordDAO.getRecords(), foodAmounts);
    });

    test('firestore read', () async {
      foodRecordDAO.addRecord(1.1);
      expect((await foodRecordDAO.getRecords())[0], 1.1);
    });
  });
}
