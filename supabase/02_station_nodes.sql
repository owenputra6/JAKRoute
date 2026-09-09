-- JAKRoute / Supabase
-- Jalankan file ini SETELAH 01_station_blocks.sql.
-- Sumber: Titik Titik Penghubung LT 2.geojson
-- Hasil: 20 point. Titik 19-20 menjadi batas tengah koridor crowd selebar 2 meter.
-- Simulator backend nanti membuat 100 posisi dummy di dalam koridor ini.
-- Nilai crowd tetap berupa bobot numerik per pengguna; tidak memakai label low/medium/high.
-- Skrip aman dijalankan ulang dan tidak menghapus tabel lama.

begin;

create schema if not exists extensions;
create extension if not exists postgis with schema extensions;

create table if not exists public.station_nodes (
  id text primary key,
  station_id text not null,
  floor smallint not null,
  source_no smallint not null,
  name text not null,
  node_type text not null,
  linked_block_id text null
    references public.station_blocks(id)
    on update cascade
    on delete set null,
  is_routable boolean not null default true,
  geom extensions.geometry(Point, 4326) not null,
  crowd_zone_id text null,
  crowd_sequence smallint null,
  crowd_width_m numeric(6,2) null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint station_nodes_source_unique unique (station_id, floor, source_no),
  constraint station_nodes_floor_check check (floor >= 0),
  constraint station_nodes_type_check check (
    node_type in (
      'connector_access',
      'entrance_access',
      'facility_entrance',
      'destination',
      'crowd_boundary'
    )
  ),
  constraint station_nodes_crowd_sequence_check check (
    crowd_sequence is null or crowd_sequence between 1 and 2
  ),
  constraint station_nodes_crowd_width_check check (
    crowd_width_m is null or crowd_width_m > 0
  ),
  constraint station_nodes_crowd_fields_check check (
    (
      crowd_zone_id is null
      and crowd_sequence is null
      and crowd_width_m is null
    )
    or
    (
      crowd_zone_id is not null
      and crowd_sequence is not null
      and crowd_width_m is not null
    )
  )
);

create index if not exists station_nodes_geom_gix
  on public.station_nodes using gist (geom);

create index if not exists station_nodes_station_floor_idx
  on public.station_nodes (station_id, floor);

create index if not exists station_nodes_crowd_zone_idx
  on public.station_nodes (crowd_zone_id, crowd_sequence)
  where crowd_zone_id is not null;

alter table public.station_nodes enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.station_nodes to anon, authenticated;

drop policy if exists station_nodes_public_read on public.station_nodes;
create policy station_nodes_public_read
  on public.station_nodes
  for select
  to anon, authenticated
  using (true);

insert into public.station_nodes (
  id, station_id, floor, source_no, name, node_type,
  linked_block_id, is_routable, geom,
  crowd_zone_id, crowd_sequence, crowd_width_m, metadata
)
values
  ('palmerah_lt2_node_001', 'palmerah', 2, 1, 'Lift Peron 1', 'connector_access', 'palmerah_lt2_block_001', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.7972025226635,-6.20769306662541],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":1,"source_property":"Access To","source_value":"Lift Peron 1","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_002', 'palmerah', 2, 2, 'Lift Peron 2', 'connector_access', 'palmerah_lt2_block_002', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79739741216662,-6.207779279536837],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":2,"source_property":"Access To","source_value":"Lift Peron 2","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_003', 'palmerah', 2, 3, 'Eskalator Peron 1.1', 'connector_access', 'palmerah_lt2_block_003', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79728495622027,-6.207529749356823],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":3,"source_property":"Access To","source_value":"Eskalator Peron 1.1","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_004', 'palmerah', 2, 4, 'Eskalator Peron 2.2', 'connector_access', 'palmerah_lt2_block_004', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79746098577397,-6.207615556653764],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":4,"source_property":"Access To","source_value":"Eskalator Peron 2.2","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_005', 'palmerah', 2, 5, 'Tangga Peron 1.1', 'connector_access', 'palmerah_lt2_block_021', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79743076706302,-6.207210668468278],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":5,"source_property":"Access To","source_value":"Tangga Peron 1.1","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_006', 'palmerah', 2, 6, 'Tangga Peron 1.2', 'connector_access', 'palmerah_lt2_block_021', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79745260789002,-6.207220541648155],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":6,"source_property":"Access To","source_value":"Tangga Peron 1.2","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_007', 'palmerah', 2, 7, 'Tangga Peron 2.1', 'connector_access', 'palmerah_lt2_block_020', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79759747082608,-6.207283886724412],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":7,"source_property":"Access To","source_value":"Tangga Peron 2.1","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_008', 'palmerah', 2, 8, 'Tangga Peron 2.2', 'connector_access', 'palmerah_lt2_block_020', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79761706054609,-6.207294054106811],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":8,"source_property":"Access To","source_value":"Tangga Peron 2.2","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_009', 'palmerah', 2, 9, 'EntryExit1', 'entrance_access', 'palmerah_lt2_block_011', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.7970826624661,-6.2079270889352784],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":9,"source_property":"Access To","source_value":"EntryExit1","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_010', 'palmerah', 2, 10, 'EntryExit2', 'entrance_access', 'palmerah_lt2_block_012', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79729625882214,-6.208023759074621],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":10,"source_property":"Access To","source_value":"EntryExit2","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_011', 'palmerah', 2, 11, 'Pintu Masuk P3K', 'facility_entrance', 'palmerah_lt2_block_015', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79756956056474,-6.207021976002494],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":11,"source_property":"Access To","source_value":"Pintu Masuk P3K","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_012', 'palmerah', 2, 12, 'Pintu Masuk Toilet Pria', 'facility_entrance', 'palmerah_lt2_block_014', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.7975415288405,-6.207082644159186],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":12,"source_property":"Access To","source_value":"Pintu Masuk Toilet Pria","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_013', 'palmerah', 2, 13, 'Pintu Masuk Musala Pria', 'facility_entrance', 'palmerah_lt2_block_013', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79753757630215,-6.2070907523502825],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":13,"source_property":"Access To","source_value":"Pintu Masuk Musala Pria","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_014', 'palmerah', 2, 14, 'Pintu Masuk Ruang Laktasi', 'facility_entrance', 'palmerah_lt2_block_016', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79769946009503,-6.207047865302627],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":14,"source_property":"Access To","source_value":"Pintu Masuk Ruang Laktasi","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_015', 'palmerah', 2, 15, 'Pintu Masuk Toilet Difabel', 'facility_entrance', 'palmerah_lt2_block_017', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.7976966921716,-6.207053756171732],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":15,"source_property":"Access To","source_value":"Pintu Masuk Toilet Difabel","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_016', 'palmerah', 2, 16, 'Pintu Masuk Toilet Wanita', 'facility_entrance', 'palmerah_lt2_block_018', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79766215128308,-6.207122087067688],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":16,"source_property":"Access To","source_value":"Pintu Masuk Toilet Wanita","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_017', 'palmerah', 2, 17, 'Pintu Masuk Musala Wanita', 'facility_entrance', 'palmerah_lt2_block_019', true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79765853759784,-6.207129100925528],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":17,"source_property":"Access To","source_value":"Pintu Masuk Musala Wanita","link_method":"reviewed_name_match"}'::jsonb),
  ('palmerah_lt2_node_018', 'palmerah', 2, 18, 'Vending Machine 1', 'destination', null, true, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79758215895305,-6.207242574075124],"type":"Point"}'), 4326), null, null, null, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":18,"source_property":"Access To","source_value":"Vending Machine 1","link_method":null}'::jsonb),
  ('palmerah_lt2_node_019', 'palmerah', 2, 19, 'Koridor Crowd 01 — Start', 'crowd_boundary', null, false, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79746152248532,-6.207399080319959],"type":"Point"}'), 4326), 'crowd_corridor_01', 1, 2.00, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":19,"source_property":"Access To","source_value":null,"link_method":null}'::jsonb),
  ('palmerah_lt2_node_020', 'palmerah', 2, 20, 'Koridor Crowd 01 — End', 'crowd_boundary', null, false, extensions.ST_SetSRID(extensions.ST_GeomFromGeoJSON('{"coordinates":[106.79760183449002,-6.207103818662631],"type":"Point"}'), 4326), 'crowd_corridor_01', 2, 2.00, '{"source_file":"Titik Titik Penghubung LT 2.geojson","source_feature_no":20,"source_property":"Access To","source_value":null,"link_method":null}'::jsonb)
on conflict (id) do update set
  station_id = excluded.station_id,
  floor = excluded.floor,
  source_no = excluded.source_no,
  name = excluded.name,
  node_type = excluded.node_type,
  linked_block_id = excluded.linked_block_id,
  is_routable = excluded.is_routable,
  geom = excluded.geom,
  crowd_zone_id = excluded.crowd_zone_id,
  crowd_sequence = excluded.crowd_sequence,
  crowd_width_m = excluded.crowd_width_m,
  metadata = excluded.metadata,
  updated_at = now();

do $$
declare
  imported_count integer;
  crowd_point_count integer;
begin
  select count(*) into imported_count
  from public.station_nodes
  where station_id = 'palmerah'
    and floor = 2
    and id like 'palmerah_lt2_node_%';

  if imported_count <> 20 then
    raise exception 'Import station_nodes tidak lengkap: ditemukan %, seharusnya 20.', imported_count;
  end if;

  select count(*) into crowd_point_count
  from public.station_nodes
  where station_id = 'palmerah'
    and floor = 2
    and crowd_zone_id = 'crowd_corridor_01';

  if crowd_point_count <> 2 then
    raise exception 'Koridor crowd membutuhkan tepat 2 titik; ditemukan %.', crowd_point_count;
  end if;

  if exists (
    select 1
    from public.station_nodes
    where station_id = 'palmerah'
      and floor = 2
      and id like 'palmerah_lt2_node_%'
      and extensions.ST_SRID(geom) <> 4326
  ) then
    raise exception 'Ada geometry station_nodes dengan SRID selain 4326.';
  end if;
end
$$;

commit;

-- Cek cepat setelah selesai:
select
  count(*) as jumlah_node,
  count(*) filter (where is_routable) as node_routing,
  count(*) filter (where crowd_zone_id = 'crowd_corridor_01') as titik_koridor_crowd
from public.station_nodes
where station_id = 'palmerah' and floor = 2;

-- Lihat garis koridor crowd titik 19 -> 20 dan panjangnya:
select
  crowd_zone_id,
  extensions.ST_AsGeoJSON(
    extensions.ST_MakeLine(geom order by crowd_sequence)
  )::jsonb as corridor_geojson,
  round(
    extensions.ST_Length(
      extensions.ST_MakeLine(geom order by crowd_sequence)::extensions.geography
    )::numeric,
    2
  ) as corridor_length_m,
  max(crowd_width_m) as corridor_width_m
from public.station_nodes
where crowd_zone_id = 'crowd_corridor_01'
group by crowd_zone_id;
