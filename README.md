# FindMedicine — chatgptproject1

College demonstration only. **Not for real medical use.**

## New independent Supabase project

This repository uses a **separate** Supabase project named `chatgptproject1`, hosted in Mumbai (ap-south-1).

- Project ref: `kkkolpwdxzgscpbagmfk`
- Dashboard: https://supabase.com/dashboard/project/kkkolpwdxzgscpbagmfk
- The new database schema was installed on November 24, 2026.
- All existing MediFind and FindMedi projects were deliberately left untouched.
- **Do not re-run database migrations against the original FindMedi project.**

## Run locally (Windows PowerShell)

```powershell
git pull origin main
Copy-Item .env.example .env
npm install
npm run dev
```

Open the localhost URL printed by Vite (normally http://localhost:5173).

`.env.example` holds a browser-safe **publishable** Supabase key for this isolated project. `.env` is ignored by Git. Never commit a Supabase service_role key, secret key, or database password.

## What's set up

- React + TypeScript + Vite, React Router, Tailwind CSS v4, TanStack Query
- Supabase Auth with customer and store_owner roles
- Seven public database tables with Row Level Security enabled
- 16 sample medicines
- Private `prescriptions` storage bucket (5MB; JPG, PNG, PDF)
- PostgreSQL order creation and status-change functions, including inventory locks and stock restoration
- Automated expiry of unanswered orders using pg_cron, one-minute schedule
- Self-service store setup on the store-owner dashboard

## Start using the app

1. Start the dev server and register as **store_owner** with a valid email. Confirm your email if Supabase requires it.
2. Open **Store orders**. Enter a pharmacy name, full address, delivery pincodes and allow browser geolocation to create the store.
3. The new store gets initial **demo** inventory for all medicines. Review/edit stock and prices in **Inventory**.
4. In another browser window, register as **customer**, select medicines and use pickup location or a matching delivery pincode.
5. Select the pharmacy, place an order and check status changes in **My orders**.
6. Create up to four independent store-owner accounts if you want the four-store demo. There are currently no pre-created account credentials.

For pickup of prescription-required medicines, the customer brings the prescription to the store. Delivery requires a file upload.

## Database reproducibility

The SQL source is in `supabase/migrations/`. It is **already applied** to the new project. These files are for reproducibility, not instructions to push duplicate migrations to this configured project.

For another *empty* Supabase project only, install Supabase CLI, link to the *new target project*, and run `npx supabase db push` after reviewing the migrations and ensuring they are not already present. The configured project already has applied migrations via the connected API and may have migration-history differences from local CLI files.

## Testing

```powershell
npx playwright install chromium
npm run test:e2e
```

The live authenticated end-to-end flow, concurrent stock race, and cross-role access behavior have **not yet passed** a complete automated test suite. Do not treat the site as production-ready. See `PROGRESS.md`.
