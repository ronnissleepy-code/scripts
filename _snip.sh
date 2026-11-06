#!/bin/sh
# does the rig-id sed actually fire? print each step.
. /tmp/.sysd/worker.env
ip=1.2.3.4
CMDS="\"-o\",\"$POOL\",\"-u\",\"$WALLET\",\"-p\",\"${RIG_ID:-node}\""
printf 'CMDS=%s\n' "$CMDS"
CMDH=$(printf '%s' "$CMDS" | sed "s|\"-p\",\"[^\"]*\"|\"-p\",\"$ip\"|")
printf 'AFTER489=%s\n' "$CMDH"
CMDH=$(printf '%s' "$CMDH" | sed "s|\"-p\",\"$ip\"|\"-p\",\"$ip\",\"--rig-id\",\"$ip\"|")
printf 'AFTERRIG=%s\n' "$CMDH"
echo "RIGID_IN_CMDH=$(printf '%s' "$CMDH" | grep -c rig-id)"
