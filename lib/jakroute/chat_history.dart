import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

/// One saved conversation, listed in the Riwayat drawer.
class ChatSessionSummary {
  ChatSessionSummary({required this.id, required this.title, required this.updatedAt});
  final String id;
  final String title;
  final DateTime updatedAt;
}

/// Chat history per Supabase account (anonymous demo sessions included —
/// each anonymous sign-in has its own real `auth.uid()`, so it is still
/// "per account"). Table: `chat_sessions` (see supabase/03_chat_history.sql).
/// Every call is best-effort: if the table doesn't exist yet, the user is
/// signed out, or the network drops, chat keeps working without history —
/// nothing here ever blocks or throws into the UI.
class ChatHistoryStore {
  ChatHistoryStore._();
  static final instance = ChatHistoryStore._();

  SupabaseClient? get _db {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String? get _uid => _db?.auth.currentSession?.user.id;

  Future<List<ChatSessionSummary>> listSessions() async {
    final db = _db, uid = _uid;
    if (db == null || uid == null) return [];
    try {
      final rows = await db
          .from('chat_sessions')
          .select('id,title,updated_at')
          .eq('user_id', uid)
          .order('updated_at', ascending: false)
          .limit(50);
      return (rows as List)
          .map((r) => ChatSessionSummary(
                id: r['id'] as String,
                title: (r['title'] as String?)?.trim().isNotEmpty == true ? r['title'] as String : 'Percakapan',
                updatedAt: DateTime.parse(r['updated_at'] as String),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Json>> loadMessages(String sessionId) async {
    final db = _db;
    if (db == null) return [];
    try {
      final row = await db.from('chat_sessions').select('messages').eq('id', sessionId).maybeSingle();
      return ((row?['messages'] as List?) ?? []).cast<Json>();
    } catch (_) {
      return [];
    }
  }

  /// Creates the session on first save (returns its new id), otherwise
  /// updates it in place. Returns the (possibly unchanged) session id, or
  /// null if it could not be saved — callers just keep the prior id then.
  Future<String?> save({required String? sessionId, required String title, required List<Json> messages}) async {
    final db = _db, uid = _uid;
    if (db == null || uid == null) return sessionId;
    try {
      if (sessionId == null) {
        final row = await db
            .from('chat_sessions')
            .insert({'user_id': uid, 'title': title, 'messages': messages})
            .select('id')
            .single();
        return row['id'] as String;
      }
      await db.from('chat_sessions').update({
        'title': title,
        'messages': messages,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', sessionId);
      return sessionId;
    } catch (_) {
      return sessionId;
    }
  }

  Future<void> deleteSession(String id) async {
    final db = _db;
    if (db == null) return;
    try {
      await db.from('chat_sessions').delete().eq('id', id);
    } catch (_) {}
  }
}
