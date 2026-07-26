#!/bin/sh
# Canon rebuild.
#   ./rebuild.sh          re-ingest the core demo set (skips already-ingested scenes)
#   ./rebuild.sh fresh    wipe canon first, then core set
#   ./rebuild.sh all      core set + the big transcripts (Monsters x2, Lady Vanishes)
set -e
cd "$(dirname "$0")"
J=.venv/bin/jac
if [ -z "$OPENROUTER_API_KEY" ] && [ "$CW_BACKEND" != "claude" ]; then
  export OPENROUTER_API_KEY=$(grep -E '^export OPENAI_API_KEY' ~/.zshrc | sed 's/^export OPENAI_API_KEY=//' | tr -d '"')
fi
if [ "$1" = "fresh" ]; then $J run main.jac reset; fi

# core set: the demo essentials (~37 scenes)
$J run main.jac ingest data/home_alone_ep1.txt
$J run main.jac ingest data/home_alone_ep2.txt
$J run main.jac ingest data/got_s8e3.txt
$J run main.jac ingest data/got_s8e5.txt
$J run main.jac ingest data/final_destination_3.txt   # real full transcript, proves scale

if [ "$1" = "all" ]; then
  $J run main.jac ingest data/monsters_university.txt  # prequel first: story order
  $J run main.jac ingest data/monsters_inc.txt
  $J run main.jac ingest data/lady_vanishes.txt
fi

$J run main.jac audit
$J run main.jac score
$J run main.jac dump
echo "REBUILD COMPLETE"
