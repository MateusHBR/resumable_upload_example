import 'package:meta/meta.dart';
import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/retry.dart' as retry;
import 'package:http/http.dart' as http;
import 'http_client.dart' as app;

final class CupertinoHttpClient extends app.HttpClient {
  @visibleForTesting
  http.BaseClient Function() baseClientBuilder = () {
    final config = URLSessionConfiguration.defaultSessionConfiguration();
    config.httpMaximumConnectionsPerHost = 8;
    config.allowsExpensiveNetworkAccess = true;
    config.allowsCellularAccess = true;
    config.networkServiceType =
        NSURLRequestNetworkServiceType.NSURLNetworkServiceTypeResponsiveData;
    config.waitsForConnectivity = true;
    config.multipathServiceType =
        NSURLSessionMultipathServiceType
            .NSURLSessionMultipathServiceTypeHandover;
    config.requestCachePolicy =
        NSURLRequestCachePolicy.NSURLRequestReloadIgnoringLocalCacheData;

    final nativeClient = CupertinoClient.fromSessionConfiguration(config);

    final client = retry.RetryClient(
      nativeClient,
      when: (resp) => resp.statusCode >= 500,
      whenError: (error, _) {
        print('Error: ${error.toString()}');
        final commonExceptions = [
          'SocketException',
          'HttpException',
          'HandshakeException',
          'TimeoutException',
        ];

        final err = error.runtimeType.toString();
        return commonExceptions.any(err.contains);
      },
      delay: (c) => Duration(milliseconds: c * 200),
    );

    return client;
  };

  late final http.BaseClient _client = baseClientBuilder();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final resp = await _client.send(request);
    return resp;
  }
}
