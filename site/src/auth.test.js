// @vitest-environment node
import { describe, it, expect } from 'vitest';
import { isAdmin, ADMIN_USERS } from './auth';

describe('admin access gate', () => {
  it('allows oguzhan', () => {
    expect(isAdmin('oguzhan')).toBe(true);
  });

  it('allows fcdagdelen', () => {
    expect(isAdmin('fcdagdelen')).toBe(true);
  });

  it('rejects a random github user', () => {
    expect(isAdmin('random-person')).toBe(false);
  });

  it('rejects empty string', () => {
    expect(isAdmin('')).toBe(false);
  });

  it('rejects null/undefined', () => {
    expect(isAdmin(null)).toBe(false);
    expect(isAdmin(undefined)).toBe(false);
  });

  it('is case-sensitive (GitHub logins are lowercase)', () => {
    expect(isAdmin('Oguzhan')).toBe(false);
    expect(isAdmin('OGUZHAN')).toBe(false);
    expect(isAdmin('FcDagdelen')).toBe(false);
  });

  it('only has exactly 2 admins', () => {
    expect(ADMIN_USERS).toHaveLength(2);
    expect(ADMIN_USERS).toEqual(['oguzhan', 'fcdagdelen']);
  });
});
