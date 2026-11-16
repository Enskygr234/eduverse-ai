import { readFileSync } from 'fs';
import { join } from 'path';
import { grade } from './grader';

/** Guards the bundled course pack: every question must be answerable with its own key. */
const pack = JSON.parse(readFileSync(join(__dirname, '../../../../../packages/content/courses.json'), 'utf8'));

function correctResponse(q: any): unknown {
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
    default:
      throw new Error(`unknown type ${q.type}`);
  }
}

describe('course content pack', () => {
  const categories = new Set(pack.categories.map((c: any) => c.slug));
  const lessonSlugs = new Set<string>();

  for (const course of pack.courses) {
    it(`${course.slug} points to a known category`, () => {
      expect(categories.has(course.categorySlug)).toBe(true);
    });

    for (const unit of course.units) {
      for (const lesson of unit.lessons) {
        it(`${lesson.slug} has a unique slug and questions`, () => {
          expect(lessonSlugs.has(lesson.slug)).toBe(false);
          lessonSlugs.add(lesson.slug);
          expect(lesson.questions.length > 0).toBe(true);
          expect(lesson.xpReward > 0).toBe(true);
        });

        lesson.questions.forEach((q: any, i: number) => {
          it(`${lesson.slug} #${i + 1} (${q.type}) is answerable with its key`, () => {
            expect(grade(q.type, q.payload, q.answerKey, correctResponse(q)).correct).toBe(true);
            if (q.type === 'WORD_ORDER') {
              const bank = [...q.payload.words].sort();
              const needed = String(q.answerKey.sentence).split(' ').sort();
              expect(bank).toEqual(needed);
            }
            if (q.type === 'MATCHING') {
              expect([...q.payload.left].sort()).toEqual(Object.keys(q.answerKey.pairs).sort());
              expect([...q.payload.right].sort()).toEqual(Object.values(q.answerKey.pairs).map(String).sort());
            }
          });
        });
      }
    }
  }
});
