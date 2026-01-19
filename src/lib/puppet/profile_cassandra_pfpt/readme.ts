
import { toc } from './readme/00_toc';
import { description } from './readme/01_description';
import { setup } from './readme/02_setup';
import { usage } from './readme/03_usage';
import { hiera } from './readme/04_hiera';
import { puppet_agent } from './readme/05_puppet_agent';
import { backup_restore } from './readme/06_backup_restore';
import { compaction } from './readme/07_compaction';
import { garbage_collection } from './readme/08_garbage_collection';
import { sstables } from './readme/09_sstables';
import { cleanup } from './readme/10_cleanup';
import { limitations } from './readme/11_limitations';
import { development } from './readme/12_development';

export const readme = `
${toc}
${description}
${setup}
${usage}
${hiera}
${puppet_agent}
${backup_restore}
${compaction}
${garbage_collection}
${sstables}
${cleanup}
${limitations}
${development}
`.trim();
