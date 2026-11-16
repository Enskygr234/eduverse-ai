import { IsObject, IsUUID } from 'class-validator';

export class SubmitAnswerDto {
  @IsUUID()
  questionId: string;

  /** Shape depends on question type; validated by the grader. */
  @IsObject()
  response: Record<string, unknown>;
}
