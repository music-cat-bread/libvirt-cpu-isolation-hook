#!/usr/bin/env bash

set -e

CONFIG_FILE=/home/$(cat username)/tmp/hook/vm-config

HOST_CPU=NOTHING_FOUND

for i in $(cat $CONFIG_FILE); do
    if [[ $(echo $i | grep -Eo "^$1\..*") != "" ]]; then
        # TODO: Removing dot at the beginning of PRE is
        #       done on second line. If anybody knows
        #       how to reduce this pls fix
        HOST_CPU=$(echo $i | grep -Eo "\..*$")
        HOST_CPU=${HOST_CPU:1}
        break
    fi
done

if [[ $HOST_CPU != 'NOTHING_FOUND' ]]; then
    echo $HOST_CPU
else
    echo 'NUH UH'
    exit 1
fi
