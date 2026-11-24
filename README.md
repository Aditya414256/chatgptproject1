# FindMedicine — chatgptproject1

College project only. **Not for real medical use.**

## Stack
React + TypeScript + Vite, React Router, Tailwind v4, TanStack Query, Supabase Auth/Postgres/RLS/Storage/Realtime and Playwright. No maps.

## Local setup

```bash
npm install
cp .env.example .env
# Fill in VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY from your existing Supabase project.
npm run dev
```

On Windows, replace `cp` with `copy`. Never commit `.env` or service-role keys.

## Database

**Before running migrations:** review `supabase/migrations/` against your existing database; this project may have objects with the same name. Use a disposable Supabase project for testing where possible. Your existing storage bucket and pg_cron extension must not be recreated. For the referenced project:

```bash
npx supabase login
npx supabase link --project-ref ilumcvjseevbpkgtscth
npx supabase db push
```

Type the database password directly into your terminal if the CLI asks. Do not put it in chat. Inspect migration conflicts before applying.

## Accounts

Sign up in the app as `customer` or `store_owner`. You must provision owner stores and their inventory using the dashboard/SQL before orders can be placed. Demo passwords are intentionally **not embedded in the repository**. Supabase Auth users cannot be created safely by inserting arbitrary passwords into SQL tables.

## Test notification flow

Open a normal browser window as a customer and an incognito window as a store owner. In the owner window click **Enable alerts**. Place an order from the customer and verify that it appears in the owner dashboard and that status changes appear in My orders. For automated smoke tests run:

```bash
npx playwright install chromium
npm run test:e2e
```

Full backend integration and concurrency scenarios remain unverified; see `PROGRESS.md`.

## Repository creation

Create a blank GitHub repo named `chatgptproject1` and run:

```bash
git init
git add .
git commit -m "feat: initial FindMedicine scaffold"
git branch -M main
git remote add origin https://github.com/Aditya414256/chatgptproject1.git
git push -u origin main
```
