-- JAKRoute / Supabase
-- Jalankan file ini lewat Supabase SQL Editor, kapan saja setelah 01/02.
-- Riwayat percakapan Tanya AI, per akun (termasuk sesi anonim/demo — setiap
-- login anonim punya auth.uid() sendiri, jadi tetap "per akun").
-- Seluruh isi percakapan (pesan user + jawaban AI mentah) disimpan sebagai
-- satu kolom jsonb per sesi; tidak ada tabel pesan terpisah, cukup untuk
-- kebutuhan riwayat chat.
-- Skrip aman dijalankan ulang; tabel lama tidak dihapus.

begin;

create table if not exists public.chat_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Percakapan baru',
  messages jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists chat_sessions_user_idx
  on public.chat_sessions (user_id, updated_at desc);

alter table public.chat_sessions enable row level security;

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.chat_sessions to authenticated;

drop policy if exists chat_sessions_owner_rw on public.chat_sessions;
create policy chat_sessions_owner_rw
  on public.chat_sessions
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

commit;
