class FishmaticBaseException implements Exception {
  final String _title;
  final String _message;
  final String _details;

  FishmaticBaseException(this._title, this._message, [this._details = '']);

  String get title => _title;
  String get message => _message;
  String get details => _details;

  @override
  String toString() => _title + ': ' + _message + '\n' + _details;
}

class DuplicateNameException extends FishmaticBaseException {
  DuplicateNameException(String dataType, String dataName)
      : super('Duplicate $dataType',
            'A $dataType called "$dataName" already exists.');
}

class NotFoundException extends FishmaticBaseException {
  NotFoundException(String dataType, String dataName)
      : super('$dataType Not Found', '$dataType "$dataName" not found.');
}

class MaxItemLimitException extends FishmaticBaseException {
  MaxItemLimitException(String dataType, int maxLimit)
      : super('$dataType limit reached',
            'Cannot have more than $maxLimit ${dataType}s.');
}

class MinItemLimitException extends FishmaticBaseException {
  MinItemLimitException(String dataType, int minLimit)
      : super('$dataType limit reached',
            'Must have atleast $minLimit ${dataType}s.');
}

class CriticalFoodException extends FishmaticBaseException {
  CriticalFoodException()
      : super(
            'Critical Food Level', 'Feeding is suspended');
}
