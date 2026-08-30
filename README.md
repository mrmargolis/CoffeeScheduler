This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

This project uses [pnpm](https://pnpm.io). The version is pinned in
`package.json`, so Corepack will fetch it for you:

```bash
corepack enable pnpm
pnpm install
```

Then run the development server:

```bash
pnpm dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

A read-only schedule is also published to [GitHub Pages](https://mrmargolis.github.io/CoffeeScheduler/). Update it with `pnpm publish-schedule`.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Dependencies

Dependencies are managed with pnpm and locked in `pnpm-lock.yaml` — don't run
`npm install` or `yarn` here, as either would add a competing lockfile.

`pnpm-workspace.yaml` sets `minimumReleaseAge: 10080`, so pnpm refuses to
install any version published in the last 7 days. Freshly published versions are
the usual shape of a compromised-maintainer attack, and most get caught and
pulled within that window. The check runs on every install, including ones
resolved from the lockfile, so adding a dependency or upgrading to a
just-released version will fail until that version is a week old — wait rather
than disabling the setting.

pnpm also blocks dependency install scripts by default. The packages allowed to
run them are listed explicitly under `allowBuilds` in `pnpm-workspace.yaml`.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

You can check out [the Next.js GitHub repository](https://github.com/vercel/next.js) - your feedback and contributions are welcome!

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
