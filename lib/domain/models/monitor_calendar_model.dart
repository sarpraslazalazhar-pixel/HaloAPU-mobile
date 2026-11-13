class MonitorCalendarModel {
  final String date;
  final List<MonitorCalendarItemModel> bookings;

  MonitorCalendarModel({
    required this.date,
    required this.bookings,
  });

  factory MonitorCalendarModel.fromJson(Map<String, dynamic> json) {
    var list = json['bookings'] as List? ?? [];
    List<MonitorCalendarItemModel> bookingList = list.map((i) => MonitorCalendarItemModel.fromJson(i)).toList();

    return MonitorCalendarModel(
      date: json['date'] ?? '',
      bookings: bookingList,
    );
  }
}

class MonitorCalendarItemModel {
  final int id;
  final String namaAset;
  final String tipe;
  final String status;
  final String user;
  final String waktu;
  final String? rawStart;
  final String? rawEnd;

  MonitorCalendarItemModel({
    required this.id,
    required this.namaAset,
    required this.tipe,
    required this.status,
    required this.user,
    required this.waktu,
    this.rawStart,
    this.rawEnd,
  });

  factory MonitorCalendarItemModel.fromJson(Map<String, dynamic> json) {
    final raw = json['waktu_raw'];
    final rawMap = raw is Map ? raw : null;
    return MonitorCalendarItemModel(
      id: json['id'] ?? 0,
      namaAset: json['nama_aset'] ?? '',
      tipe: json['tipe'] ?? '',
      status: json['status'] ?? '',
      user: json['user'] ?? '-',
      waktu: json['waktu'] ?? '',
      rawStart: rawMap?['start']?.toString(),
      rawEnd: rawMap?['end']?.toString(),
    );
  }
}
