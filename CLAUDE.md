# CLAUDE.md

## Commands

```bash
npm run dev          # Next.js dev server
npm run build        # Production build
npm run lint         # ESLint
npm run test         # Vitest watch mode
npm run test:run     # Vitest single run (CI)
npx vitest run src/__tests__/lib/scheduler.test.ts  # Run single test file
```

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

