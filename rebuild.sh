#!/bin/sh
# Full canon rebuild — all reels, story order for the Monsters prequel pair.
set -e
cd "$(dirname "$0")"
J=.venv/bin/jac
if [ -z "$OPENROUTER_API_KEY" ]; then
  export OPENROUTER_API_KEY=$(grep -E '^export OPENAI_API_KEY' ~/.zshrc | sed 's/^export OPENAI_API_KEY=//' | tr -d '"')
fi
if [ "$1" = "fresh" ]; then $J run main.jac reset; fi
$J run main.jac ingest data/home_alone_ep1.txt
$J run main.jac ingest data/home_alone_ep2.txt
$J run main.jac ingest data/got_s8e3.txt
$J run main.jac ingest data/got_s8e5.txt
$J run main.jac ingest data/monsters_university.txt   # prequel first: story order
$J run main.jac ingest data/monsters_inc.txt
$J run main.jac ingest data/final_destination_3.txt
$J run main.jac ingest data/lady_vanishes.txt
$J run main.jac audit
$J run main.jac score
$J run main.jac dump
echo "REBUILD COMPLETE"
