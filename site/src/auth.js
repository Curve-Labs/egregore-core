// Admin users who can create new instances via /setup
export const ADMIN_USERS = ["oguzhan", "fcdagdelen"];

export function isAdmin(login) {
  return typeof login === "string" && ADMIN_USERS.includes(login);
}
