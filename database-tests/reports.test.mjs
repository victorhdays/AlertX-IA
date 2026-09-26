import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { PGlite } from '@electric-sql/pglite';

test('migration enforces identity, isolation, idempotency, validation and rate limits', async () => {
  const db = new PGlite();
  try {
    await db.exec(`
      create role anon; create role authenticated;
      create schema auth;
      create table auth.users(id uuid primary key);
      create function auth.uid() returns uuid language sql stable as
        $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
      create function auth.jwt() returns jsonb language sql stable as
        $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
      grant usage on schema auth to anon, authenticated;
      create table public.reportes(id int);
      grant select on public.reportes to anon, authenticated;
      insert into auth.users values ('00000000-0000-4000-8000-000000000001'), ('00000000-0000-4000-8000-000000000002');
    `);
    await db.exec(await readFile(new URL('../supabase/migrations/202609260001_reports.sql', import.meta.url), 'utf8'));
    await db.exec(`set role anon;`);
    await assert.rejects(db.query('select * from public.alertx_reports'), /permission denied/);
    await assert.rejects(db.query('select * from public.reportes'), /permission denied/);
    const create = (id = '00000000-0000-4000-8000-000000000011', description = 'Obstrucción en el cruce principal', lat = 20.53) =>
      db.query('select public.alertx_create_report($1, $2, -97.45, $3, $4) as report', [id, lat, description, 'obstruccion']);
    await assert.rejects(create(), /permission denied/);
    await db.exec(`reset role; set role authenticated; select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);`);
    const first = (await create()).rows[0].report;
    assert.equal(first.estado, 'recibido');
    assert.equal(first.usuario_id, undefined);
    assert.equal((await create()).rows[0].report.id, first.id);
    await assert.rejects(create(undefined, 'Datos diferentes del mismo envío'), /idempotency_conflict/);
    await assert.rejects(create('00000000-0000-4000-8000-000000000012', undefined, 91), /check constraint/);
    await assert.rejects(create('00000000-0000-4000-8000-000000000012', '   '), /check constraint/);
    await assert.rejects(db.query("update public.alertx_reports set estado = 'cerrado'"), /permission denied/);
    await assert.rejects(db.query('delete from public.alertx_reports'), /permission denied/);
    await assert.rejects(db.query("insert into public.alertx_reports default values"), /permission denied/);
    await db.exec(`select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000002', false);`);
    assert.equal((await db.query('select * from public.alertx_reports')).rows.length, 0);
    assert.equal((await db.query('select public.alertx_my_stats() as stats')).rows[0].stats.total, 0);
    await db.exec(`select set_config('request.jwt.claim.sub', '00000000-0000-4000-8000-000000000001', false);`);
    for (let i = 12; i <= 15; i++) await create(`00000000-0000-4000-8000-0000000000${i}`);
    assert.equal((await db.query('select public.alertx_my_stats() as stats')).rows[0].stats.total, 5);
    await assert.rejects(create('00000000-0000-4000-8000-000000000016'), /report_rate_limit/);
    assert.equal((await create()).rows[0].report.id, first.id);
    await db.exec(`select set_config('request.jwt.claims', '{"is_anonymous":true}', false);`);
    assert.equal((await db.query('select * from public.alertx_reports')).rows.length, 0);
    await assert.rejects(create(), /authentication_required/);
  } finally { await db.close(); }
});
