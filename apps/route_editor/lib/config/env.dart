class Env {
  static const String connectionMode = 'tunnel';
  static const String apiUrl = 'https://bus-api.catcode.tech';
  static const String serverIp = 'localhost';
  static const int apiPort = 8000;
  static const String apiSecretKey =
      'gO07ar3UQV3Tb2qoy5ETAWwCknKwRiKr4bQ2Lh3JjsmdKX7CJ4wPEvBhYwpTfIVWNgDVRDPAWIqLSb01sXzFsf2sosChslTrRQVXCpfycf6mvJqKgx0UfZqQzCqUW36iQTF6Udgt7tSHSd09TD0KrPCJSutcj298nnjnHcw0MKPiP7xFddWBXc2vuBL0GWUgCJNi9JlelUqmuhISOB12BUCF3cZc38Job7Yt8AnSj959vpclYLmojHKF97adSXBo';

  static bool get isTunnelMode => connectionMode == 'tunnel';
}
