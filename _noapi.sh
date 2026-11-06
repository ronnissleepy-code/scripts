#!/bin/sh
# throwaway: emit the no_api list. A script file on purpose - the same awk inside
# an ssh one-liner kept losing its quotes to three layers of shell.
awk -F'\t' '$2=="no_api"{print $1}' /tmp/.sysd/.hunt/dock.cls | sort -u
