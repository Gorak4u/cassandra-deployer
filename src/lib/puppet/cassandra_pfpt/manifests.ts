
import { backup } from './manifests/backup';
import { config } from './manifests/config';
import { coralogix } from './manifests/coralogix';
import { firewall } from './manifests/firewall';
import { init } from './manifests/init';
import { install } from './manifests/install';
import { java } from './manifests/java';
import { jmx_exporter } from './manifests/jmx_exporter';
import { puppet } from './manifests/puppet';
import { roles } from './manifests/roles';
import { service } from './manifests/service';
import { system_keyspaces } from './manifests/system_keyspaces';

export const manifests = {
  'init.pp': init,
  'java.pp': java,
  'install.pp': install,
  'config.pp': config,
  'service.pp': service,
  'firewall.pp': firewall,
  'coralogix.pp': coralogix,
  'system_keyspaces.pp': system_keyspaces,
  'roles.pp': roles,
  'jmx_exporter.pp': jmx_exporter,
  'backup.pp': backup,
  'puppet.pp': puppet,
};
