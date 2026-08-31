# FAWUsed.ru MVP

GitHub-ready monorepo starter for the Russian FAW commercial vehicle classifieds platform.

## Structure

- `apps/web` — Next.js web application
- `apps/api` — NestJS REST API starter
- `packages/contracts` — shared TypeScript contracts
- `packages/ui` — shared brand/UI constants starter
- `database/migrations` — PostgreSQL/PostGIS schema
- `docs/openapi.yaml` — OpenAPI 3.1 contract
- `infra/docker` — reserved for deployment-specific Docker assets
- `.github/workflows/ci.yml` — GitHub Actions CI

## Prerequisites

- Node.js 22+
- pnpm 9+
- Docker + Docker Compose

## First run

```bash
cp .env.example .env
pnpm install
docker compose up -d postgres redis minio
pnpm dev
```

Web: http://localhost:3000  
API health: http://localhost:4000/api/v1/health

## Database

On a fresh Docker volume, `database/migrations/001_initial.sql` is applied automatically by PostgreSQL init. For normal development, move migrations to the selected migration tool before production.

## Architecture rules already encoded

- Vehicle is separate from Listing.
- One `published` listing per Vehicle/VIN.
- One user can belong to at most one organization.
- Select/Approved are verification records controlled by the platform.
- Published listing requires 6+ processed photos (validation helper included in SQL).
- API credentials, idempotency, webhooks, outbox, analytics and audit are first-class entities.

## GitHub first push

Create an empty private GitHub repository named `fawused` and run:

```bash
git init
git add .
git commit -m "chore: bootstrap FAWUsed MVP"
git branch -M main
git remote add origin git@github.com:YOUR_ORG_OR_USER/fawused.git
git push -u origin main
```

Then protect `main`, require pull requests and require the `CI / quality` check.

## Recommended branches

- `main` — production-ready
- `develop` — optional integration branch
- feature branches: `feat/auth-sms`, `feat/listings`, `feat/catalog`, etc.

## Immediate engineering backlog

1. Connect NestJS to PostgreSQL using a migration/ORM choice.
2. Implement real SMS OTP provider + sessions.
3. Implement Organization/RBAC.
4. Implement Vehicle + Listing transactional services.
5. Implement catalog query builder/PostGIS radius filtering.
6. Implement S3 presigned uploads and media worker.
7. Generate frontend API client from `docs/openapi.yaml`.
8. Add admin API surface and moderation UI.
