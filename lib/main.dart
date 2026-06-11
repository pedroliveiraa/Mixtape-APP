// MIXTAPE APP — main.dart  (v3 — Retrô + PDF + Backup)
//
// pubspec.yaml (adicionar às dependências existentes):
//   pdf: ^3.10.8
//   path_provider: ^2.1.3
//   share_plus: ^9.0.0
//   file_picker: ^8.0.0
//   printing: ^5.12.0
// ===========================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// ===========================================================
// MODELOS
// ===========================================================

class Track {
  final String id;
  final String title;
  final String artist;
  final String albumTitle;
  final String? albumId;
  final String? artistId;
  final String coverUrl;
  final String previewUrl;
  String personalNote;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.albumTitle,
    this.albumId,
    this.artistId,
    required this.coverUrl,
    required this.previewUrl,
    this.personalNote = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'albumTitle': albumTitle,
        'albumId': albumId,
        'artistId': artistId,
        'coverUrl': coverUrl,
        'previewUrl': previewUrl,
        'personalNote': personalNote,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'],
        title: json['title'],
        artist: json['artist'],
        albumTitle: json['albumTitle'] ?? '',
        albumId: json['albumId'],
        artistId: json['artistId'],
        coverUrl: json['coverUrl'],
        previewUrl: json['previewUrl'],
        personalNote: json['personalNote'] ?? '',
      );
}

class Mixtape {
  final String id;
  String title;
  String recipient;
  String openingMessage;
  List<Track> tracks;
  String theme;
  String? photoPath;
  final DateTime createdAt;

  Mixtape({
    required this.id,
    required this.title,
    required this.recipient,
    required this.openingMessage,
    required this.tracks,
    required this.theme,
    this.photoPath,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'recipient': recipient,
        'openingMessage': openingMessage,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'theme': theme,
        'photoPath': photoPath,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Mixtape.fromJson(Map<String, dynamic> json) => Mixtape(
        id: json['id'],
        title: json['title'],
        recipient: json['recipient'],
        openingMessage: json['openingMessage'],
        tracks: (json['tracks'] as List).map((t) => Track.fromJson(t)).toList(),
        theme: json['theme'],
        photoPath: json['photoPath'],
        createdAt: DateTime.parse(json['createdAt']),
      );
}

// ===========================================================
// SERVIÇO DE BUSCA (iTunes, sem branding externo)
// ===========================================================

class MusicSearchService {
  static const _base = 'https://itunes.apple.com';

  static String _hiresCover(String url) =>
      url.replaceAll('100x100bb', '600x600bb');

  static Track _trackFromJson(Map<String, dynamic> t) => Track(
        id: t['trackId']?.toString() ?? t['collectionId'].toString(),
        title: t['trackName'] ?? t['collectionName'] ?? '',
        artist: t['artistName'] ?? 'Artista Desconhecido',
        albumTitle: t['collectionName'] ?? '',
        albumId: t['collectionId']?.toString(),
        artistId: t['artistId']?.toString(),
        coverUrl: _hiresCover(t['artworkUrl100'] ?? ''),
        previewUrl: t['previewUrl'] ?? '',
      );

  static Future<List<Track>> search(String query, {int limit = 20}) async {
    if (query.trim().isEmpty) return [];
    try {
      final uri = Uri.parse(
          '$_base/search?term=${Uri.encodeComponent(query)}&entity=song&limit=$limit&country=BR');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final List results = data['results'] ?? [];
        return results
            .where((t) =>
                t['kind'] == 'song' &&
                t['previewUrl'] != null &&
                (t['previewUrl'] as String).isNotEmpty)
            .map((t) => _trackFromJson(t as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Erro busca: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getAlbum(String albumId) async {
    if (albumId.isEmpty) return null;
    try {
      final uri = Uri.parse('$_base/lookup?id=$albumId&entity=song&country=BR');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final List results = data['results'] ?? [];
        if (results.isEmpty) return null;
        final album = results.first as Map<String, dynamic>;
        final tracks = results
            .skip(1)
            .where((t) =>
                t['kind'] == 'song' &&
                t['previewUrl'] != null &&
                (t['previewUrl'] as String).isNotEmpty)
            .map((t) => _trackFromJson(t as Map<String, dynamic>))
            .toList();
        return {
          'title': album['collectionName'] ?? '',
          'artist': album['artistName'] ?? '',
          'cover': _hiresCover(album['artworkUrl100'] ?? ''),
          'tracks': tracks,
        };
      }
    } catch (e) {
      debugPrint('Erro álbum: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getArtist(String artistId) async {
    if (artistId.isEmpty) return null;
    try {
      final uri = Uri.parse(
          '$_base/lookup?id=$artistId&entity=song&limit=1&country=BR');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final List results = data['results'] ?? [];
        if (results.isEmpty) return null;
        final a = results.first as Map<String, dynamic>;
        return {
          'name': a['artistName'] ?? '',
          'genre': a['primaryGenreName'] ?? '',
        };
      }
    } catch (e) {
      debugPrint('Erro artista: $e');
    }
    return null;
  }

  static Future<List<Track>> getArtistTop(String artistId, {int limit = 20}) async {
    if (artistId.isEmpty) return [];
    try {
      final uri = Uri.parse(
          '$_base/lookup?id=$artistId&entity=song&limit=$limit&country=BR');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final List results = data['results'] ?? [];
        return results
            .where((t) =>
                t['kind'] == 'song' &&
                t['previewUrl'] != null &&
                (t['previewUrl'] as String).isNotEmpty)
            .map((t) => _trackFromJson(t as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Erro artista top: $e');
    }
    return [];
  }
}

// ===========================================================
// SERVIÇO DE ARMAZENAMENTO LOCAL
// ===========================================================

class StorageService {
  static const _key = 'mixtapes_v1';
  static const _firstUseKey = 'first_use_date';

  static Future<List<Mixtape>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw.map((s) => Mixtape.fromJson(jsonDecode(s))).toList();
  }

  static Future<void> saveAll(List<Mixtape> mixtapes) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = mixtapes.map((m) => jsonEncode(m.toJson())).toList();
    await prefs.setStringList(_key, raw);
  }

  static Future<void> add(Mixtape mixtape) async {
    final all = await loadAll();
    all.insert(0, mixtape);
    await saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((m) => m.id == id);
    await saveAll(all);
  }

  static Future<void> update(Mixtape mixtape) async {
    final all = await loadAll();
    final idx = all.indexWhere((m) => m.id == mixtape.id);
    if (idx >= 0) {
      all[idx] = mixtape;
      await saveAll(all);
    }
  }

  static Future<DateTime> getFirstUseDate() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_firstUseKey);
    if (stored != null) return DateTime.parse(stored);
    final now = DateTime.now();
    await prefs.setString(_firstUseKey, now.toIso8601String());
    return now;
  }
}

class ProfileService {
  static const _nameKey = 'user_display_name';

  static Future<String> getName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey) ?? '';
  }

  static Future<void> saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }
}

// ===========================================================
// SERVIÇO DE BACKUP JSON
// ===========================================================

class BackupService {
  static Future<void> exportBackup(BuildContext context) async {
    try {
      final mixtapes = await StorageService.loadAll();
      final name = await ProfileService.getName();
      final firstUse = await StorageService.getFirstUseDate();
      
      final backup = {
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'profile': {
          'name': name,
          'memberSince': firstUse.toIso8601String(),
        },
        'mixtapes': mixtapes.map((m) => m.toJson()).toList(),
      };

      final json = const JsonEncoder.withIndent('  ').convert(backup);
      final bytes = utf8.encode(json);

      final filename = 'mixtape_backup_${DateTime.now().millisecondsSinceEpoch}.json';

      if (kIsWeb) {
        final file = XFile.fromData(bytes, name: filename, mimeType: 'application/json');
        await Share.shareXFiles(
          [file],
          subject: 'Backup Mixtape',
          text: 'Meu backup do Mixtape — ${mixtapes.length} fitas salvas.',
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Backup Mixtape',
        text: 'Meu backup do Mixtape — ${mixtapes.length} fitas salvas.',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao exportar: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  static Future<bool> importBackup(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) return false;

      final String content;
      // No navegador (web), lemos os bytes do arquivo. Em outras plataformas, usamos o caminho.
      if (kIsWeb) {
        final bytes = result.files.first.bytes;
        if (bytes == null) throw Exception("Não foi possível ler o arquivo no navegador.");
        content = utf8.decode(bytes);
      } else {
        final file = File(result.files.first.path!);
        content = await file.readAsString();
      }
      final data = jsonDecode(content) as Map<String, dynamic>;

      // Restaurar perfil
      if (data['profile'] != null) {
        final pName = data['profile']['name'] as String? ?? '';
        if (pName.isNotEmpty) await ProfileService.saveName(pName);
      }

      // Restaurar mixtapes
      final mixtapesJson = data['mixtapes'] as List? ?? [];
      final mixtapes = mixtapesJson.map((m) => Mixtape.fromJson(m)).toList();
      await StorageService.saveAll(mixtapes.cast<Mixtape>());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${mixtapes.length} fitas restauradas!'),
            backgroundColor: cSuccessGreen,
          ),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao importar: $e'), backgroundColor: Colors.redAccent),
        );
      }
      return false;
    }
  }
}

// ===========================================================
// SERVIÇO DE PDF
// ===========================================================

class MixtapePdfService {
  static List<int> _themeColorPdf(String theme) {
    switch (theme) {
      case 'sunset': return [154, 52, 18];
      case 'night': return [49, 46, 129];
      case 'forest': return [6, 78, 59];
      case 'ocean': return [12, 74, 110];
      default: return [39, 39, 42];
    }
  }

  static Future<Uint8List> generate(Mixtape mixtape) async {
    final pdf = pw.Document();
    final rgb = _themeColorPdf(mixtape.theme);
    final themeColor = PdfColor.fromInt(
      (0xFF000000 | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]),
    );
    final themeColorLight = PdfColor(
      rgb[0] / 255 + 0.3,
      rgb[1] / 255 + 0.3,
      rgb[2] / 255 + 0.3,
    );

    final dateStr =
        '${mixtape.createdAt.day.toString().padLeft(2, '0')}/${mixtape.createdAt.month.toString().padLeft(2, '0')}/${mixtape.createdAt.year}';

    // ---- PÁGINA DE CAPA ----
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context ctx) {
          return pw.Stack(
            children: [
              // Fundo do tema
              pw.Positioned.fill(
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                    gradient: pw.LinearGradient(
                      colors: [themeColor, PdfColors.black],
                      begin: pw.Alignment.topLeft,
                      end: pw.Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
              // Padrão de linhas (textura retrô)
              // O padrão de linhas foi removido para evitar "riscos" na capa.
              // Conteúdo
              pw.Padding(
                padding: const pw.EdgeInsets.all(60),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Badge "MIXTAPE"
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.amber, width: 1.5),
                      ),
                      child: pw.Text(
                        'M I X T A P E',
                        style: pw.TextStyle(
                          color: PdfColors.amber,
                          fontSize: 11,
                          letterSpacing: 4,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.SizedBox(height: 48),
                    // Título da fita
                    pw.Text(
                      mixtape.title.toUpperCase(),
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 42,
                        fontWeight: pw.FontWeight.bold,
                        lineSpacing: 4,
                      ),
                    ),
                    pw.SizedBox(height: 16),
                    // Para quem
                    pw.Row(
                      children: [
                        pw.Container(
                          width: 40,
                          height: 1.5,
                          color: PdfColors.amber,
                        ),
                        pw.SizedBox(width: 12),
                        pw.Text(
                          'para ${mixtape.recipient}',
                          style: const pw.TextStyle(
                            color: PdfColors.amber,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 48),
                    // Linha divisória
                    pw.Container(height: 0.5, color: PdfColors.white.withAlpha(0.38)),
                    pw.SizedBox(height: 32),
                    // Mensagem de abertura
                    if (mixtape.openingMessage.isNotEmpty) ...[
                      pw.Text(
                        '"',
                        style: pw.TextStyle(
                          color: PdfColors.amber,
                          fontSize: 60,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        mixtape.openingMessage,
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 15,
                          lineSpacing: 6,
                        ),
                      ),
                    ],
                    pw.Spacer(),
                    // Footer da capa
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          dateStr,
                          style: const pw.TextStyle(color: PdfColor(1, 1, 1, 0.54), fontSize: 11),
                        ),
                        pw.Text(
                          '${mixtape.tracks.length} FAIXAS',
                          style: const pw.TextStyle(
                            color: PdfColor(1, 1, 1, 0.54),
                            fontSize: 11,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    // ---- PÁGINA DE TRACKLIST ----
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context ctx) {
          return pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Container(color: const PdfColor(0.05, 0.05, 0.05)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(60),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Cabeçalho tracklist
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'LADO A — TRACKLIST',
                          style: pw.TextStyle(
                            color: PdfColors.amber,
                            fontSize: 11,
                            letterSpacing: 3,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          mixtape.title,
                          style: const pw.TextStyle(
                            color: PdfColor(1, 1, 1, 0.54),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Container(height: 0.5, color: PdfColors.amber),
                    pw.SizedBox(height: 24),
                    // Faixas
                    ...mixtape.tracks.asMap().entries.map((e) {
                      final i = e.key;
                      final t = e.value;
                      final isEven = i % 2 == 0;
                      return pw.Container(
                        color: isEven
                            ? const PdfColor(0.10, 0.10, 0.10)
                            : const PdfColor(0.08, 0.08, 0.08),
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        margin: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Row(
                          children: [
                            // Número
                            pw.SizedBox(
                              width: 32,
                              child: pw.Text(
                                '${(i + 1).toString().padLeft(2, '0')}.',
                                style: pw.TextStyle(
                                  color: PdfColors.amber,
                                  fontSize: 13,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                            pw.SizedBox(width: 12),
                            // Info da faixa
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(
                                    t.title,
                                    style: pw.TextStyle(
                                      color: PdfColors.white,
                                      fontSize: 13,
                                      fontWeight: pw.FontWeight.bold,
                                    ),
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Text(
                                    t.artist +
                                        (t.albumTitle.isNotEmpty
                                            ? '  ·  ${t.albumTitle}'
                                            : ''),
                                    style: const pw.TextStyle(
                                      color: PdfColor(1, 1, 1, 0.54),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Nota pessoal
                            if (t.personalNote.isNotEmpty)
                              pw.Container(
                                constraints: const pw.BoxConstraints(maxWidth: 120),
                                padding: const pw.EdgeInsets.all(6),
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(
                                    color: PdfColors.amber,
                                    width: 0.5,
                                  ),
                                ),
                                child: pw.Text(
                                  '"${t.personalNote}"',
                                  style: const pw.TextStyle(
                                    color: PdfColors.amber,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    pw.Spacer(),
                    pw.Container(height: 0.5, color: PdfColors.white.withAlpha(0.12)),
                    pw.SizedBox(height: 12),
                    pw.Center(
                      child: pw.Text(
                        'feito com carinho · MIXTAPE · $dateStr',
                        style: const pw.TextStyle(
                          color: PdfColor(1, 1, 1, 0.38),
                          fontSize: 9,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> shareAsPdf(BuildContext context, Mixtape mixtape) async {
    try {
      final bytes = await generate(mixtape);
      final safeName = mixtape.title
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(' ', '_')
          .toLowerCase();

      if (kIsWeb) {
        await Printing.sharePdf(bytes: bytes, filename: 'mixtape_$safeName.pdf');
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mixtape_$safeName.pdf');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Mixtape: ${mixtape.title}',
        text: 'Uma fita feita especialmente para ${mixtape.recipient} 🎶',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}

// ===========================================================
// ESTADO GLOBAL DO PLAYER
// ===========================================================

class PlayerState extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  Track? currentTrack;
  bool isPlaying = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  PlayerState() {
    _player.positionStream.listen((p) { position = p; notifyListeners(); });
    _player.durationStream.listen((d) { duration = d ?? Duration.zero; notifyListeners(); });
    _player.playingStream.listen((playing) { isPlaying = playing; notifyListeners(); });
  }

  Future<void> play(Track track) async {
    if (track.previewUrl.isEmpty) return;
    currentTrack = track;
    await _player.stop();
    await _player.setUrl(track.previewUrl);
    await _player.play();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_player.playing) await _player.pause();
    else await _player.play();
  }

  Future<void> stop() async {
    await _player.stop();
    currentTrack = null;
    notifyListeners();
  }

  double get progress {
    if (duration.inMilliseconds == 0) return 0;
    return position.inMilliseconds / duration.inMilliseconds;
  }

  String get positionLabel {
    final m = position.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = position.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get durationLabel {
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }
}

// ===========================================================
// DESIGN TOKENS — ESTILO RETRÔ/CASSETE
// ===========================================================

const Color cBackground  = Color(0xFF0D0B08);  // preto quente
const Color cSurface     = Color(0xFF1A1610);  // marrom escuro
const Color cSurfaceHigh = Color(0xFF2A2218);  // marrom médio
const Color cAmber       = Color(0xFFF0A500);  // âmbar quente
const Color cSepia       = Color(0xFFC4853A);  // sépia
const Color cCream       = Color(0xFFF5E6C8);  // creme vintage
const Color cPurple      = Color(0xFF7C3AED);
const Color cSuccessGreen= Color(0xFF4A7C59);
const Color cTextPrimary = Color(0xFFF5E6C8);  // creme
const Color cTextSecondary= Color(0xFFB8976A); // sépia claro
const Color cTextMuted   = Color(0xFF6B5335);  // marrom apagado
const Color cBorder      = Color(0xFF3D2E1A);  // borda marrom

final ThemeData appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: cBackground,
  colorScheme: const ColorScheme.dark(
    primary: cAmber,
    secondary: cSepia,
    surface: cSurface,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      fontFamily: 'Courier',
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: cAmber,
      letterSpacing: 4,
    ),
    iconTheme: IconThemeData(color: cTextSecondary),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: cSurfaceHigh,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: cBorder, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: cBorder, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: cAmber, width: 1.5),
    ),
    hintStyle: const TextStyle(color: cTextMuted, fontFamily: 'Courier'),
    labelStyle: const TextStyle(color: cTextSecondary),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: cAmber,
      foregroundColor: Colors.black,
      padding: const EdgeInsets.symmetric(vertical: 15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: const BorderSide(color: Color(0xFFD4900A), width: 1),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Courier',
        fontWeight: FontWeight.bold,
        fontSize: 13,
        letterSpacing: 2,
      ),
    ),
  ),
);

// ===========================================================
// HELPERS VISUAIS
// ===========================================================

List<Color> themeGradient(String theme) {
  switch (theme) {
    case 'sunset': return [const Color(0xFF7C2D12), const Color(0xFFB45309)];
    case 'night':  return [const Color(0xFF1E1B4B), const Color(0xFF312E81)];
    case 'forest': return [const Color(0xFF052E16), const Color(0xFF14532D)];
    case 'ocean':  return [const Color(0xFF082F49), const Color(0xFF075985)];
    default:       return [const Color(0xFF1A1610), const Color(0xFF2A2218)];
  }
}

IconData themeIcon(String theme) {
  switch (theme) {
    case 'sunset': return Icons.wb_sunny_rounded;
    case 'night':  return Icons.nights_stay_rounded;
    case 'forest': return Icons.forest_rounded;
    case 'ocean':  return Icons.water_rounded;
    default:       return Icons.photo_rounded;
  }
}

String themeLabel(String theme) {
  switch (theme) {
    case 'sunset': return 'Pôr do Sol';
    case 'night':  return 'Noite';
    case 'forest': return 'Floresta';
    case 'ocean':  return 'Oceano';
    default:       return 'Foto';
  }
}

// ===========================================================
// WIDGETS RETRÔ REUTILIZÁVEIS
// ===========================================================

/// Borda pontilhada estilo fita — usada nos cards
class DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final BorderRadius borderRadius;

  const DashedBorder({
    super.key,
    required this.child,
    this.color = cBorder,
    this.strokeWidth = 1,
    this.dashWidth = 6,
    this.dashSpace = 4,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color,
        strokeWidth: strokeWidth,
        dashWidth: dashWidth,
        dashSpace: dashSpace,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final BorderRadius borderRadius;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(8),
      ));

    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        var end = distance + dashWidth;
        if (end > metric.length) end = metric.length;
        canvas.drawPath(
          metric.extractPath(distance, end),
          paint,
        );
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => false;
}

/// Textura de grain (ruído visual)
class GrainTexture extends StatelessWidget {
  final double opacity;
  const GrainTexture({super.key, this.opacity = 0.04});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(painter: _GrainPainter()),
    );
  }
}

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    // padrão simples de pontilhado para simular grain
    for (double x = 0; x < size.width; x += 4) {
      for (double y = 0; y < size.height; y += 4) {
        if ((x.toInt() + y.toInt()) % 8 == 0) {
          canvas.drawCircle(Offset(x, y), 0.5, paint);
        }
      }
    }
  }
  @override
  bool shouldRepaint(_GrainPainter old) => false;
}

/// Cassete animado
class CassetteIcon extends StatelessWidget {
  final double size;
  final Color color;
  const CassetteIcon({super.key, this.size = 40, this.color = cAmber});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.6,
      height: size,
      child: CustomPaint(painter: _CassettePainter(color)),
    );
  }
}

class _CassettePainter extends CustomPainter {
  final Color color;
  _CassettePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color.withOpacity(0.10)
      ..style = PaintingStyle.fill;

    // Corpo
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(4));
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body, stroke);

    // Segunda borda (dupla — estilo vintage)
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(3, 3, size.width - 6, size.height - 6), const Radius.circular(2));
    canvas.drawRRect(inner, Paint()..color = color.withOpacity(0.15)..style = PaintingStyle.stroke..strokeWidth = 0.5);

    // Janela
    final window = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.22, size.height * 0.18,
          size.width * 0.56, size.height * 0.58), const Radius.circular(3));
    canvas.drawRRect(window, fill);
    canvas.drawRRect(window, stroke);

    // Bobinas
    final r = size.height * 0.19;
    final cy = size.height * 0.47;
    final cx1 = size.width * 0.36;
    final cx2 = size.width * 0.64;
    for (final cx in [cx1, cx2]) {
      canvas.drawCircle(Offset(cx, cy), r, stroke);
      canvas.drawCircle(Offset(cx, cy), r * 0.55, stroke);
      canvas.drawCircle(Offset(cx, cy), r * 0.2, fill..color = color.withOpacity(0.4));
      canvas.drawCircle(Offset(cx, cy), r * 0.2, stroke);
      // raios da bobina
      for (int a = 0; a < 3; a++) {
        final angle = (a * 120) * 3.14159 / 180;
        canvas.drawLine(
          Offset(cx + (r * 0.2) * cos(angle), cy + (r * 0.2) * sin(angle)),
          Offset(cx + (r * 0.55) * cos(angle), cy + (r * 0.55) * sin(angle)),
          stroke..strokeWidth = 1.2,
        );
      }
    }

    // Fita entre bobinas
    canvas.drawLine(
      Offset(cx1 + r, cy + r * 0.6),
      Offset(size.width * 0.5, size.height * 0.88),
      stroke..strokeWidth = 1.2,
    );
    canvas.drawLine(
      Offset(cx2 - r, cy + r * 0.6),
      Offset(size.width * 0.5, size.height * 0.88),
      stroke..strokeWidth = 1.2,
    );

    // Entalhes laterais
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.28, 5, size.height * 0.35),
      Paint()..color = color.withOpacity(0.3)..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - 5, size.height * 0.28, 5, size.height * 0.35),
      Paint()..color = color.withOpacity(0.3)..style = PaintingStyle.fill,
    );

    // Label central
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.38, size.height * 0.78, size.width * 0.24, size.height * 0.14),
      Paint()..color = color.withOpacity(0.2)..style = PaintingStyle.fill,
    );
  }

  double cos(double rad) => dart_math_cos(rad);
  double sin(double rad) => dart_math_sin(rad);

  @override
  bool shouldRepaint(_CassettePainter old) => old.color != color;
}

double dart_math_cos(double x) {
  // Taylor series cos(x) — evita import de dart:math no painter
  double result = 1;
  double term = 1;
  for (int i = 1; i <= 6; i++) {
    term *= -x * x / ((2 * i - 1) * (2 * i));
    result += term;
  }
  return result;
}

double dart_math_sin(double x) {
  double result = x;
  double term = x;
  for (int i = 1; i <= 6; i++) {
    term *= -x * x / ((2 * i) * (2 * i + 1));
    result += term;
  }
  return result;
}

/// Vinyl disc
class VinylDisc extends StatefulWidget {
  final String? imageUrl;
  final bool spinning;
  final double size;
  const VinylDisc({super.key, this.imageUrl, this.spinning = false, this.size = 240});

  @override
  State<VinylDisc> createState() => _VinylDiscState();
}

class _VinylDiscState extends State<VinylDisc> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 5));
    if (widget.spinning) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(VinylDisc old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_ctrl.isAnimating) _ctrl.repeat();
    else if (!widget.spinning && _ctrl.isAnimating) _ctrl.stop();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: SizedBox(
        width: widget.size, height: widget.size,
        child: CustomPaint(painter: _VinylPainter()),
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    canvas.drawCircle(Offset(cx, cy), r,
        Paint()..color = const Color(0xFF0D0B08));

    for (double i = r * 0.3; i < r * 0.96; i += r * 0.055) {
      canvas.drawCircle(Offset(cx, cy), i,
          Paint()
            ..color = Colors.white.withOpacity(0.05)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6);
    }

    // Label vinyl (sépia)
    final labelR = r * 0.28;
    canvas.drawCircle(Offset(cx, cy), labelR,
        Paint()..color = const Color(0xFF2A1A08));
    canvas.drawCircle(Offset(cx, cy), labelR,
        Paint()
          ..color = cSepia.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    // Linhas decorativas no label (tipo rótulo vintage)
    for (double y = cy - labelR + 8; y < cy + labelR - 8; y += 6) {
      canvas.drawLine(
        Offset(cx - labelR * 0.7, y),
        Offset(cx + labelR * 0.7, y),
        Paint()..color = cSepia.withOpacity(0.06)..strokeWidth = 2,
      );
    }

    canvas.drawCircle(Offset(cx, cy), r * 0.04,
        Paint()..color = const Color(0xFF0D0B08));

    // Reflexo
    canvas.drawCircle(
      Offset(cx - r * 0.15, cy - r * 0.15),
      r * 0.25,
      Paint()
        ..color = Colors.white.withOpacity(0.03)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );
  }

  @override
  bool shouldRepaint(_VinylPainter old) => false;
}

/// Equalizador animado
class EqBars extends StatefulWidget {
  final Color color;
  final double height;
  const EqBars({super.key, this.color = cAmber, this.height = 20});

  @override
  State<EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<EqBars> with TickerProviderStateMixin {
  final List<AnimationController> _ctrls = [];

  @override
  void initState() {
    super.initState();
    final delays = [0, 120, 60, 200, 80];
    final durations = [600, 750, 550, 820, 680];
    for (int i = 0; i < 5; i++) {
      final c = AnimationController(vsync: this, duration: Duration(milliseconds: durations[i]));
      Future.delayed(Duration(milliseconds: delays[i]), () {
        if (mounted) c.repeat(reverse: true);
      });
      _ctrls.add(c);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(5, (i) => AnimatedBuilder(
        animation: _ctrls[i],
        builder: (_, __) => Container(
          width: 3,
          height: 4 + (_ctrls[i].value * (widget.height - 4)),
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      )),
    );
  }
}

/// Botão retrô com borda dupla
class RetroButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;
  const RetroButton({
    super.key,
    required this.label,
    this.onTap,
    this.color = cAmber,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(2, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de fita com estilo retrô
class TapeCard extends StatelessWidget {
  final Mixtape mixtape;
  final VoidCallback onTap;
  const TapeCard({super.key, required this.mixtape, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final grad = themeGradient(mixtape.theme);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: cBorder, width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8, offset: const Offset(3, 3)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Faixa superior colorida (tipo etiqueta de fita)
              Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: grad),
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Capa ou gradiente
                    if (mixtape.photoPath != null)
                      Image.file(File(mixtape.photoPath!), fit: BoxFit.cover)
                    else if (mixtape.tracks.isNotEmpty && mixtape.tracks.first.coverUrl.isNotEmpty)
                      CachedNetworkImage(imageUrl: mixtape.tracks.first.coverUrl, fit: BoxFit.cover)
                    else
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [grad[0].withOpacity(0.8), grad[1].withOpacity(0.4)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                    // Grain overlay
                    Positioned.fill(child: GrainTexture(opacity: 0.06)),
                    // Overlay escuro
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black.withOpacity(0.75)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    // Cassete pequeno no canto
                    Positioned(
                      top: 8, right: 8,
                      child: Opacity(opacity: 0.4, child: CassetteIcon(size: 14, color: cCream)),
                    ),
                    // Badge tracks
                    Positioned(
                      bottom: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          border: Border.all(color: cAmber.withOpacity(0.4), width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.music_note_rounded, size: 9, color: cAmber),
                            const SizedBox(width: 3),
                            Text(
                              '${mixtape.tracks.length}',
                              style: const TextStyle(
                                fontSize: 9, fontWeight: FontWeight.bold,
                                color: cCream, fontFamily: 'Courier',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Info inferior
              Container(
                color: cSurface,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mixtape.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: cCream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'para ${mixtape.recipient}',
                      style: const TextStyle(color: cTextMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================
// ROTEAMENTO
// ===========================================================

final _playerState = PlayerState();

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
    GoRoute(path: '/search', builder: (_, __) => const SearchScreen()),
    GoRoute(path: '/album/:id', builder: (_, state) => AlbumScreen(albumId: state.pathParameters['id']!)),
    GoRoute(path: '/artist/:id', builder: (_, state) => ArtistScreen(artistId: state.pathParameters['id']!)),
    GoRoute(path: '/create', builder: (_, state) => CreateMixtapeScreen(existing: state.extra as Mixtape?)),
    GoRoute(path: '/player', builder: (_, state) => PlayerScreen(mixtape: state.extra as Mixtape, playerState: _playerState)),
  ],
);

// ===========================================================
// MAIN
// ===========================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // dotenv opcional — remover se não usar
  try { await dotenv.load(fileName: '.env'); } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MixtapeApp());
}

class MixtapeApp extends StatelessWidget {
  const MixtapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Mixtape',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      routerConfig: _router,
    );
  }
}

// ===========================================================
// TELA 1: LOGIN
// ===========================================================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isNewUser = false;

  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  Future<void> _checkUser() async {
    final name = await ProfileService.getName();
    setState(() => _isNewUser = name.isEmpty);
    if (name.isNotEmpty) _nameCtrl.text = name;
  }

  Future<void> _enter() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _isLoading = true);
    await ProfileService.saveName(name);
    await StorageService.getFirstUseDate(); // registra first use
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) context.go('/dashboard');
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fundo com gradiente retrô
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.5),
                radius: 1.2,
                colors: [Color(0xFF2A1A08), Color(0xFF0D0B08)],
              ),
            ),
          ),
          // Textura de grain
          Positioned.fill(child: GrainTexture(opacity: 0.05)),
          // Linhas horizontais retrô
          Positioned.fill(
            child: CustomPaint(painter: _ScanLinesPainter()),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // Logo
                  Center(
                    child: Column(
                      children: [
                        DashedBorder(
                          color: cAmber.withOpacity(0.5),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: CassetteIcon(size: 52, color: cAmber),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'MIXTAPE',
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 12,
                            color: cAmber,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '— a trilha sonora da sua vida —',
                          style: TextStyle(
                            color: cTextMuted,
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 56),
                  // Label
                  Text(
                    _isNewUser ? 'COMO POSSO TE CHAMAR?' : 'BEM-VINDO DE VOLTA',
                    style: const TextStyle(
                      color: cTextMuted,
                      fontSize: 10,
                      fontFamily: 'Courier',
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    style: const TextStyle(
                      color: cCream,
                      fontFamily: 'Courier',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Seu nome...',
                      prefixIcon: const Icon(Icons.person_outline_rounded, size: 20, color: cTextMuted),
                      // Borda customizada âmbar
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(3),
                        borderSide: const BorderSide(color: cAmber, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _enter(),
                  ),
                  const SizedBox(height: 24),
                  // Botão entrar
                  GestureDetector(
                    onTap: _isLoading ? null : _enter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: cAmber,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: const Color(0xFFD4900A), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: cAmber.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                            : const Text(
                                'APERTAR O PLAY',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontFamily: 'Courier',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 3,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Linha decorativa
                  Row(
                    children: [
                      Expanded(child: Container(height: 0.5, color: cBorder)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: CassetteIcon(size: 10, color: cTextMuted),
                      ),
                      Expanded(child: Container(height: 0.5, color: cBorder)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Import backup
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final ok = await BackupService.importBackup(context);
                        if (ok && context.mounted) context.go('/dashboard');
                      },
                      child: Text(
                        'Restaurar backup',
                        style: TextStyle(
                          color: cTextMuted,
                          fontSize: 12,
                          fontFamily: 'Courier',
                          decoration: TextDecoration.underline,
                          decorationColor: cTextMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..strokeWidth = 0.5;
    for (double y = 0; y < size.height; y += 6) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }
  @override
  bool shouldRepaint(_ScanLinesPainter old) => false;
}

// ===========================================================
// TELA REGISTER
// ===========================================================

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CRIAR CONTA')),
      body: const Center(child: Text('Tela de Registro')),
    );
  }
}

// ===========================================================
// TELA 2: DASHBOARD
// ===========================================================

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Mixtape> _mixtapes = [];
  bool _loading = true;
  String _userName = '';

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final list = await StorageService.loadAll();
    final name = await ProfileService.getName();
    setState(() { _mixtapes = list; _userName = name; _loading = false; });
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: cSurface,
      width: 280,
      child: Stack(
        children: [
          // Grain no drawer
          Positioned.fill(child: GrainTexture(opacity: 0.04)),
          Column(
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
                decoration: BoxDecoration(
                  color: cSurfaceHigh,
                  border: Border(bottom: BorderSide(color: cBorder)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CassetteIcon(size: 28, color: cAmber),
                    const SizedBox(height: 16),
                    Text(
                      _userName.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: cCream,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_mixtapes.length} fita${_mixtapes.length != 1 ? "s" : ""} na coleção',
                      style: const TextStyle(color: cTextMuted, fontSize: 11, fontFamily: 'Courier'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _drawerSection('NAVEGAR'),
                    _drawerItem(icon: Icons.home_filled, label: 'Início', isActive: true, onTap: () => Navigator.pop(context)),
                    _drawerItem(
                      icon: Icons.fiber_manual_record_rounded,
                      label: 'Gravar Nova Fita',
                      onTap: () async { Navigator.pop(context); await context.push('/create'); _loadData(); },
                    ),
                    _drawerItem(
                      icon: Icons.search_rounded,
                      label: 'Buscar Músicas',
                      onTap: () { Navigator.pop(context); context.push('/search'); },
                    ),
                    const Divider(color: cBorder, height: 1, indent: 20, endIndent: 20),
                    _drawerSection('CONTA'),
                    _drawerItem(
                      icon: Icons.person_rounded,
                      label: 'Meu Perfil',
                      onTap: () async { Navigator.pop(context); await context.push('/profile'); _loadData(); },
                    ),
                    _drawerItem(
                      icon: Icons.upload_rounded,
                      label: 'Exportar Backup',
                      onTap: () async { Navigator.pop(context); await BackupService.exportBackup(context); },
                    ),
                    _drawerItem(
                      icon: Icons.download_rounded,
                      label: 'Importar Backup',
                      onTap: () async {
                        Navigator.pop(context);
                        final ok = await BackupService.importBackup(context);
                        if (ok) _loadData();
                      },
                    ),
                    const Divider(color: cBorder, height: 1, indent: 20, endIndent: 20),
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: cBorder)),
                ),
                child: ListTile(
                  leading: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                  title: const Text('Sair', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontFamily: 'Courier')),
                  onTap: () => context.go('/'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
    );
  }

  Widget _drawerSection(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(title, style: const TextStyle(fontSize: 9, color: cTextMuted, fontFamily: 'Courier', letterSpacing: 2, fontWeight: FontWeight.w700)),
  );

  Widget _drawerItem({required IconData icon, required String label, required VoidCallback onTap, bool isActive = false}) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: Icon(icon, size: 18, color: isActive ? cAmber : cTextSecondary),
      title: Text(label, style: TextStyle(fontSize: 13, fontFamily: 'Courier', color: isActive ? cCream : cTextSecondary, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(context),
      body: Stack(
        children: [
          Positioned.fill(child: GrainTexture(opacity: 0.03)),
          CustomScrollView(
            slivers: [
              // AppBar retrô
              SliverAppBar(
                expandedHeight: 80,
                floating: true,
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cBackground.withOpacity(0.85),
                        border: Border(bottom: BorderSide(color: cBorder, width: 0.5)),
                      ),
                      child: const FlexibleSpaceBar(
                        centerTitle: true,
                        titlePadding: EdgeInsets.only(bottom: 14),
                        title: Text(
                          'MIXTAPE',
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            color: cAmber,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                leading: Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(Icons.menu_rounded, color: cTextSecondary),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search_rounded, color: cTextSecondary),
                    onPressed: () => context.push('/search'),
                  ),
                ],
              ),

              // Saudação
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Olá, ${_userName.isEmpty ? "Ouvinte" : _userName}',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: cCream,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text('O que você está sentindo hoje?', style: TextStyle(color: cTextMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ),

              // Hero banner
              if (_mixtapes.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _HeroBanner(mixtape: _mixtapes.first),
                  ),
                ),

              // Botão Gravar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: GestureDetector(
                    onTap: () async { await context.push('/create'); _loadData(); },
                    child: DashedBorder(
                      color: cAmber.withOpacity(0.3),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        color: cSurface,
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: cAmber.withOpacity(0.15),
                                border: Border.all(color: cAmber, width: 1.5),
                              ),
                              child: const Icon(Icons.add, color: cAmber, size: 20),
                            ),
                            const SizedBox(width: 14),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Gravar Nova Fita', style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 14, color: cCream)),
                                SizedBox(height: 2),
                                Text('Compile seus sentimentos', style: TextStyle(color: cTextMuted, fontSize: 11)),
                              ],
                            ),
                            const Spacer(),
                            const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: cTextMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Seção grid
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                  child: Row(
                    children: [
                      const Text('SUAS FITAS', style: TextStyle(fontFamily: 'Courier', color: cTextMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)),
                      const Spacer(),
                      if (_mixtapes.isNotEmpty)
                        Text('${_mixtapes.length} no total', style: const TextStyle(color: cTextMuted, fontSize: 10)),
                    ],
                  ),
                ),
              ),

              if (_loading)
                const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: cAmber))))
              else if (_mixtapes.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        children: [
                          CassetteIcon(size: 40, color: cTextMuted),
                          const SizedBox(height: 16),
                          const Text('Sua prateleira está vazia.', style: TextStyle(color: cTextSecondary, fontFamily: 'Courier')),
                          const SizedBox(height: 4),
                          const Text('Grave sua primeira fita.', style: TextStyle(color: cTextMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.76,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => TapeCard(
                        mixtape: _mixtapes[i],
                        onTap: () => context.push('/player', extra: _mixtapes[i]),
                      ),
                      childCount: _mixtapes.length,
                    ),
                  ),
                ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 48)),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final Mixtape mixtape;
  const _HeroBanner({required this.mixtape});

  @override
  Widget build(BuildContext context) {
    final grad = themeGradient(mixtape.theme);
    return GestureDetector(
      onTap: () => context.push('/player', extra: mixtape),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [grad[0].withOpacity(0.9), grad[1].withOpacity(0.6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: cBorder, width: 1),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: GrainTexture(opacity: 0.06)),
            Positioned(right: -10, bottom: -10,
              child: Opacity(opacity: 0.06, child: CassetteIcon(size: 60, color: Colors.white))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CONTINUAR OUVINDO',
                    style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.5), letterSpacing: 2, fontFamily: 'Courier')),
                  const SizedBox(height: 6),
                  Text(mixtape.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Courier')),
                  Text('para ${mixtape.recipient} · ${mixtape.tracks.length} faixas',
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.5))),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 0.5),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text('Continuar', style: TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================
// TELA: BUSCA DE MÚSICAS
// ===========================================================

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  List<Track> _results = [];
  bool _loading = false;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _loading = true);
    final res = await MusicSearchService.search(q);
    setState(() { _results = res; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BUSCAR MÚSICAS')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(hintText: 'Título, artista ou álbum...', prefixIcon: Icon(Icons.search, size: 18)),
                      onSubmitted: _doSearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  RetroButton(label: 'BUSCAR', onTap: () => _doSearch(_searchCtrl.text)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: cAmber))
                  : _results.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CassetteIcon(size: 32, color: cTextMuted),
                              const SizedBox(height: 12),
                              const Text('Busque uma música para começar', style: TextStyle(color: cTextMuted, fontFamily: 'Courier', fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (c, i) {
                            final t = _results[i];
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                              decoration: BoxDecoration(
                                color: cSurface,
                                border: Border.all(color: cBorder, width: 0.5),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: CachedNetworkImage(
                                    imageUrl: t.coverUrl, width: 52, height: 52, fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(width: 52, height: 52, color: cSurfaceHigh, child: const Icon(Icons.music_note_rounded, color: cTextMuted)),
                                  ),
                                ),
                                title: Text(t.title, style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 13, color: cCream)),
                                subtitle: Text('${t.artist} · ${t.albumTitle}', style: const TextStyle(color: cTextMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.play_arrow_rounded, color: cAmber), onPressed: () async => await _playerState.play(t)),
                                    if (t.albumId != null)
                                      IconButton(icon: const Icon(Icons.album_rounded, color: cTextMuted, size: 18), onPressed: () => context.push('/album/${t.albumId}')),
                                    if (t.artistId != null)
                                      IconButton(icon: const Icon(Icons.person_rounded, color: cTextMuted, size: 18), onPressed: () => context.push('/artist/${t.artistId}')),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================
// TELA: DETALHE DO ÁLBUM
// ===========================================================

class AlbumScreen extends StatefulWidget {
  final String albumId;
  const AlbumScreen({super.key, required this.albumId});
  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  Map<String, dynamic>? _album;
  bool _loading = true;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    final a = await MusicSearchService.getAlbum(widget.albumId);
    if (mounted) setState(() { _album = a; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: cAmber)));
    if (_album == null) return Scaffold(body: Center(child: Text('Álbum não encontrado', style: TextStyle(color: cTextMuted))));

    final title = _album!['title'] as String;
    final artist = _album!['artist'] as String;
    final cover = _album!['cover'] as String;
    final tracks = _album!['tracks'] as List<Track>;

    return Scaffold(
      appBar: AppBar(title: Text(title.toUpperCase())),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            if (cover.isNotEmpty)
              ClipRRect(borderRadius: BorderRadius.circular(2),
                child: CachedNetworkImage(imageUrl: cover, width: 110, height: 110, fit: BoxFit.cover)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontFamily: 'Courier', fontSize: 16, fontWeight: FontWeight.bold, color: cCream)),
              const SizedBox(height: 4),
              Text(artist, style: const TextStyle(color: cTextSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              Text('${tracks.length} faixas', style: const TextStyle(color: cTextMuted, fontSize: 11)),
            ])),
          ]),
        ),
        Container(height: 0.5, color: cBorder, margin: const EdgeInsets.symmetric(horizontal: 16)),
        Expanded(child: ListView.builder(
          itemCount: tracks.length,
          itemBuilder: (c, i) {
            final t = tracks[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: Text('${i + 1}'.padLeft(2, '0'), style: const TextStyle(color: cAmber, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
              title: Text(t.title, style: const TextStyle(fontSize: 13, color: cCream)),
              subtitle: Text(t.artist, style: const TextStyle(color: cTextMuted, fontSize: 11)),
              trailing: IconButton(icon: const Icon(Icons.play_arrow_rounded, color: cAmber), onPressed: () async => await _playerState.play(t)),
            );
          },
        )),
      ])),
    );
  }
}

// ===========================================================
// TELA: PERFIL (dados reais, sem informações falsas)
// ===========================================================

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '';
  int _mixtapeCount = 0;
  int _totalTracks = 0;
  DateTime? _memberSince;
  bool _loading = true;

  @override
  void initState() { super.initState(); _loadProfile(); }

  Future<void> _loadProfile() async {
    final name = await ProfileService.getName();
    final mix = await StorageService.loadAll();
    final firstUse = await StorageService.getFirstUseDate();
    final total = mix.fold<int>(0, (sum, m) => sum + m.tracks.length);
    setState(() {
      _name = name;
      _mixtapeCount = mix.length;
      _totalTracks = total;
      _memberSince = firstUse;
      _loading = false;
    });
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _name);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: const BorderSide(color: cBorder)),
        title: const Text('Editar Nome', style: TextStyle(fontFamily: 'Courier', fontSize: 15, color: cCream)),
        content: TextField(controller: ctrl, autofocus: true,
          style: const TextStyle(fontFamily: 'Courier', color: cCream),
          decoration: const InputDecoration(hintText: 'Seu nome...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: cTextMuted))),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                await ProfileService.saveName(ctrl.text.trim());
                setState(() => _name = ctrl.text.trim());
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MEU PERFIL')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: cAmber))
          : Stack(
              children: [
                Positioned.fill(child: GrainTexture(opacity: 0.03)),
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Card de perfil estilo vinil
                      DashedBorder(
                        color: cBorder,
                        child: Container(
                          width: double.infinity,
                          color: cSurface,
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              // Avatar com cassete
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    width: 88, height: 88,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: cSurfaceHigh,
                                      border: Border.all(color: cAmber, width: 2),
                                    ),
                                    child: const Icon(Icons.person_rounded, size: 44, color: cTextMuted),
                                  ),
                                  GestureDetector(
                                    onTap: _editName,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: cAmber, border: Border.all(color: cBackground, width: 2)),
                                      child: const Icon(Icons.edit_rounded, size: 13, color: Colors.black),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              GestureDetector(
                                onTap: _editName,
                                child: Text(_name, style: const TextStyle(fontFamily: 'Courier', fontSize: 22, fontWeight: FontWeight.bold, color: cCream)),
                              ),
                              const SizedBox(height: 4),
                              Text('Membro desde ${_formatDate(_memberSince)}',
                                style: const TextStyle(color: cTextMuted, fontSize: 11)),
                              const SizedBox(height: 24),
                              // Stats reais
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildStat('$_mixtapeCount', 'Fitas'),
                                  Container(height: 36, width: 0.5, color: cBorder),
                                  _buildStat('$_totalTracks', 'Faixas'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Ações
                      _actionCard(
                        icon: Icons.upload_rounded,
                        title: 'Exportar Backup',
                        subtitle: 'Salvar todas as suas fitas em JSON',
                        onTap: () => BackupService.exportBackup(context),
                      ),
                      const SizedBox(height: 8),
                      _actionCard(
                        icon: Icons.download_rounded,
                        title: 'Importar Backup',
                        subtitle: 'Restaurar fitas de um arquivo JSON',
                        onTap: () async {
                          final ok = await BackupService.importBackup(context);
                          if (ok) _loadProfile();
                        },
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent, width: 0.8),
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                          textStyle: const TextStyle(fontFamily: 'Courier'),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Sair'),
                        onPressed: () => context.go('/'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStat(String value, String label) => Column(children: [
    Text(value, style: const TextStyle(fontFamily: 'Courier', fontSize: 24, fontWeight: FontWeight.bold, color: cAmber)),
    const SizedBox(height: 3),
    Text(label, style: const TextStyle(fontSize: 11, color: cTextMuted, letterSpacing: 0.5)),
  ]);

  Widget _actionCard({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cSurface, border: Border.all(color: cBorder, width: 0.5)),
        child: Row(children: [
          Icon(icon, color: cAmber, size: 20),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: 'Courier', fontSize: 13, color: cCream, fontWeight: FontWeight.bold)),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: cTextMuted)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: cTextMuted),
        ]),
      ),
    );
  }
}

// ===========================================================
// TELA 3: CRIAR MIXTAPE
// ===========================================================

class CreateMixtapeScreen extends StatefulWidget {
  final Mixtape? existing;
  const CreateMixtapeScreen({super.key, this.existing});
  @override
  State<CreateMixtapeScreen> createState() => _CreateMixtapeScreenState();
}

class _CreateMixtapeScreenState extends State<CreateMixtapeScreen> {
  final _titleCtrl = TextEditingController();
  final _recipientCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  List<Track> _selectedTracks = [];
  List<Track> _searchResults = [];
  bool _searching = false;
  String _theme = 'sunset';
  bool _saving = false;

  final _themes = ['sunset', 'night', 'forest', 'ocean'];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final m = widget.existing!;
      _titleCtrl.text = m.title;
      _recipientCtrl.text = m.recipient;
      _messageCtrl.text = m.openingMessage;
      _selectedTracks = List.from(m.tracks);
      _theme = m.theme;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _recipientCtrl.dispose();
    _messageCtrl.dispose(); _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _searching = true);
    final results = await MusicSearchService.search(q);
    setState(() { _searchResults = results; _searching = false; });
  }

  Future<void> _save() async {
    if (_titleCtrl.text.isEmpty || _selectedTracks.isEmpty) return;
    setState(() => _saving = true);
    final m = Mixtape(
      id: widget.existing?.id ?? const Uuid().v4(),
      title: _titleCtrl.text.trim(),
      recipient: _recipientCtrl.text.trim(),
      openingMessage: _messageCtrl.text.trim(),
      tracks: _selectedTracks,
      theme: _theme,
      createdAt: DateTime.now(),
    );
    if (widget.existing != null) await StorageService.delete(widget.existing!.id);
    await StorageService.add(m);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null ? 'EDITAR FITA' : 'GRAVAR FITA'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('SALVAR', style: TextStyle(color: cAmber, fontFamily: 'Courier', fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: GrainTexture(opacity: 0.03)),
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _label('TÍTULO DA FITA'),
              const SizedBox(height: 6),
              TextField(controller: _titleCtrl, style: const TextStyle(fontFamily: 'Courier', color: cCream),
                decoration: const InputDecoration(hintText: 'ex: Chuva de Novembro')),
              const SizedBox(height: 14),
              _label('PARA QUEM?'),
              const SizedBox(height: 6),
              TextField(controller: _recipientCtrl, style: const TextStyle(fontFamily: 'Courier', color: cCream),
                decoration: const InputDecoration(hintText: 'Nome do destinatário')),
              const SizedBox(height: 14),
              _label('MENSAGEM DE ABERTURA'),
              const SizedBox(height: 6),
              TextField(controller: _messageCtrl, maxLines: 3, style: const TextStyle(fontFamily: 'Courier', color: cCream, fontSize: 13),
                decoration: const InputDecoration(hintText: 'Escreva algo especial...')),

              // Tema
              const SizedBox(height: 24),
              _label('TEMA DA FITA'),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _themes.map((t) {
                    final selected = _theme == t;
                    final grad = themeGradient(t);
                    return GestureDetector(
                      onTap: () => setState(() => _theme = t),
                      child: Container(
                        width: 80, height: 54,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
                          border: Border.all(color: selected ? cAmber : cBorder, width: selected ? 2 : 1),
                        ),
                        child: Stack(
                          children: [
                            if (selected) Positioned.fill(child: GrainTexture(opacity: 0.1)),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(themeIcon(t), size: 18, color: Colors.white),
                                const SizedBox(height: 4),
                                Text(themeLabel(t), style: const TextStyle(fontSize: 9, color: Colors.white, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // Busca
              const SizedBox(height: 24),
              _label('ADICIONAR MÚSICAS'),
              const SizedBox(height: 8),
              TextField(
                controller: _searchCtrl,
                onSubmitted: _search,
                style: const TextStyle(fontFamily: 'Courier', color: cCream),
                decoration: InputDecoration(
                  hintText: 'Buscar por título ou artista...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: _searching
                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: cAmber))
                      : IconButton(icon: const Icon(Icons.search_rounded, size: 18), onPressed: () => _search(_searchCtrl.text)),
                ),
              ),

              // Resultados
              if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 10),
                ..._searchResults.take(8).map((t) => Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(color: cSurface, border: Border.all(color: cBorder, width: 0.5)),
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: CachedNetworkImage(imageUrl: t.coverUrl, width: 40, height: 40, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(width: 40, height: 40, color: cSurfaceHigh, child: const Icon(Icons.music_note_rounded, color: cTextMuted, size: 16))),
                    ),
                    title: Text(t.title, style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: cCream, fontWeight: FontWeight.bold)),
                    subtitle: Text(t.artist, style: const TextStyle(color: cTextMuted, fontSize: 10), maxLines: 1),
                    trailing: IconButton(
                      icon: Icon(
                        _selectedTracks.any((s) => s.id == t.id) ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                        color: _selectedTracks.any((s) => s.id == t.id) ? cSuccessGreen : cAmber,
                        size: 20,
                      ),
                      onPressed: () => setState(() {
                        if (!_selectedTracks.any((s) => s.id == t.id) && _selectedTracks.length < 12) {
                          _selectedTracks.add(t);
                        }
                      }),
                    ),
                  ),
                )),
              ],

              // Tracklist
              const SizedBox(height: 24),
              Row(children: [
                Text('LADO A — ${_selectedTracks.length}/12',
                  style: const TextStyle(fontFamily: 'Courier', color: cAmber, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2)),
                const Spacer(),
                if (_selectedTracks.isNotEmpty) CassetteIcon(size: 12, color: cAmber),
              ]),
              const SizedBox(height: 8),
              Container(height: 0.5, color: cAmber.withOpacity(0.3)),
              const SizedBox(height: 8),
              if (_selectedTracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text('Adicione músicas acima', style: TextStyle(color: cTextMuted.withOpacity(0.5), fontSize: 12, fontFamily: 'Courier'))),
                )
              else
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final item = _selectedTracks.removeAt(oldIndex);
                      _selectedTracks.insert(newIndex, item);
                    });
                  },
                  children: _selectedTracks.asMap().entries.map((e) => Container(
                    key: ValueKey(e.value.id),
                    margin: const EdgeInsets.only(bottom: 2),
                    decoration: BoxDecoration(color: cSurface, border: Border.all(color: cBorder, width: 0.5)),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      leading: SizedBox(width: 24, child: Center(child: Text('${e.key + 1}'.padLeft(2, '0'), style: const TextStyle(color: cAmber, fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 12)))),
                      title: Text(e.value.title, style: const TextStyle(fontSize: 13, color: cCream)),
                      subtitle: Text(e.value.artist, style: const TextStyle(color: cTextMuted, fontSize: 11)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.drag_handle_rounded, color: cTextMuted, size: 18),
                        IconButton(icon: const Icon(Icons.close_rounded, color: cTextMuted, size: 16), onPressed: () => setState(() => _selectedTracks.removeAt(e.key))),
                      ]),
                    ),
                  )).toList(),
                ),

              const SizedBox(height: 28),
              GestureDetector(
                onTap: (_saving || _titleCtrl.text.isEmpty || _selectedTracks.isEmpty) ? null : _save,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: (_saving || _titleCtrl.text.isEmpty || _selectedTracks.isEmpty) ? cTextMuted.withOpacity(0.3) : cAmber,
                    border: Border.all(color: cBorder),
                  ),
                  child: Center(child: _saving
                    ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 2)
                    : const Text('FINALIZAR GRAVAÇÃO', style: TextStyle(color: Colors.black, fontFamily: 'Courier', fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 13)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text, style: const TextStyle(fontFamily: 'Courier', color: cTextMuted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 2));
}

// ===========================================================
// TELA 4: PLAYER
// ===========================================================

class PlayerScreen extends StatefulWidget {
  final Mixtape mixtape;
  final PlayerState playerState;
  const PlayerScreen({super.key, required this.mixtape, required this.playerState});
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  int _currentIndex = 0;
  bool _showNoteEditor = false;
  final _noteCtrl = TextEditingController();

  @override
  void initState() { super.initState(); widget.playerState.addListener(_rebuild); }
  void _rebuild() => setState(() {});
  @override
  void dispose() { widget.playerState.removeListener(_rebuild); widget.playerState.stop(); _noteCtrl.dispose(); super.dispose(); }

  Future<void> _play() async => widget.playerState.play(widget.mixtape.tracks[_currentIndex]);
  void _next() { if (_currentIndex < widget.mixtape.tracks.length - 1) { setState(() => _currentIndex++); _play(); } }
  void _prev() { if (_currentIndex > 0) { setState(() => _currentIndex--); _play(); } }

  @override
  Widget build(BuildContext context) {
    if (widget.mixtape.tracks.isEmpty) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Fita vazia')));
    }

    final t = widget.mixtape.tracks[_currentIndex];
    final ps = widget.playerState;
    final grad = themeGradient(widget.mixtape.theme);

    return Scaffold(
      body: Stack(
        children: [
          // Fundo com gradiente do tema
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [grad[0].withOpacity(0.8), cBackground],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.55],
              ),
            ),
          ),
          Positioned.fill(child: GrainTexture(opacity: 0.05)),
          Positioned.fill(child: CustomPaint(painter: _ScanLinesPainter())),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: cTextSecondary),
                        onPressed: () => context.pop(),
                      ),
                      Expanded(child: Column(children: [
                        Text('TOCANDO DE', style: TextStyle(fontSize: 9, color: cTextMuted, letterSpacing: 2, fontFamily: 'Courier')),
                        const SizedBox(height: 2),
                        Text(widget.mixtape.title, style: const TextStyle(fontFamily: 'Courier', fontSize: 13, fontWeight: FontWeight.bold, color: cCream)),
                      ])),
                      // Exportar PDF
                      IconButton(
                        icon: const Icon(Icons.picture_as_pdf_rounded, color: cTextSecondary, size: 20),
                        onPressed: () => MixtapePdfService.shareAsPdf(context, widget.mixtape),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: [
                    Text('para ', style: TextStyle(fontSize: 10, color: cTextMuted.withOpacity(0.7))),
                    Text(widget.mixtape.recipient, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cTextSecondary, fontFamily: 'Courier')),
                    const Spacer(),
                    Text('${_currentIndex + 1} de ${widget.mixtape.tracks.length}', style: const TextStyle(fontSize: 10, color: cTextMuted, fontFamily: 'Courier')),
                  ]),
                ),

                const SizedBox(height: 12),

                // Disco de vinil
                Expanded(
                  child: Center(
                    child: VinylDisc(
                      imageUrl: t.coverUrl,
                      spinning: ps.isPlaying,
                      size: MediaQuery.of(context).size.width * 0.62,
                    ),
                  ),
                ),

                // Info da faixa
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.title, style: const TextStyle(fontFamily: 'Courier', fontSize: 19, fontWeight: FontWeight.bold, color: cCream), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text(t.artist, style: const TextStyle(color: cTextSecondary, fontSize: 13)),
                    ])),
                    if (ps.isPlaying) const Padding(padding: EdgeInsets.only(left: 12), child: EqBars(height: 20)),
                  ]),
                ),

                // Nota pessoal
                if (t.personalNote.isNotEmpty || _showNoteEditor)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: DashedBorder(
                      color: cAmber.withOpacity(0.3),
                      child: Container(
                        color: cAmber.withOpacity(0.04),
                        padding: const EdgeInsets.all(10),
                        child: _showNoteEditor
                            ? TextField(
                                controller: _noteCtrl,
                                style: const TextStyle(fontSize: 12, color: cTextSecondary, fontFamily: 'Courier'),
                                decoration: const InputDecoration(hintText: 'Escreva uma nota...', border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                                onSubmitted: (v) { setState(() { t.personalNote = v; _showNoteEditor = false; }); },
                              )
                            : Row(children: [
                                const Icon(Icons.format_quote_rounded, size: 13, color: cAmber),
                                const SizedBox(width: 8),
                                Expanded(child: Text(t.personalNote, style: const TextStyle(fontSize: 11, color: cTextSecondary, fontStyle: FontStyle.italic, fontFamily: 'Courier'))),
                              ]),
                      ),
                    ),
                  ),

                // Progress
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Column(children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: cAmber,
                        inactiveTrackColor: cSurfaceHigh,
                        thumbColor: cAmber,
                        overlayColor: cAmber.withOpacity(0.2),
                      ),
                      child: Slider(value: ps.progress, onChanged: (_) {}),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(ps.positionLabel, style: const TextStyle(fontSize: 10, color: cTextMuted, fontFamily: 'Courier')),
                        Text(ps.durationLabel, style: const TextStyle(fontSize: 10, color: cTextMuted, fontFamily: 'Courier')),
                      ]),
                    ),
                  ]),
                ),

                // Controles
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(icon: const Icon(Icons.shuffle_rounded, color: cTextMuted, size: 20), onPressed: () {}),
                      IconButton(icon: const Icon(Icons.skip_previous_rounded, color: cCream, size: 34), onPressed: _currentIndex > 0 ? _prev : null),
                      // Botão play retrô
                      GestureDetector(
                        onTap: () {
                          if (ps.currentTrack?.id != t.id) _play();
                          else ps.togglePlayPause();
                        },
                        child: Container(
                          width: 66, height: 66,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: cAmber,
                            border: Border.all(color: const Color(0xFFD4900A), width: 2),
                            boxShadow: [BoxShadow(color: cAmber.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)],
                          ),
                          child: Icon(ps.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 34, color: Colors.black),
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.skip_next_rounded, color: cCream, size: 34), onPressed: _currentIndex < widget.mixtape.tracks.length - 1 ? _next : null),
                      IconButton(icon: const Icon(Icons.repeat_rounded, color: cTextMuted, size: 20), onPressed: () {}),
                    ],
                  ),
                ),

                // Ações secundárias
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _actionBtn(Icons.favorite_border_rounded, 'Curtir', () {}),
                      _actionBtn(Icons.edit_note_rounded, 'Nota', () {
                        setState(() { _noteCtrl.text = t.personalNote; _showNoteEditor = !_showNoteEditor; });
                      }),
                      _actionBtn(Icons.picture_as_pdf_rounded, 'PDF', () => MixtapePdfService.shareAsPdf(context, widget.mixtape)),
                      _actionBtn(Icons.share_rounded, 'Enviar', () => MixtapePdfService.shareAsPdf(context, widget.mixtape)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Icon(icon, color: cTextMuted, size: 20),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 9, color: cTextMuted, fontFamily: 'Courier', letterSpacing: 0.5)),
      ]),
    );
  }
}

// ===========================================================
// TELA: ARTISTA
// ===========================================================

class ArtistScreen extends StatefulWidget {
  final String artistId;
  const ArtistScreen({super.key, required this.artistId});
  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  Map<String, dynamic>? _artist;
  List<Track> _top = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    final a = await MusicSearchService.getArtist(widget.artistId);
    final top = await MusicSearchService.getArtistTop(widget.artistId, limit: 20);
    if (mounted) setState(() { _artist = a; _top = top; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: cAmber)));
    if (_artist == null) return Scaffold(body: Center(child: Text('Artista não encontrado', style: TextStyle(color: cTextMuted))));

    final name = _artist!['name'] as String;
    final genre = _artist!['genre'] as String;

    return Scaffold(
      appBar: AppBar(title: Text(name.toUpperCase())),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cSurfaceHigh, border: Border.all(color: cAmber, width: 1.5)),
              child: const Icon(Icons.person_rounded, size: 40, color: cTextMuted),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontFamily: 'Courier', fontSize: 18, fontWeight: FontWeight.bold, color: cCream)),
              if (genre.isNotEmpty) Text(genre, style: const TextStyle(color: cTextMuted, fontSize: 12)),
              Text('${_top.length} músicas', style: const TextStyle(color: cTextMuted, fontSize: 11)),
            ])),
          ]),
        ),
        Container(height: 0.5, color: cBorder, margin: const EdgeInsets.symmetric(horizontal: 16)),
        Expanded(child: ListView.builder(
          itemCount: _top.length,
          itemBuilder: (c, i) {
            final t = _top[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: ClipRRect(borderRadius: BorderRadius.circular(2),
                child: CachedNetworkImage(imageUrl: t.coverUrl, width: 52, height: 52, fit: BoxFit.cover)),
              title: Text(t.title, style: const TextStyle(color: cCream, fontSize: 13)),
              subtitle: Text(t.albumTitle, style: const TextStyle(color: cTextMuted, fontSize: 11)),
              trailing: IconButton(icon: const Icon(Icons.play_arrow_rounded, color: cAmber), onPressed: () async => await _playerState.play(t)),
            );
          },
        )),
      ])),
    );
  }
}