import type { QuestionType } from '@prisma/client';

/**
 * Server-side answer checking. The client never receives answer keys before answering,
 * and its own verdict is never trusted.
 */

export class InvalidAnswerError extends Error {}

type Json = unknown;

const isObject = (v: Json): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);

/** Case-, accent-spacing- and punctuation-tolerant comparison for typed text. */
export function normalizeText(value: string): string {
  return value
    .normalize('NFKC')
    .toLocaleLowerCase('tr')
    .replace(/\s+/g, ' ')
    .replace(/\s*([()\[\]{}.,!?;:])\s*/g, '$1')
    .trim()
    .replace(/[.!?]+$/, '');
}

export interface GradeResult {
  correct: boolean;
  /** Human-readable correct answer, revealed only after the user answered. */
  correctAnswer: unknown;
}

export function grade(type: QuestionType, payload: Json, answerKey: Json, response: Json): GradeResult {
  if (!isObject(response)) throw new InvalidAnswerError('Answer must be an object');
  if (!isObject(answerKey)) throw new Error('Corrupt answer key');
  const p = isObject(payload) ? payload : {};

  switch (type) {
    case 'MULTIPLE_CHOICE': {
      const options = Array.isArray(p.options) ? p.options : [];
      const index = response.index;
      if (typeof index !== 'number' || !Number.isInteger(index) || index < 0 || index >= options.length) {
        throw new InvalidAnswerError('index out of range');
      }
      return { correct: index === answerKey.index, correctAnswer: { index: answerKey.index } };
    }
    case 'TRUE_FALSE': {
      if (typeof response.value !== 'boolean') throw new InvalidAnswerError('value must be boolean');
      return { correct: response.value === answerKey.value, correctAnswer: { value: answerKey.value } };
    }
    case 'FILL_BLANK': {
      if (typeof response.text !== 'string' || response.text.length > 200) throw new InvalidAnswerError('text required');
      const accepted = (answerKey.accepted as string[]) ?? [];
      const given = normalizeText(response.text);
      return { correct: accepted.some((a) => normalizeText(a) === given), correctAnswer: { text: accepted[0] } };
    }
    case 'WORD_ORDER': {
      const words = response.words;
      const bank = Array.isArray(p.words) ? (p.words as string[]) : [];
      if (!Array.isArray(words) || words.some((w) => typeof w !== 'string') || words.length > bank.length) {
        throw new InvalidAnswerError('words must be an array of strings from the word bank');
      }
      const expected = String(answerKey.sentence);
      return {
        correct: normalizeText(words.join(' ')) === normalizeText(expected),
        correctAnswer: { sentence: expected },
      };
    }
    case 'MATCHING': {
      const pairs = response.pairs;
      const expected = (answerKey.pairs as Record<string, string>) ?? {};
      if (!isObject(pairs)) throw new InvalidAnswerError('pairs must be an object');
      const keys = Object.keys(expected);
      const correct =
        Object.keys(pairs).length === keys.length && keys.every((k) => pairs[k] === expected[k]);
      return { correct, correctAnswer: { pairs: expected } };
    }
    default:
      throw new InvalidAnswerError(`Unsupported question type ${type as string}`);
  }
}
