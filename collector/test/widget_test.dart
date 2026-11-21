import 'package:flutter_test/flutter_test.dart';
import 'package:krishi_collector/main.dart';

void main() {
  test('labels follow the training folder convention', () {
    expect(labelFor('Spinach', 'healthy', ''), 'Spinach___healthy');
    expect(labelFor('Spinach', 'disease', 'Leaf spot'), 'Spinach___Leaf_spot');
    expect(labelFor('Bottle gourd', 'pest', ''), 'Bottle_gourd___Unknown_pest');
  });
}
