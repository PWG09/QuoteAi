# QuoteAI

QuoteAI is the professional quoting SaaS foundation for CBDEVS.

## Stack
- Next.js 16 + TypeScript + App Router
- Supabase Auth + PostgreSQL + RLS
- Vercel
- Tailwind CSS
- Zod validation
- Provider-agnostic AI integration for OpenAI/NVIDIA

## First production foundation
- Cookie-based Supabase authentication
- Automatic organization creation for new users
- Organization memberships and RBAC roles
- Application permission foundation
- PostgreSQL tenant isolation with RLS
- Cross-tenant customer/quote/service checks
- Customers
- Reusable services
- Server-side quote creation
- Integer-cent financial calculations
- Quote items and version snapshots
- AI quote drafting with validated structured output
- Audit log writes
- Protected dashboard and API routes
- Security response headers

## Authorization model

Protected operations follow:

authenticated user → organization membership → role/permission → resource authorization → organization_id → PostgreSQL RLS

UUIDs are identifiers, not authorization boundaries.

## Setup

1. Create a Supabase project.
2. Configure `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
3. Run `supabase/migrations/0001_quoteai.sql`.
4. Copy `.env.example` to `.env.local`.
5. Configure an AI provider if AI drafting is needed.
6. Run `npm install`.
7. Run `npm run dev`.

Supabase's current Next.js guidance uses `@supabase/ssr` and cookie-based sessions. The repository follows that pattern.

## Security roadmap

The master production plan still calls for the next layers before commercial launch: public quote links with revocable tokens, PDF/email, invitations, rate limiting and abuse controls, centralized billing/entitlements, verified Stripe webhooks, stronger permission matrices, automated RLS/IDOR tests, Sentry-ready observability, data export/deletion, legal pages/consent, CI security checks and production deployment configuration.

No secrets belong in this repository.

Repository: https://github.com/PWG09/QuoteAi
