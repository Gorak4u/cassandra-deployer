
import { backup_config } from './templates/backup_config';
import { backup_service } from './templates/backup_service';
import { backup_timer } from './templates/backup_timer';
import { cassandra_yaml } from './templates/cassandra_yaml';
import { coralogix_conf } from './templates/coralogix_conf';
import { cqlshrc } from './templates/cqlshrc';
import { jvm_options } from './templates/jvm_options';
import { limits_conf } from './templates/limits_conf';
import { rackdc_properties } from './templates/rackdc_properties';
import { range_repair_service } from './templates/range_repair_service';
import { service_override } from './templates/service_override';
import { sysctl_conf } from './templates/sysctl_conf';

export const templates = {
  'cassandra.yaml.erb': cassandra_yaml,
  'cassandra-rackdc.properties.erb': rackdc_properties,
  'jvm-server.options.erb': jvm_options,
  'cqlshrc.erb': cqlshrc,
  'range-repair.service.erb': range_repair_service,
  'cassandra_limits.conf.erb': limits_conf,
  'sysctl.conf.erb': sysctl_conf,
  'cassandra.service.d.erb': service_override,
  'coralogix-agent.conf.erb': coralogix_conf,
  'cassandra-full-backup.service.erb': backup_service.full,
  'cassandra-full-backup.timer.erb': backup_timer.full,
  'cassandra-incremental-backup.service.erb': backup_service.incremental,
  'cassandra-incremental-backup.timer.erb': backup_timer.incremental,
  'backup.config.json.erb': backup_config,
};
