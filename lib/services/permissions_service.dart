import 'package:injectable/injectable.dart';

@singleton
class PermissionsService {
  Future<void> initialize() async {
    // TODO: request runtime permissions (camera, location, storage, bluetooth)
  }
}
