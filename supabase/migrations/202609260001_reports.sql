begin;

-- Existing prototype data stays untouched and is no longer publicly readable.
do $$ begin
  if to_regclass('public.reportes') is not null then
    execute 'alter table public.reportes enable row level security';
    execute 'revoke all on public.reportes from anon, authenticated';
  end if;
end $$;

create table public.alertx_reports (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  created_at timestamptz not null default now(),
  latitud double precision not null check (latitud between -90 and 90),
  longitud double precision not null check (longitud between -180 and 180),
  precision_metros double precision check (precision_metros between 0 and 100000),
  descripcion text not null check (char_length(btrim(descripcion)) between 15 and 2000),
  tipo text not null check (tipo in ('colision', 'obstruccion', 'riesgo_vial', 'otro')),
  estado text not null default 'recibido' check (estado in ('recibido', 'en_revision', 'cerrado')),
  unique (usuario_id, request_id)
);
create index alertx_reports_user_created on public.alertx_reports(usuario_id, created_at desc, id desc);
alter table public.alertx_reports enable row level security;
revoke all on public.alertx_reports from anon, authenticated;
grant select on public.alertx_reports to authenticated;
create policy "Read own reports" on public.alertx_reports for select to authenticated
  using ((select auth.uid()) = usuario_id and coalesce((select auth.jwt()) ->> 'is_anonymous', 'false') = 'false');

create function public.alertx_create_report(
  p_request_id uuid, p_latitud double precision, p_longitud double precision,
  p_descripcion text, p_tipo text, p_precision_metros double precision default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_report public.alertx_reports;
begin
  if v_user is null or coalesce(auth.jwt() ->> 'is_anonymous', 'false') = 'true' then
    raise insufficient_privilege using message = 'authentication_required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text, 0));
  select * into v_report from public.alertx_reports where usuario_id = v_user and request_id = p_request_id;
  if found then
    if v_report.latitud is distinct from p_latitud or v_report.longitud is distinct from p_longitud
      or v_report.descripcion is distinct from btrim(p_descripcion) or v_report.tipo is distinct from p_tipo
      or v_report.precision_metros is distinct from p_precision_metros then
      raise exception using message = 'idempotency_conflict';
    end if;
    return to_jsonb(v_report) - 'usuario_id' - 'request_id';
  end if;
  if (select count(*) from public.alertx_reports where usuario_id = v_user and created_at > now() - interval '1 minute') >= 5 then
    raise exception using message = 'report_rate_limit';
  end if;
  insert into public.alertx_reports(usuario_id, request_id, latitud, longitud, descripcion, tipo, precision_metros)
  values(v_user, p_request_id, p_latitud, p_longitud, btrim(p_descripcion), p_tipo, p_precision_metros)
  returning * into v_report;
  return to_jsonb(v_report) - 'usuario_id' - 'request_id';
end $$;
revoke all on function public.alertx_create_report(uuid, double precision, double precision, text, text, double precision) from public, anon;
grant execute on function public.alertx_create_report(uuid, double precision, double precision, text, text, double precision) to authenticated;

create function public.alertx_my_stats() returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_object('total', count(*), 'recibidos', count(*) filter(where estado = 'recibido'),
    'en_revision', count(*) filter(where estado = 'en_revision'), 'cerrados', count(*) filter(where estado = 'cerrado'))
  from public.alertx_reports where usuario_id = auth.uid();
$$;
revoke all on function public.alertx_my_stats() from public, anon;
grant execute on function public.alertx_my_stats() to authenticated;

create function public.alertx_schema_version() returns integer language sql immutable set search_path = '' as $$ select 1; $$;
revoke all on function public.alertx_schema_version() from public;
grant execute on function public.alertx_schema_version() to anon, authenticated;

commit;
