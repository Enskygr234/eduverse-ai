/* Idempotent development seed: roles/permissions and the bundled course pack. */
import { PrismaClient, Prisma, QuestionType, CourseLevel } from '@prisma/client';
import { readFileSync } from 'fs';
import { join } from 'path';

const prisma = new PrismaClient();

const ROLES: Record<string, { name: string; permissions: string[] }> = {
  super_admin: { name: 'Super Admin', permissions: ['*'] },
  admin: { name: 'Admin', permissions: ['users.read', 'users.write', 'content.read', 'content.write', 'content.publish', 'reports.read'] },
  content_editor: { name: 'Content Editor', permissions: ['content.read', 'content.write'] },
  moderator: { name: 'Moderator', permissions: ['users.read', 'moderation.write'] },
  support: { name: 'Support', permissions: ['users.read'] },
  learner: { name: 'Learner', permissions: [] },
};

interface PackQuestion {
  type: QuestionType;
  prompt: string;
  payload: Prisma.InputJsonValue;
  answerKey: Prisma.InputJsonValue;
  explanation: string;
}
interface PackLesson {
  slug: string;
  title: string;
  xpReward: number;
  explanation: string;
  examples: string[];
  questions: PackQuestion[];
}
interface Pack {
  categories: { slug: string; name: string; icon: string; color: string; order: number }[];
  courses: {
    slug: string;
    categorySlug: string;
    title: string;
    description: string;
    level: CourseLevel;
    units: { title: string; lessons: PackLesson[] }[];
  }[];
}

async function seedRoles() {
  const allPermissions = [...new Set(Object.values(ROLES).flatMap((r) => r.permissions))];
  for (const key of allPermissions) {
    await prisma.permission.upsert({ where: { key }, create: { key }, update: {} });
  }
  for (const [key, def] of Object.entries(ROLES)) {
    const role = await prisma.role.upsert({ where: { key }, create: { key, name: def.name }, update: { name: def.name } });
    for (const pKey of def.permissions) {
      const permission = await prisma.permission.findUniqueOrThrow({ where: { key: pKey } });
      await prisma.rolePermission.upsert({
        where: { roleId_permissionId: { roleId: role.id, permissionId: permission.id } },
        create: { roleId: role.id, permissionId: permission.id },
        update: {},
      });
    }
  }
}

async function seedContent(pack: Pack) {
  for (const c of pack.categories) {
    await prisma.category.upsert({
      where: { slug: c.slug },
      create: { slug: c.slug, name: c.name, icon: c.icon, color: c.color, sortOrder: c.order },
      update: { name: c.name, icon: c.icon, color: c.color, sortOrder: c.order },
    });
  }

  for (const c of pack.courses) {
    const category = await prisma.category.findUniqueOrThrow({ where: { slug: c.categorySlug } });
    const course = await prisma.course.upsert({
      where: { slug: c.slug },
      create: { slug: c.slug, categoryId: category.id, title: c.title, description: c.description, level: c.level, status: 'PUBLISHED' },
      update: { categoryId: category.id, title: c.title, description: c.description, level: c.level, status: 'PUBLISHED' },
    });

    for (const [ui, u] of c.units.entries()) {
      const unit = await prisma.unit.upsert({
        where: { courseId_sortOrder: { courseId: course.id, sortOrder: ui + 1 } },
        create: { courseId: course.id, sortOrder: ui + 1, title: u.title },
        update: { title: u.title },
      });

      for (const [li, l] of u.lessons.entries()) {
        const data = { unitId: unit.id, sortOrder: li + 1, title: l.title, explanation: l.explanation, examples: l.examples, xpReward: l.xpReward, status: 'PUBLISHED' as const };
        const lesson = await prisma.lesson.upsert({ where: { slug: l.slug }, create: { slug: l.slug, ...data }, update: data });

        for (const [qi, q] of l.questions.entries()) {
          const qData = { type: q.type, prompt: q.prompt, payload: q.payload, answerKey: q.answerKey, explanation: q.explanation, status: 'PUBLISHED' as const };
          await prisma.question.upsert({
            where: { lessonId_sortOrder: { lessonId: lesson.id, sortOrder: qi + 1 } },
            create: { lessonId: lesson.id, sortOrder: qi + 1, ...qData },
            update: qData,
          });
        }
        await prisma.question.deleteMany({ where: { lessonId: lesson.id, sortOrder: { gt: l.questions.length } } });
      }
    }
  }
}

async function main() {
  const packPath = process.env.CONTENT_PACK ?? join(__dirname, '../../../packages/content/courses.json');
  const pack: Pack = JSON.parse(readFileSync(packPath, 'utf8'));
  await seedRoles();
  await seedContent(pack);
  const counts = await Promise.all([prisma.course.count(), prisma.lesson.count(), prisma.question.count()]);
  console.log(`Seed complete: ${counts[0]} courses, ${counts[1]} lessons, ${counts[2]} questions`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
