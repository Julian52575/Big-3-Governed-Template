// Prisma 7 reads the connection string here, not from schema.prisma.
// https://www.prisma.io/docs/orm/reference/prisma-config-reference
import { defineConfig } from "prisma/config";

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: { path: "prisma/migrations" },
  // Not env(): that throws when unset, and `prisma generate` runs in image
  // builds without a database.
  datasource: { url: process.env.DATABASE_URL ?? "" },
});
