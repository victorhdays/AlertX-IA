# Checklist de producción

1. Configura `APP_ENV=production`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `CORS_ORIGINS` y `ALLOWED_HOSTS` en el proveedor. Usa solo la clave pública `anon`/publishable.
2. Aplica `supabase/migrations/202609260001_reports.sql`. La migración activa RLS, limita la lectura a cada usuario, hace los envíos idempotentes y limita a cinco reportes por minuto.
3. Ejecuta la API con `uvicorn backend_fastapi.main:app --host 0.0.0.0 --port 8000` detrás de HTTPS y un proxy con health checks en `/health` y `/ready`.
4. Compila Flutter pasando `SUPABASE_URL`, `SUPABASE_ANON_KEY` y `API_BASE_URL` mediante `--dart-define`. Configura la firma real de Android/iOS antes de generar el release.
5. Verifica con una cuenta de prueba el login, permiso de ubicación, creación, reintento tras timeout, historial y cierre de sesión. Ante una emergencia, la app debe dirigir al 911; guardar un reporte no es despacho de unidades.

Comandos de validación:

```powershell
python -m pytest backend_fastapi/tests -q
python -m ruff check backend_fastapi
cd app_flutter
flutter analyze
flutter test
```
