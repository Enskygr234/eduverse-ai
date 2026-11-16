import { grade, InvalidAnswerError, normalizeText } from './grader';

describe('normalizeText', () => {
  it('ignores case, extra spaces and trailing punctuation', () => {
    expect(normalizeText('  Good   Evening! ')).toBe('good evening');
  });
  it('treats code spacing around brackets the same', () => {
    expect(normalizeText('print ( "Merhaba" )')).toBe(normalizeText('print("Merhaba")'));
  });
  it('lowercases Turkish I correctly', () => {
    expect(normalizeText('İSİM')).toBe('isim');
  });
});

describe('grade', () => {
  it('multiple choice', () => {
    const payload = { options: ['a', 'b', 'c'] };
    expect(grade('MULTIPLE_CHOICE', payload, { index: 1 }, { index: 1 }).correct).toBe(true);
    expect(grade('MULTIPLE_CHOICE', payload, { index: 1 }, { index: 2 })).toEqual({ correct: false, correctAnswer: { index: 1 } });
    expect(() => grade('MULTIPLE_CHOICE', payload, { index: 1 }, { index: 9 })).toThrow(InvalidAnswerError);
    expect(() => grade('MULTIPLE_CHOICE', payload, { index: 1 }, { index: '1' })).toThrow(InvalidAnswerError);
  });

  it('true / false', () => {
    expect(grade('TRUE_FALSE', {}, { value: false }, { value: false }).correct).toBe(true);
    expect(grade('TRUE_FALSE', {}, { value: false }, { value: true }).correct).toBe(false);
    expect(() => grade('TRUE_FALSE', {}, { value: false }, { value: 'no' })).toThrow(InvalidAnswerError);
  });

  it('fill in the blank accepts any listed spelling', () => {
    const key = { accepted: ['colour', 'color'] };
    expect(grade('FILL_BLANK', {}, key, { text: ' Color ' }).correct).toBe(true);
    expect(grade('FILL_BLANK', {}, key, { text: 'colr' }).correct).toBe(false);
  });

  it('word order', () => {
    const payload = { words: ['student', 'I', 'a', 'am'] };
    const key = { sentence: 'I am a student' };
    expect(grade('WORD_ORDER', payload, key, { words: ['I', 'am', 'a', 'student'] }).correct).toBe(true);
    expect(grade('WORD_ORDER', payload, key, { words: ['am', 'I', 'a', 'student'] }).correct).toBe(false);
    expect(() => grade('WORD_ORDER', payload, key, { words: ['I', 'am', 'a', 'student', 'x'] })).toThrow(InvalidAnswerError);
  });

  it('matching needs every pair right', () => {
    const key = { pairs: { Hello: 'Merhaba', Please: 'Lütfen' } };
    expect(grade('MATCHING', {}, key, { pairs: { Hello: 'Merhaba', Please: 'Lütfen' } }).correct).toBe(true);
    expect(grade('MATCHING', {}, key, { pairs: { Hello: 'Lütfen', Please: 'Merhaba' } }).correct).toBe(false);
    expect(grade('MATCHING', {}, key, { pairs: { Hello: 'Merhaba' } }).correct).toBe(false);
  });

  it('rejects non-object answers', () => {
    expect(() => grade('TRUE_FALSE', {}, { value: true }, 'true')).toThrow(InvalidAnswerError);
  });
});
