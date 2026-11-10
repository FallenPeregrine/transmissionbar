#!/bin/bash
cd "$(dirname "$0")" || exit 1
bash scripts/package-dmg.sh
result=$?
if [[ $result -ne 0 ]]; then
  printf '\nPackaging stopped with an error. Copy the error above when reporting it.\n'
fi
printf '\nPress Return to close.\n'
read -r
exit "$result"
