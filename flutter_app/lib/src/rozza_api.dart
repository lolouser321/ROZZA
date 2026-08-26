import 'dart:convert';

import 'package:http/http.dart' as http;

import 'track.dart';

class RozzaApi {
  RozzaApi({http.Client? client}) : _client = client ?? http.Client();

  static const configuredBaseUrl = String.fromEnvironment('ROZZA_API_BASE_URL');

  final http.Client _client;

  bool get isConfigured =>
      Uri.tryParse(configuredBaseUrl)?.isScheme('https') ?? false;

  Future<List<Track>> search(String query) async {
    if (!isConfigured) return _searchAudius(query);
    final base = configuredBaseUrl.replaceFirst(RegExp(r'/$'), '');
    final response = await _client
        .post(
          Uri.parse('$base/api/v2/search'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'query': query,
            'source': 'youtubeMusic',
            'filter': 'songs',
            'page': 0,
            'pageSize': 40,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Search failed (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['tracks'] as List<dynamic>? ?? const [])
        .map((value) => Track.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<Track>> _searchAudius(String query) async {
    final response = await _client
        .get(
          Uri.https('api.audius.co', '/v1/tracks/search', {
            'query': query,
            'limit': '40',
            'app_name': 'ROZZA',
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Audius search failed (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['data'] as List<dynamic>? ?? const [])
        .map((value) => value as Map<String, dynamic>)
        .where((value) {
          final stream = value['stream'] as Map<String, dynamic>?;
          return value['is_streamable'] != false && stream?['url'] != null;
        })
        .map((value) {
          final user = value['user'] as Map<String, dynamic>? ?? const {};
          final artwork = value['artwork'] as Map<String, dynamic>?;
          final stream = value['stream'] as Map<String, dynamic>;
          final id = value['id'].toString();
          return Track(
            id: 'audius-$id',
            title: value['title'] as String? ?? 'Untitled',
            artist:
                user['name'] as String? ??
                user['handle'] as String? ??
                'Unknown artist',
            album:
                (value['album_backlink'] as Map<String, dynamic>?)?['title']
                    as String?,
            artworkUrl:
                artwork?['480x480'] as String? ??
                artwork?['150x150'] as String?,
            duration: (value['duration'] as num?)?.toDouble(),
            sources: [
              TrackSource(
                provider: 'audius',
                providerId: id,
                url: stream['url'] as String,
                canPlayInBackground: true,
              ),
            ],
          );
        })
        .toList(growable: false);
  }
}
