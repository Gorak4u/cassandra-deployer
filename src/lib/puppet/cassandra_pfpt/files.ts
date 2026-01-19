
import { backupScripts } from './files/backup';
import { binaryAssets } from './files/binary';
import { healthScripts } from './files/health';
import { maintenanceScripts } from './files/maintenance';
import { managementScripts } from './files/management';

export const files = {
  ...backupScripts,
  ...binaryAssets,
  ...healthScripts,
  ...maintenanceScripts,
  ...managementScripts,
};
