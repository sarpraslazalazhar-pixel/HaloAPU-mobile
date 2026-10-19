import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/config/app_flavor.dart';
import 'package:halo_apu_mobile/core/config/api_config.dart';

void main() {
  group('FlavorConfig & ApiConfig', () {
    test('resolves consistent values for the active flavor', () {
      if (FlavorConfig.isStaging) {
        expect(FlavorConfig.current, AppFlavor.staging);
        expect(FlavorConfig.baseUrl, 'https://dev.haloapu.id/api');
        expect(FlavorConfig.webUrl, 'https://dev.haloapu.id');
        expect(FlavorConfig.appTitle, 'Halo APU Staging');
      } else {
        expect(FlavorConfig.current, AppFlavor.production);
        expect(FlavorConfig.baseUrl, 'https://haloapu.id/api');
        expect(FlavorConfig.webUrl, 'https://haloapu.id');
        expect(FlavorConfig.appTitle, 'Halo APU');
      }
    });

    test('ApiConfig delegates to FlavorConfig', () {
      expect(ApiConfig.baseUrl, FlavorConfig.baseUrl);
      expect(ApiConfig.defaultBaseUrl, FlavorConfig.baseUrl);
    });
  });
}
