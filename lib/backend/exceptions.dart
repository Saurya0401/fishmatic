class FishmaticBaseException implements Exception {
  final String _title;
  final String _message;
  final String? _details;

  FishmaticBaseException(this._title, this._message, [this._details]);

  String get title => _title;
  String get message => _message;
  String get details => _details ?? '';
  String get errorText =>
      _message + (_details == null ? '' : ':\n' + _details!) + '.';

  @override
  String toString() => errorText;
}

class BluetoothConnectionError extends FishmaticBaseException {
  BluetoothConnectionError(String message)
      : super('Bluetooth Connection Error', message);
}

class BluetoothDisabledException extends FishmaticBaseException {
  BluetoothDisabledException()
      : super('Bluetooth Disabled', 'Please turn on bluetooth');
}

class SetupException extends FishmaticBaseException {
  SetupException(String message) : super('Setup Error', message);
}

class DuplicateNameException extends FishmaticBaseException {
  DuplicateNameException(String dataType, String dataName)
      : super('Duplicate Name Error',
            'A $dataType called "$dataName" already exists');
}

class NotFoundException extends FishmaticBaseException {
  NotFoundException(String dataType, String dataName)
      : super('Not Found Error', '$dataType "$dataName" not found');
}

class MaxItemLimitException extends FishmaticBaseException {
  MaxItemLimitException(String dataType, int maxLimit)
      : super('Max Item Error', 'Cannot have more than $maxLimit ${dataType}s');
}

class MinItemLimitException extends FishmaticBaseException {
  MinItemLimitException(String dataType, int minLimit)
      : super('Min Item Error', 'Must have atleast $minLimit ${dataType}s');
}

class CriticalFoodException extends FishmaticBaseException {
  CriticalFoodException()
      : super('Critical Food Error', 'Food level is at critical levels',
            'Feeding is suspended');
}

class ConnectionTimeout extends FishmaticBaseException {
  ConnectionTimeout(String message)
      : super('Connection Timed Out', 'Connection timed out', message);
}
