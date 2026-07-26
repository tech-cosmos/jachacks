#!/bin/sh
# Continuity Walker — demo driver.
#   ./demo.sh prep    reset canon, ingest part 1 + GoT E3 (run BEFORE demo)
#   ./demo.sh find    ingest part 2 + GoT E5, audit → confirmed violations
#   ./demo.sh naive   what a raw LLM does with the same script (run twice!)
#   ./demo.sh amend   add the long-distance defense to canon → finding withdrawn
#   ./demo.sh score   extraction accuracy scoreboard
#   ./demo.sh contracts        MSA + amendments -> 2 confirmed inconsistencies
#   ./demo.sh contracts-amend  corrective amendment -> findings withdrawn
#   ./demo.sh serve   viz at http://localhost:8765
set -e
cd "$(dirname "$0")"
J=.venv/bin/jac
if [ -z "$OPENROUTER_API_KEY" ]; then
  export OPENROUTER_API_KEY=$(grep -E '^export OPENAI_API_KEY' ~/.zshrc | sed 's/^export OPENAI_API_KEY=//' | tr -d '"')
fi

case "$1" in
  prep)
    $J run main.jac reset
    $J run main.jac ingest data/home_alone_ep1.txt
    $J run main.jac ingest data/got_s8e3.txt
    $J run main.jac audit
    $J run main.jac dump
    ;;
  find)
    $J run main.jac ingest data/home_alone_ep2.txt
    $J run main.jac ingest data/got_s8e5.txt
    $J run main.jac audit
    $J run main.jac dump
    ;;
  naive)
    $J run main.jac naive data/home_alone_ep1.txt data/home_alone_ep2.txt
    ;;
  amend)
    $J run main.jac ingest data/home_alone_amendment.txt
    $J run main.jac audit
    $J run main.jac dump
    ;;
  score)
    $J run main.jac score
    $J run main.jac canon
    ;;
  contracts)
    # the "not just movies" beat: MSA + 2 amendments -> 2 CONFIRMED
    # drafting inconsistencies (or: jac run main.jac import canon_contracts.json
    # into an empty canon for the zero-LLM-call version)
    $J run main.jac ingest data/contract_msa.txt
    $J run main.jac ingest data/contract_amendment_1.txt
    $J run main.jac ingest data/contract_amendment_2.txt
    $J run main.jac audit
    $J run main.jac dump
    ;;
  contracts-amend)
    # corrective Amendment No. 3 restores the terms -> findings WITHDRAWN
    # (live version: paste it in the UI's AMENDMENT DESK tab instead)
    $J run main.jac ingest data/contract_amendment_3.txt
    $J run main.jac audit
    $J run main.jac dump
    ;;
  serve)
    $J run main.jac serve
    ;;
  *)
    echo "usage: ./demo.sh prep|find|naive|amend|score|contracts|contracts-amend|serve" ;;
esac
