import EmbeddedPostgres from 'embedded-postgres';
import { existsSync, mkdirSync, rmSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'data', 'pg');
mkdirSync(root, { recursive: true });

const pg = new EmbeddedPostgres({
  databaseDir: root,
  user: 'deliveria',
  password: 'deliveria',
  port: 5433,
  persistent: true,
  initdbFlags: ['--encoding=UTF8', '--locale=C'],
});

if (!existsSync(join(root, 'PG_VERSION'))) {
  await pg.initialise();
} else {
  rmSync(join(root, 'postmaster.pid'), { force: true });
}
await pg.start();
try {
  await pg.createDatabase('deliveria');
} catch {
  // already created
}
console.info('PostgreSQL is running on 127.0.0.1:5433 (database deliveria)');
console.info('Leave this process open while the API is running.');
