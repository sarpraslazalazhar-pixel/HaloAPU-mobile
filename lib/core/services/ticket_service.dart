import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import '../storage/secure_storage_helper.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import '../config/api_config.dart';
import 'session_manager.dart';

class TicketService {
  final Dio _dio;

  TicketService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiConfig.baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'Accept': 'application/json',
              },
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await SafeSecureStorage.read('auth_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (e.response?.statusCode == 401) {
          await SessionManager.handleHttpUnauthorized(
            path: e.requestOptions.path,
            authorizationHeader: e.requestOptions.headers['Authorization'],
            responseData: e.response?.data,
          );
        }
        return handler.next(e);
      },
    ));
  }

  /// Ambil pesan error dari body response apa pun bentuknya (Map/List/String/HTML).
  static String _errorMessage(Object? data, String fallback) {
    if (data is Map) {
      final msg = data['message'];
      if (msg != null && msg.toString().trim().isNotEmpty) return msg.toString();
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
        if (first != null && first.toString().trim().isNotEmpty) return first.toString();
      }
      return fallback;
    }
    if (data is String && data.trim().isNotEmpty) {
      final text = data.trim();
      // Body HTML/panjang (mis. halaman 500/419) tidak layak ditampilkan mentah.
      if (text.length > 120 || text.startsWith('<')) return fallback;
      return text;
    }
    return fallback;
  }

  /// Body response sebagai Map; body non-Map (HTML/teks) jadi Map kosong agar
  /// akses `['data']` tidak melempar `TypeError`.
  static Map<String, dynamic> _body(Response<dynamic> response) {
    final dynamic data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  Future<MultipartFile> _createMultipartFile(XFile file) async {
    final bytes = await file.readAsBytes();
    String mimeType = lookupMimeType(file.name, headerBytes: bytes) ?? 'application/octet-stream';
    
    // Fallback: detect image type from magic bytes if octet-stream
    if (mimeType == 'application/octet-stream') {
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
        mimeType = 'image/jpeg';
      } else if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        mimeType = 'image/png';
      }
    }

    final mediaType = MediaType.parse(mimeType);

    String name = file.name.trim();
    if (name.isEmpty || name == 'attachment' || name == 'image_picker' || !name.contains('.')) {
      final ext = mimeType.contains('png') ? 'png' : (mimeType.contains('pdf') ? 'pdf' : 'jpg');
      final base = (name.isEmpty || name == 'attachment' || name == 'image_picker') ? 'foto_${DateTime.now().millisecondsSinceEpoch}' : name;
      name = '$base.$ext';
    }

    return MultipartFile.fromBytes(
      bytes,
      filename: name,
      contentType: mediaType,
    );
  }

  // ============ SERVICES ============

  /// Get all service categories (Units with SubUnits)
  Future<Map<String, dynamic>> getServices() async {
    try {
      final response = await _dio.get('/services');
      return {'success': true, 'data': _body(response)['data']};
    } on DioException catch (e) {
      return {
        'success': false,
        'statusCode': e.response?.statusCode,
        'message': e.response?.statusCode == 401
            ? SessionManager.extractUnauthorizedMessage(e.response?.data)
            : _errorMessage(e.response?.data, 'Gagal mengambil layanan')
      };
    }
  }

  /// Get form fields for a specific sub unit
  Future<Map<String, dynamic>> getFormFields(int subUnitId) async {
    try {
      final response = await _dio.get('/services/$subUnitId/fields');
      return {'success': true, 'data': _body(response)['data']};
    } on DioException catch (e) {
      return {
        'success': false,
        'statusCode': e.response?.statusCode,
        'message': e.response?.statusCode == 401
            ? SessionManager.extractUnauthorizedMessage(e.response?.data)
            : _errorMessage(e.response?.data, 'Gagal memuat form')
      };
    }
  }

  // ============ TICKETS ============

  Future<Map<String, dynamic>> getTickets({
    List<String>? statuses,
    String? dateFrom,
    String? dateTo,
    String? search,
    String? tab,
    int page = 1,
  }) async {
    try {
      final Map<String, dynamic> queryParameters = {
        'page': page,
        if (dateFrom != null) 'date_from': dateFrom,
        if (dateTo != null) 'date_to': dateTo,
        if (search != null && search.isNotEmpty) 'search': search,
        if (tab != null && tab.isNotEmpty) 'tab': tab,
      };
      if (statuses != null && statuses.isNotEmpty) {
        queryParameters['status'] = statuses.join(',');
      }

      final response = await _dio.get('/tickets', queryParameters: queryParameters);
      return {
        'success': true,
        'data': _body(response)['data'],
        'meta': _body(response)['meta']
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'statusCode': e.response?.statusCode,
        'message': e.response?.statusCode == 401
            ? SessionManager.extractUnauthorizedMessage(e.response?.data)
            : _errorMessage(e.response?.data, 'Gagal mengambil tiket')
      };
    }
  }

  Future<Map<String, dynamic>> getTicketDetail(String id) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.get('/tickets/$cleanId');
      final body = _body(response);
      final data = body['data'];
      if (data is! Map) {
        return {
          'success': false,
          'message': _errorMessage(body, 'Respons detail tiket tidak valid'),
        };
      }
      return {'success': true, 'data': data};
    } on DioException catch (e) {
      return {
        'success': false,
        'statusCode': e.response?.statusCode,
        'message': e.response?.statusCode == 401
            ? SessionManager.extractUnauthorizedMessage(e.response?.data)
            : _errorMessage(e.response?.data, 'Gagal memuat tiket')
      };
    }
  }

  /// Create a new ticket with form_data and optional file attachments
  Future<Map<String, dynamic>> createTicket({
    required int subUnitId,
    required Map<String, dynamic> formData,
    String priority = 'normal',
    Map<String, List<XFile>>? attachments,
  }) async {
    try {
      final Map<String, dynamic> dataMap = {
        'sub_unit_id': subUnitId.toString(),
        'priority': priority,
        'form_data': jsonEncode(formData),
      };

      if (attachments != null && attachments.isNotEmpty) {
        final formDataObj = FormData.fromMap(dataMap);

        for (var entry in attachments.entries) {
          final fieldKey = entry.key;
          for (var file in entry.value) {
            final multipartFile = await _createMultipartFile(file);
            formDataObj.files.add(MapEntry(
              'attachments[$fieldKey][]',
              multipartFile,
            ));
          }
        }

        final response = await _dio.post('/tickets', data: formDataObj);
        return {
          'success': true,
          'data': _body(response)['data'],
          'message': _body(response)['message']
        };
      } else {
        final response = await _dio.post('/tickets', data: dataMap);
        return {
          'success': true,
          'data': _body(response)['data'],
          'message': _body(response)['message']
        };
      }
    } on DioException catch (e) {
      String message = 'Gagal membuat tiket';
      final data = e.response?.data;
      if (data is Map) {
        if (data['message'] != null) {
          message = data['message'].toString();
        } else if (data['errors'] is Map) {
          final firstError = (data['errors'] as Map).values.first;
          if (firstError is List && firstError.isNotEmpty) {
            message = firstError.first.toString();
          }
        }
      } else if (data is String && data.isNotEmpty) {
        message = data.length > 100
            ? 'Terjadi kesalahan pada server (${e.response?.statusCode ?? 500})'
            : data;
      }
      return {
        'success': false,
        'message': message,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal membuat tiket: $e',
      };
    }
  }

  Future<Map<String, dynamic>> changeStatus(
    String id,
    String newStatus, {
    String? catatan,
    List<XFile>? attachments,
  }) async {
    try {
      final cleanId = id.replaceAll('-', '');
      if (attachments == null || attachments.isEmpty) {
        final response = await _dio.post(
          '/tickets/$cleanId/status',
          data: {
            'status': newStatus,
            if (catatan != null && catatan.isNotEmpty) 'catatan': catatan,
          },
        );
        final data = _body(response);
        final message = (data['message'] != null)
            ? data['message'].toString()
            : 'Status berhasil diperbarui';
        return {'success': true, 'message': message};
      } else {
        final formData = FormData.fromMap({
          'status': newStatus,
          if (catatan != null && catatan.isNotEmpty) 'catatan': catatan,
        });

        for (var file in attachments) {
          final multipartFile = await _createMultipartFile(file);
          formData.files.add(MapEntry('general_attachments[]', multipartFile));
        }

        final response = await _dio.post('/tickets/$cleanId/status', data: formData);
        final data = _body(response);
        final message = (data['message'] != null)
            ? data['message'].toString()
            : 'Status berhasil diperbarui';
        return {'success': true, 'message': message};
      }
    } on DioException catch (e) {
      String message = 'Gagal mengubah status';
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        message = data['message'].toString();
      } else if (data is String && data.isNotEmpty) {
        message = data.length > 100
            ? 'Terjadi kesalahan pada server (${e.response?.statusCode ?? 500})'
            : data;
      }
      return {
        'success': false,
        'message': message,
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal mengubah status: $e',
      };
    }
  }

  Future<Map<String, dynamic>> assignOperator(String id, int? adminId) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.post(
        '/tickets/$cleanId/assign',
        data: {'admin_id': adminId},
      );
      return {'success': true, 'data': _body(response)['data'], 'message': _body(response)['message']};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _errorMessage(e.response?.data, 'Gagal menugaskan operator')
      };
    }
  }

  Future<Map<String, dynamic>> replyTicket(
    String id,
    String note, {
    List<XFile>? attachments,
  }) async {
    try {
      final cleanId = id.replaceAll('-', '');
      if (attachments != null && attachments.isNotEmpty) {
        final formData = FormData.fromMap({
          'catatan': note,
        });

        for (var file in attachments) {
          final multipartFile = await _createMultipartFile(file);
          formData.files.add(MapEntry('attachments[]', multipartFile));
        }

        final response = await _dio.post('/tickets/$cleanId/reply', data: formData);
        return {'success': true, 'data': _body(response)['data']};
      } else {
        final response = await _dio.post(
          '/tickets/$cleanId/reply',
          data: {'catatan': note},
        );
        return {'success': true, 'data': _body(response)['data']};
      }
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _errorMessage(e.response?.data, e.error?.toString() ?? 'Gagal membalas tiket')
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal membalas tiket: $e'
      };
    }
  }

  /// Cancel a ticket (only if status == 'open')
  Future<Map<String, dynamic>> cancelTicket(String id) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.patch('/tickets/$cleanId/cancel');
      return {
        'success': true,
        'message': _body(response)['message'],
        'data': _body(response)['data'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _errorMessage(e.response?.data, 'Gagal membatalkan tiket')
      };
    }
  }

  Future<Map<String, dynamic>> cancelBooking(String id, {String? catatan}) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.patch(
        '/tickets/$cleanId/cancel-booking',
        data: {
          if (catatan != null && catatan.isNotEmpty) 'catatan': catatan,
        },
      );
      return {
        'success': true,
        'message': _body(response)['message'] ?? 'Booking berhasil dibatalkan',
        'data': _body(response)['data'],
      };
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _errorMessage(e.response?.data, 'Gagal membatalkan booking')
      };
    }
  }

  /// Accept the result of a solved ticket
  Future<Map<String, dynamic>> acceptResult(String id) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.post('/tickets/$cleanId/accept');
      final data = _body(response);
      final message = (data['message'] != null)
          ? data['message'].toString()
          : 'Hasil pekerjaan diterima';
      return {'success': true, 'message': message};
    } on DioException catch (e) {
      final data = e.response?.data;
      return {
        'success': false,
        'message': (data is Map ? data['message'] : null)?.toString() ?? 'Gagal menerima hasil'
      };
    } catch (e) {
      return {'success': false, 'message': 'Gagal menerima hasil: $e'};
    }
  }

  /// Request revision on a solved ticket
  Future<Map<String, dynamic>> requestRevision(
    String id,
    String note, {
    List<XFile>? attachments,
  }) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final Response<dynamic> response;
      if (attachments != null && attachments.isNotEmpty) {
        final formData = FormData.fromMap({
          'catatan': note,
        });

        for (var file in attachments) {
          final multipartFile = await _createMultipartFile(file);
          formData.files.add(MapEntry('attachments[]', multipartFile));
        }

        response = await _dio.post('/tickets/$cleanId/revision', data: formData);
      } else {
        response = await _dio.post(
          '/tickets/$cleanId/revision',
          data: {'catatan': note},
        );
      }
      final data = _body(response);
      final message = (data['message'] != null)
          ? data['message'].toString()
          : 'Permintaan revisi terkirim';
      return {'success': true, 'message': message};
    } on DioException catch (e) {
      String message = 'Gagal mengajukan revisi';
      final data = e.response?.data;
      if (data is Map) {
        if (data['message'] != null) {
          message = data['message'].toString();
        } else if (data['errors'] is Map && (data['errors'] as Map).isNotEmpty) {
          final firstError = (data['errors'] as Map).values.first;
          if (firstError is List && firstError.isNotEmpty) {
            message = firstError.first.toString();
          }
        }
      }
      return {'success': false, 'message': message};
    } catch (e) {
      return {'success': false, 'message': 'Gagal mengajukan revisi: $e'};
    }
  }

  /// Submit CSAT rating for a ticket
  Future<Map<String, dynamic>> rateTicket(String id, int rating, {String? comment}) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.post(
        '/tickets/$cleanId/rate',
        data: {
          'rating': rating,
          if (comment != null && comment.isNotEmpty) 'komentar': comment,
        },
      );
      return {'success': true, 'message': _body(response)['message']};
    } on DioException catch (e) {
      return {
        'success': false,
        'message': _errorMessage(e.response?.data, 'Gagal memberi rating')
      };
    }
  }

  Future<Map<String, dynamic>> kembalikanAlat(String id, {required String kondisi, String? catatan}) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.post('/tickets/$cleanId/kembalikan-alat', data: {
        'kondisi_kembali': kondisi,
        if (catatan != null && catatan.isNotEmpty) 'catatan_kembali': catatan,
      });
      return {'success': true, 'message': _body(response)['message'] ?? 'Alat berhasil dikembalikan'};
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e.response?.data, 'Gagal menandai pengembalian alat')};
    }
  }

  /// Edit formulir tiket oleh admin (form_data + prioritas + alasan).
  Future<Map<String, dynamic>> updateTicketForm(
    String id, {
    required Map<String, dynamic> formData,
    String? priority,
    required String reason,
  }) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.patch('/tickets/$cleanId/form', data: {
        'form_data': formData,
        if (priority != null && priority.isNotEmpty) 'priority': priority,
        'edit_reason': reason,
      });
      return {
        'success': true,
        'message': _body(response)['message'] ?? 'Formulir tiket berhasil diperbarui',
        'data': _body(response)['data'],
        'editHistories': _body(response)['editHistories'],
      };
    } on DioException catch (e) {
      final data = e.response?.data;
      String message = 'Gagal menyimpan perubahan formulir';
      if (data is Map) {
        if (data['message'] != null) {
          message = data['message'].toString();
        } else if (data['errors'] is Map && (data['errors'] as Map).isNotEmpty) {
          final firstError = (data['errors'] as Map).values.first;
          if (firstError is List && firstError.isNotEmpty) {
            message = firstError.first.toString();
          }
        }
      }
      return {'success': false, 'message': message};
    }
  }

  Future<Map<String, dynamic>> resumeWork(String id) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.post('/tickets/$cleanId/resume-work');
      final data = _body(response);
      return {
        'success': true,
        'message': data['message'] ?? 'Tiket dilanjutkan',
        'data': data['data'],
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e.response?.data, 'Gagal melanjutkan tiket')};
    }
  }

  Future<Map<String, dynamic>> updatePriority(String id, String priority) async {
    try {
      final cleanId = id.replaceAll('-', '');
      final response = await _dio.patch('/tickets/$cleanId/priority', data: {
        'priority': priority,
      });
      return {'success': true, 'message': _body(response)['message'] ?? 'Prioritas berhasil diubah'};
    } on DioException catch (e) {
      return {'success': false, 'message': _errorMessage(e.response?.data, 'Gagal mengubah prioritas')};
    }
  }
}
