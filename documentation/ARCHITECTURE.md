# EduVerse AI — Architecture

## 1. Overview

```
┌──────────────────────┐     HTTPS/JSON      ┌───────────────────────────────────────────┐
│ Flutter app          │ ──────────────────▶ │ NestJS API (modular monolith)             │
│ Riverpod · GoRouter  │   JWT access +      │ auth · users · courses · learning ·       │
│ RemoteBackend /      │   rotating refresh  │ gamification · ai · audit · mail          │
│ LocalBackend         │                     └───────────────┬───────────────┬───────────┘
└──────────────────────┘                                     │               │
                                                     PostgreSQL (Prisma)   Redis (Phase 4+:
┌──────────────────────┐                                                   quotas, rate limits,
│ Admin web (Phase 7)  │ ── same API, role-guarded routes                  leaderboards)
└──────────────────────┘                              AI providers: Gemini · Groq (server-side only)
```

The backend starts as a **modular monolith**: each domain is a Nest module with its own
controller, service and DTOs. Modules talk to each other only through exported services
(e.g. `LearningService` → `GamificationService.awardLessonXp`). A module with heavy traffic
(leaderboards, AI) can later move behind a queue or become its own service without
changing the others.

## 2. Repository layout

| Path | Purpose |
| --- | --- |
| `apps/api` | NestJS + Prisma backend, migrations, seed, unit + e2e tests |
| `apps/mobile` | Flutter app (Android/iOS) |
| `apps/admin` | Admin panel (Phase 7, not started) |
| `packages/content` | Course pack (JSON) used by the seed and bundled in the offline app |
| `infrastructure/docker` | Local stack: Postgres, Redis, API |
| `documentation` | This document, roadmap, API reference |
| `.github/workflows` | CI: typecheck, migrations, tests, APK build and release |

`packages/shared-types` and `packages/api-client` from the original plan are deferred:
the only API consumer today is Dart, so a TypeScript client would be unused. The admin panel
(Phase 7) will introduce them, generated from an OpenAPI spec.

## 3. Security model

* **Passwords**: argon2id (19 MiB, t=2). Unknown-email logins still run a hash to keep timing flat.
* **Access tokens**: JWT, 15 min, `iss`/`aud` checked, `typ=access`. A global guard protects
  every route; public routes opt out with `@Public()`.
* **Refresh tokens**: opaque `<id>.<secret>`, stored as SHA-256, rotated on every use.
  Re-using a rotated token revokes the whole family (theft detection). Rotation uses a
  conditional update so two parallel refreshes cannot both succeed.
* **Email verification / password reset**: single-use hashed tokens with expiry; a reset
  revokes all sessions. `forgot-password` answers the same for unknown emails.
* **Validation**: global `ValidationPipe` with `whitelist` + `forbidNonWhitelisted`; env is
  validated with zod at boot and the app refuses to start on bad config.
* **Rate limiting**: global 120 req/min per IP; auth routes 3–30/min.
* **Never trust the client**: answer keys never leave the server; grading, XP, streaks
  and lesson unlocking are computed server-side. XP rows are unique per
  `(user, source, attempt)`, and completion is a conditional status flip inside one
  transaction, so double submits cannot award XP twice.
* **Audit log**: register, login, failed login, refresh reuse, email verify, password reset,
  lesson completion.
* **AI keys**: only in server env; providers send them in headers, never in URLs or logs.
* **Roles**: `super_admin, admin, content_editor, moderator, support, learner` with a
  permissions table; `@Roles()` + `RolesGuard` enforce them (used by admin routes in Phase 7).

## 4. Learning flow (vertical slice)

1. `POST /v1/auth/register` → session tokens; profile, streak and `learner` role created in one transaction.
2. `PUT /v1/me/onboarding` → interests, goal, level, daily XP goal → rule-based learning plan.
3. `GET /v1/courses`, `GET /v1/courses/:slug` → path with `completed` / `locked` per lesson.
4. `GET /v1/lessons/:id` → explanation, examples, questions **without** answer keys.
5. `POST /v1/lessons/:id/attempts` → attempt id.
6. `POST /v1/attempts/:id/answers` → server grading, one answer per question, feedback with explanation.
7. `POST /v1/attempts/:id/complete` → transaction: progress, XP transaction, profile total, streak, enrollment, audit.
8. `GET /v1/me/dashboard` → greeting data, XP/level, today vs daily goal, streak, continue-learning, recommendations.

### XP rules (`apps/api/src/modules/gamification/rules.ts`)

* First completion: `round(xpReward × max(0.5, accuracy))`.
* Repeat (practice): one third of that, minimum 1.
* Level n → n+1 needs `n × 50` XP.
* Streak days are calendar days in the user's time zone.

## 5. Mobile architecture

* `lib/data/backend.dart` — the `EduverseBackend` contract.
  * `RemoteBackend` (Dio + secure storage, single-flight refresh on 401).
  * `LocalBackend` — offline mode on the bundled course pack with the same rules
    (Dart port of grader and XP rules, tested against the same expectations as the API).
  * Chosen at build time: `--dart-define=API_BASE_URL=...` → remote; otherwise offline.
* `lib/app` — providers (Riverpod), router (GoRouter with session-driven redirects), app shell.
* `lib/core/design` — tokens (colors, spacing, radii, motion) and light/dark themes.
* `lib/features/*` — auth, onboarding, home, courses, lesson (exercise widgets per type), profile.

## 6. Content model

`Category → Course → Unit → Lesson → Question`. Questions store a client-safe `payload`
and a server-only `answer_key`. `status` (DRAFT/IN_REVIEW/PUBLISHED/ARCHIVED) and `source`
(HUMAN/AI_GENERATED) let AI-generated material go through review before publishing (Phase 4).
Supported question types: multiple choice, true/false, fill in the blank, matching, word order.
