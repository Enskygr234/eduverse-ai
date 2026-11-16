import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';

export const ROLE_KEYS = ['super_admin', 'admin', 'content_editor', 'moderator', 'support'] as const;
export type RoleKey = (typeof ROLE_KEYS)[number];

/** Restricts a route to users holding at least one of the given roles. */
export const Roles = (...roles: RoleKey[]) => SetMetadata(ROLES_KEY, roles);
