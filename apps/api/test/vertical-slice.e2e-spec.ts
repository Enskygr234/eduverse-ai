/**
 * End-to-end test of the Phase 1 vertical slice against a real PostgreSQL:
 * register → login → refresh rotation → onboarding → courses → lesson → answers → completion → XP/streak.
 * Requires DATABASE_URL pointing at a migrated + seeded database.
 */
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/bootstrap';
import { PrismaService } from '../src/prisma/prisma.service';
import { MailService } from '../src/modules/mail/mail.service';

process.env.THROTTLE_DISABLED = 'true';
process.env.JWT_ACCESS_SECRET ??= 'test-secret-test-secret-test-secret-123';

function correctResponse(q: { type: string; answerKey: any }) {
  switch (q.type) {
    case 'MULTIPLE_CHOICE':
      return { index: q.answerKey.index };
    case 'TRUE_FALSE':
      return { value: q.answerKey.value };
    case 'FILL_BLANK':
      return { text: q.answerKey.accepted[0] };
    case 'WORD_ORDER':
      return { words: String(q.answerKey.sentence).split(' ') };
    case 'MATCHING':
      return { pairs: q.answerKey.pairs };
  }
  throw new Error(q.type);
}

describe('EduVerse vertical slice (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let mail: MailService;
  const email = `e2e_${Date.now()}@example.com`;
  const password = 'Sifre1234';
  let access = '';
  let refresh = '';

  const http = () => request(app.getHttpServer());
  const auth = (t = access) => ({ Authorization: `Bearer ${t}` });

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    configureApp(app);
    await app.init();
    prisma = app.get(PrismaService);
    mail = app.get(MailService);
  });

  afterAll(async () => {
    await prisma.user.deleteMany({ where: { email: { startsWith: 'e2e_' } } });
    await app.close();
  });

  async function playLesson(lessonId: string, token = access) {
    const start = await http().post(`/v1/lessons/${lessonId}/attempts`).set(auth(token)).expect(201);
    const questions = await prisma.question.findMany({ where: { lessonId }, orderBy: { sortOrder: 'asc' } });
    for (const q of questions) {
      const res = await http()
        .post(`/v1/attempts/${start.body.attemptId}/answers`)
        .set(auth(token))
        .send({ questionId: q.id, response: correctResponse(q) })
        .expect(200);
      expect(res.body.correct).toBe(true);
    }
    return start.body.attemptId as string;
  }

  describe('authentication', () => {
    it('rejects weak passwords and unknown fields', async () => {
      await http().post('/v1/auth/register').send({ email, password: 'short', displayName: 'Ece' }).expect(400);
      await http().post('/v1/auth/register').send({ email, password, displayName: 'Ece', isAdmin: true }).expect(400);
    });

    it('registers and returns a session', async () => {
      const res = await http().post('/v1/auth/register').send({ email: email.toUpperCase(), password, displayName: 'Ece' }).expect(201);
      expect(typeof res.body.accessToken).toBe('string');
      expect(res.body.refreshToken).toContain('.');
      const user = await prisma.user.findUniqueOrThrow({ where: { email } });
      expect(user.passwordHash.startsWith('$argon2id$')).toBe(true);
    });

    it('refuses a duplicate email', async () => {
      await http().post('/v1/auth/register').send({ email, password, displayName: 'Ece' }).expect(409);
    });

    it('rejects a wrong password with a generic message', async () => {
      const res = await http().post('/v1/auth/login').send({ email, password: 'Yanlis1234' }).expect(401);
      expect(res.body.message).toBe('Email or password is incorrect');
      await http().post('/v1/auth/login').send({ email: 'nobody_e2e@example.com', password }).expect(401);
    });

    it('logs in', async () => {
      const res = await http().post('/v1/auth/login').send({ email, password }).expect(200);
      access = res.body.accessToken;
      refresh = res.body.refreshToken;
    });

    it('protects routes', async () => {
      await http().get('/v1/me').expect(401);
      await http().get('/v1/me').set(auth('not-a-jwt')).expect(401);
      const me = await http().get('/v1/me').set(auth()).expect(200);
      expect(me.body.email).toBe(email);
      expect(me.body.roles).toContain('learner');
      expect(me.body.profile.onboardingCompleted).toBe(false);
    });

    it('rotates refresh tokens and detects reuse', async () => {
      const first = await http().post('/v1/auth/refresh').send({ refreshToken: refresh }).expect(200);
      expect(first.body.refreshToken).not.toBe(refresh);
      // Replaying the old token revokes the whole family, including the new token.
      await http().post('/v1/auth/refresh').send({ refreshToken: refresh }).expect(401);
      await http().post('/v1/auth/refresh').send({ refreshToken: first.body.refreshToken }).expect(401);
      const again = await http().post('/v1/auth/login').send({ email, password }).expect(200);
      access = again.body.accessToken;
      refresh = again.body.refreshToken;
    });

    it('verifies email with the mailed code', async () => {
      const msg = [...mail.outbox].reverse().find((m) => m.to === email && m.subject.includes('doğrulama'));
      const token = /kod: (\S+)/.exec(msg!.text)![1];
      await http().post('/v1/auth/verify-email').send({ token }).expect(204);
      await http().post('/v1/auth/verify-email').send({ token }).expect(400);
      const me = await http().get('/v1/me').set(auth()).expect(200);
      expect(me.body.emailVerified).toBe(true);
    });
  });

  describe('onboarding and catalog', () => {
    it('validates onboarding input', async () => {
      await http().put('/v1/me/onboarding').set(auth()).send({ interests: [], learningGoal: 'career', level: 'BEGINNER', dailyGoalXp: 20 }).expect(400);
      await http().put('/v1/me/onboarding').set(auth()).send({ interests: ['languages'], learningGoal: 'career', level: 'BEGINNER', dailyGoalXp: 999 }).expect(400);
    });

    it('creates a learning plan', async () => {
      const res = await http()
        .put('/v1/me/onboarding')
        .set(auth())
        .send({ interests: ['languages', 'programming'], learningGoal: 'career', level: 'BEGINNER', dailyGoalXp: 20 })
        .expect(200);
      expect(res.body.recommendedCourses).toEqual(expect.arrayContaining(['english-a1', 'python-basics']));
      const me = await http().get('/v1/me').set(auth()).expect(200);
      expect(me.body.profile.onboardingCompleted).toBe(true);
    });

    it('lists categories and courses', async () => {
      const cats = await http().get('/v1/categories').set(auth()).expect(200);
      expect(cats.body.map((c: any) => c.slug)).toContain('languages');
      const courses = await http().get('/v1/courses?category=languages').set(auth()).expect(200);
      expect(courses.body.map((c: any) => c.slug)).toEqual(['english-a1']);
    });

    it('locks every lesson except the first', async () => {
      const res = await http().get('/v1/courses/english-a1').set(auth()).expect(200);
      const lessons = res.body.units.flatMap((u: any) => u.lessons);
      expect(lessons[0].locked).toBe(false);
      expect(lessons.slice(1).every((l: any) => l.locked)).toBe(true);
    });
  });

  describe('lesson engine and XP integrity', () => {
    let firstLessonId = '';
    let secondLessonId = '';

    beforeAll(async () => {
      const res = await http().get('/v1/courses/english-a1').set(auth()).expect(200);
      const lessons = res.body.units.flatMap((u: any) => u.lessons);
      firstLessonId = lessons[0].id;
      secondLessonId = lessons[1].id;
    });

    it('never sends answer keys to the client', async () => {
      const res = await http().get(`/v1/lessons/${firstLessonId}`).set(auth()).expect(200);
      expect(res.body.questions.length).toBeGreaterThan(0);
      const raw = JSON.stringify(res.body);
      expect(raw).not.toContain('answerKey');
      expect(raw).not.toContain('answer_key');
      expect(raw).not.toContain('accepted');
    });

    it('refuses locked lessons', async () => {
      await http().get(`/v1/lessons/${secondLessonId}`).set(auth()).expect(404);
      await http().post(`/v1/lessons/${secondLessonId}/attempts`).set(auth()).expect(404);
    });

    it('grades on the server and rejects malformed answers', async () => {
      const start = await http().post(`/v1/lessons/${firstLessonId}/attempts`).set(auth()).expect(201);
      const q = await prisma.question.findFirstOrThrow({ where: { lessonId: firstLessonId, type: 'MULTIPLE_CHOICE' } });
      await http().post(`/v1/attempts/${start.body.attemptId}/answers`).set(auth()).send({ questionId: q.id, response: { index: 99 } }).expect(400);
      const wrong = (q.answerKey as any).index === 0 ? 1 : 0;
      const res = await http()
        .post(`/v1/attempts/${start.body.attemptId}/answers`)
        .set(auth())
        .send({ questionId: q.id, response: { index: wrong } })
        .expect(200);
      expect(res.body.correct).toBe(false);
      expect(res.body.correctAnswer).toEqual({ index: (q.answerKey as any).index });
      // No second chance inside the same attempt.
      await http()
        .post(`/v1/attempts/${start.body.attemptId}/answers`)
        .set(auth())
        .send({ questionId: q.id, response: { index: (q.answerKey as any).index } })
        .expect(409);
      // Cannot complete with unanswered questions.
      await http().post(`/v1/attempts/${start.body.attemptId}/complete`).set(auth()).expect(400);
    });

    it('completes a lesson once and awards XP once', async () => {
      const attemptId = await playLesson(firstLessonId);
      const done = await http().post(`/v1/attempts/${attemptId}/complete`).set(auth()).expect(200);
      expect(done.body).toMatchObject({ xpAwarded: 10, accuracy: 100, firstCompletion: true, totalXp: 10, streak: 1 });

      const replays = await Promise.all([
        http().post(`/v1/attempts/${attemptId}/complete`).set(auth()),
        http().post(`/v1/attempts/${attemptId}/complete`).set(auth()),
      ]);
      expect(replays.map((r) => r.status)).toEqual([409, 409]);

      const user = await prisma.user.findUniqueOrThrow({ where: { email } });
      expect(await prisma.xpTransaction.count({ where: { userId: user.id } })).toBe(1);
    });

    it('unlocks the next lesson and persists progress', async () => {
      const res = await http().get('/v1/courses/english-a1').set(auth()).expect(200);
      const lessons = res.body.units.flatMap((u: any) => u.lessons);
      expect(lessons[0].completed).toBe(true);
      expect(lessons[1].locked).toBe(false);
      expect(res.body.completedLessons).toBe(1);
    });

    it('gives reduced XP for practice repeats', async () => {
      const attemptId = await playLesson(firstLessonId);
      const done = await http().post(`/v1/attempts/${attemptId}/complete`).set(auth()).expect(200);
      expect(done.body.firstCompletion).toBe(false);
      expect(done.body.xpAwarded).toBe(3);
    });

    it('shows progress on the dashboard', async () => {
      const res = await http().get('/v1/me/dashboard').set(auth()).expect(200);
      expect(res.body.totalXp).toBe(13);
      expect(res.body.todayXp).toBe(13);
      expect(res.body.streak.current).toBe(1);
      expect(res.body.continueLearning.nextLesson.id).toBe(secondLessonId);
    });

    it("keeps other users' attempts private", async () => {
      const other = await http()
        .post('/v1/auth/register')
        .send({ email: `e2e_other_${Date.now()}@example.com`, password, displayName: 'Can' })
        .expect(201);
      const mine = await http().post(`/v1/lessons/${firstLessonId}/attempts`).set(auth()).expect(201);
      await http().post(`/v1/attempts/${mine.body.attemptId}/complete`).set(auth(other.body.accessToken)).expect(404);
    });
  });

  describe('password reset', () => {
    it('resets the password and signs out other sessions', async () => {
      await http().post('/v1/auth/forgot-password').send({ email }).expect(202);
      await http().post('/v1/auth/forgot-password').send({ email: 'nobody_e2e@example.com' }).expect(202);
      const msg = [...mail.outbox].reverse().find((m) => m.to === email && m.subject.includes('şifre'));
      const token = /kod: (\S+)/.exec(msg!.text)![1];
      await http().post('/v1/auth/reset-password').send({ token, newPassword: 'YeniSifre99' }).expect(204);
      await http().post('/v1/auth/refresh').send({ refreshToken: refresh }).expect(401);
      await http().post('/v1/auth/login').send({ email, password }).expect(401);
      await http().post('/v1/auth/login').send({ email, password: 'YeniSifre99' }).expect(200);
    });
  });
});
