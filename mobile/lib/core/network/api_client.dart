  /// POST to an SSE streaming endpoint. Returns a stream of token strings.
  /// When the caller cancels the subscription, the underlying HTTP request
  /// is aborted to prevent resource leaks.
  Stream<String> streamPost(String path, {dynamic data, CancelToken? cancelToken}) {
    final cancelTokenForRequest = cancelToken ?? CancelToken();
    final streamController = StreamController<String>(
      onCancel: () {
        if (!cancelTokenForRequest.isCancelled) {
          cancelTokenForRequest.cancel('Stream cancelled by client');
        }
        developer.log('SSE stream cancelled, request aborted');
      },
    );

    _dio.post<ResponseBody>(
      path,
      data: data,
      options: Options(responseType: ResponseType.stream),
      cancelToken: cancelTokenForRequest,
    ).then((response) {
      // Guard: if already cancelled before response arrived
      if (cancelTokenForRequest.isCancelled) return;
      final body = response.data as ResponseBody;
      body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data: ')) {
            final payload = line.substring(6).trim();
            if (payload == '[DONE]') {
              unawaited(streamController.close());
              return;
            }
            try {
              final json = jsonDecode(payload) as Map<String, dynamic>;
              if (json.containsKey('error')) {
                streamController.addError(Exception(json['error']));
                unawaited(streamController.close());
                return;
              }
              final token = json['token'] as String?;
              if (token != null && token.isNotEmpty) {
                streamController.add(token);
              }
            } catch (e) {
              developer.log('SSE parse error: $e');
            }
          }
        },
        onDone: () => unawaited(streamController.close()),
        onError: (e) {
          if (!streamController.isClosed) {
            streamController.addError(e);
            unawaited(streamController.close());
          }
        },
        cancelOnError: false,
      );
    }).catchError((e) {
      if (cancelTokenForRequest.isCancelled) return; // Intentional cancellation
      if (!streamController.isClosed) {
        streamController.addError(e);
        unawaited(streamController.close());
      }
    });

    return streamController.stream;
  }