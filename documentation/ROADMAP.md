# Roadmap and status

Status legend: ✅ done and tested · 🟡 foundation only · ⬜ not started

## Phase 1 — Architecture & foundation
* ✅ Monorepo, CI, Docker dev stack, documentation
* ✅ PostgreSQL schema + initial migration (CI verifies migrations match `schema.prisma`)
* ✅ Seed: roles/permissions, 3 courses, 6 lessons, 24 questions
* ⬜ Commit lockfiles (`package-lock.json`, `pubspec.lock`) from the first green CI run

## Phase 2 — Auth, profiles, onboarding, navigation, design system
* ✅ Register, login, refresh rotation with reuse detection, logout
* ✅ Email verification and password reset (API; **mail transport is console-only**)
* ✅ Onboarding → learning plan; profile endpoint
* ✅ Flutter: welcome, login, register, onboarding, bottom navigation, light/dark theme, tokens
* ⬜ Mobile screens for email verification and password reset
* ⬜ Real mail provider

## Phase 3 — Courses, lesson & question engine, progress
* ✅ Catalog, course path with locking, lesson player, 5 exercise types, server grading, progress
* ⬜ Listening, speaking, code challenge, math input, short written answer, image questions
* ⬜ Certificates

## Phase 4 — AI
* 🟡 Provider abstraction (Gemini, Groq) with fallback, input/output caps, tests
* ⬜ Tutor endpoints, per-user quotas in Redis, cost tracking, generated-content review queue

## Phase 5 — Gamification
* ✅ XP transactions (idempotent), levels, daily streaks, daily goal
* ⬜ Streak protection, missions, achievements, badges, leaderboards, leagues

## Phase 6 — Social, notifications, subscriptions
* ⬜ Friends, challenges, push notifications (FCM/APNs), store billing verification

## Phase 7 — Admin, analytics, hardening
* ⬜ Admin web panel (RBAC already in schema), analytics, Redis-backed throttling, security audit, deployment
