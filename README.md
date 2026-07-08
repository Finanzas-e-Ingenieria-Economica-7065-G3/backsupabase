# backsupabase

## Requisitos

- [Docker Desktop](https://docs.docker.com/desktop/) instalado y ejecutándose
- [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started#installing-the-supabase-cli): `npm install -g supabase`

## Iniciar el entorno local

```bash
supabase start
```

Esto descarga las imágenes Docker necesarias e inicia Supabase localmente (Studio, API, Auth, Storage, DB).

## Aplicar migraciones y seed data

```bash
supabase db reset
```

Esto ejecuta las migraciones (esquemas, tablas, funciones, RLS) y luego inserta los 20 vehículos de prueba con imágenes.

## Detener

```bash
supabase stop
```

## Acceder

| Servicio | URL |
|----------|-----|
| Supabase Studio | http://127.0.0.1:54323 |
| API | http://127.0.0.1:54321 |
| DB (PostgreSQL) | postgresql://postgres:postgres@127.0.0.1:54322/postgres |

## Estructura

```
supabase/
  migrations/       # Migraciones del esquema de base de datos
  seed.sql          # Datos de prueba (20 vehículos con imágenes)
  config.toml       # Configuración de Supabase
```