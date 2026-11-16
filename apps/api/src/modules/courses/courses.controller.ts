import { Controller, Get, Param, Query } from '@nestjs/common';
import { IsOptional, IsString, Matches, MaxLength } from 'class-validator';
import { AuthUser, CurrentUser } from '../../common/decorators/current-user.decorator';
import { CoursesService } from './courses.service';

const SLUG = /^[a-z0-9-]{1,80}$/;

class ListCoursesQuery {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  @Matches(SLUG)
  category?: string;
}

@Controller()
export class CoursesController {
  constructor(private readonly courses: CoursesService) {}

  @Get('categories')
  categories() {
    return this.courses.listCategories();
  }

  @Get('courses')
  list(@CurrentUser() user: AuthUser, @Query() query: ListCoursesQuery) {
    return this.courses.listCourses(user.id, query.category);
  }

  @Get('courses/:slug')
  detail(@CurrentUser() user: AuthUser, @Param('slug') slug: string) {
    return this.courses.getCourse(user.id, SLUG.test(slug) ? slug : '__invalid__');
  }
}
