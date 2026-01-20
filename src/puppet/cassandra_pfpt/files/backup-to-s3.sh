#!/bin/bash
#
# THIS SCRIPT IS DEPRECATED AND SHOULD NOT BE USED.
# It is a non-functional prototype left over from early development.
#
# The modern, automated backup system uses the following scripts:
# - /usr/local/bin/full-backup-to-s3.sh
# - /usr/local/bin/incremental-backup-to-s3.sh
#
# These are managed by systemd timers and configured via Hiera.
# Please see the profile README for more details.
#

echo "ERROR: This script (backup-to-s3.sh) is deprecated and non-functional." >&2
echo "Please use 'full-backup-to-s3.sh' or 'incremental-backup-to-s3.sh'." >&2
exit 1
