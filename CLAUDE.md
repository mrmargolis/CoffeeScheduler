# CLAUDE.md

## Commands

```bash
pnpm install         # Install dependencies (pnpm only — do not use npm or yarn)
pnpm dev             # Next.js dev server
pnpm build           # Production build
pnpm lint            # ESLint
pnpm test            # Vitest watch mode
pnpm test:run        # Vitest single run (CI)
pnpm exec vitest run src/__tests__/lib/scheduler.test.ts  # Run single test file
```

## Package management

pnpm only. The version is pinned by the `packageManager` field in `package.json`
and provisioned by Corepack (`corepack enable pnpm`); `pnpm-lock.yaml` is the
only lockfile and is committed. Never run `npm install` or `yarn` here — either
one creates a competing lockfile and bypasses the policies below.

`pnpm-workspace.yaml` carries two supply-chain settings:

- `minimumReleaseAge: 10080` — a version published less than 7 days ago will not
  install. This blunts compromised-maintainer attacks, which are usually caught
  and unpublished within days. It is enforced on every install, including ones
  fully resolved from the lockfile, so a new dependency (or an upgrade to a
  just-released version) fails until the version is a week old. Wait it out
  rather than disabling the setting.
- `allowBuilds` — an explicit per-package allowlist for dependency install/build
  scripts, which pnpm otherwise blocks. Adding an entry means letting that
  package run code at install time, so add one only when a dependency genuinely
  needs a native build.

## Architecture

Next.js 14 App Router, TypeScript strict mode, SQLite (better-sqlite3), SWR for client data fetching, FullCalendar for visualization, Tailwind CSS dark theme.

### Data Loads
Data on coffee bags and past brews is imported manually from a BeanConqueror iOS application zip file export

### Database

SQLite at `data/coffee.db`, WAL mode, foreign keys on. Schema in `src/lib/schema.ts` with inline migrations. Test DBs are in-memory via `createTestDb()` from `src/lib/db.ts`.

### Date handling

All dates are ISO 8601 strings (`YYYY-MM-DD`). Use UTC-based `Date` construction (`new Date(iso + "T00:00:00Z")`) to avoid timezone drift. BeanConqueror imports parse `DD.MM.YYYY` format.

### Testing patterns

Vitest with happy-dom. Tests in `src/__tests__/` mirroring `src/` structure. API and DB tests use `createTestDb()` for isolated in-memory databases. Scheduler tests use a `makeBean()` helper with sensible defaults.

