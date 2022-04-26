#!/bin/bash

source ./env.sh
alias python=python3

trap "pkill -P $$" EXIT

LOG_DIR=./logs
RUNNER_LOG=${LOG_DIR}/runner-$(date +"%Y_%m_%d_%I_%M_%p")

function log() {
  echo "$@"
  echo "$@" >> $RUNNER_LOG
}

function run() {
  test_envrc=$1
  baseline=$2
  if [[ ! -f "$test_envrc" ]]; then
    log "ERROR: $test_envrc is not a file that we can source"
    exit 1
  fi
  test_name=$(basename $test_envrc)
  test_name=${test_name%.env}

  # Optional
  export BASELINE_UUID=${baseline}
  # Unset because these may not be specified
  unset HAPROXY_IMAGE
  unset INGRESS_OPERATOR_IMAGE

  TEST_LOG_DIR=${LOG_DIR}/${test_name}-$(date +%Y-%m-%d)
  while [[ -d ${TEST_LOG_DIR} ]]; do
    TEST_LOG_DIR="${TEST_LOG_DIR}-1"
  done
  source ${test_envrc}
  if [[ $? -ne 0 ]]; then
    log "ERROR: Failed to source ${test_envrc}"
    exit 1
  fi
  mkdir -p $TEST_LOG_DIR
  LIMIT_ATTEMPTS=3
  ATTEMPT=1
  while [[ ! -f ${COMPARISON_OUTPUT} ]]; do
    TEST_LOG=${TEST_LOG_DIR}/log-${ATTEMPT}
    start=$(date +%s)
    log "Starting test attempt #${ATTEMPT} at $(date)"
    ./e2e-benchmarking/workloads/router-perf-v2/ingress-performance.sh &> $TEST_LOG
    end=$(date +%s)
    runtime=$((end-start))
    hours=$((runtime / 3600)); minutes=$(( (runtime % 3600) / 60 )); seconds=$(( (runtime % 3600) % 60 ));
    log "Test Exitted. Runtime: $hours:$minutes:$seconds (hh:mm:ss)"
    if [[ ! -f ${COMPARISON_OUTPUT} ]]; then
      log "ERROR: Test attempt #${ATTEMPT} failed. ${COMPARISON_OUTPUT} does not exist. Trying again."
      ATTEMPT=$((ATTEMPT+1))
      if [[ ${ATTEMPT} -gt ${LIMIT_ATTEMPTS} ]]; then
        log "ERROR: Giving up after ${LIMIT_ATTEMPTS} failed attempts"
	exit 1
      fi
    else
      log "Test attempt #${ATTEMPT} success!"
      log "Moving ${COMPARISON_OUTPUT} to $TEST_LOG_DIR"
      mv ${COMPARISON_OUTPUT} $TEST_LOG_DIR
      return
    fi
  done
}

if [ -t 1 ] ; then
  log "ERROR: You need to run this script with nohup for stablity"
  exit 1 
fi

if [[ -f ${COMPARISON_OUTPUT} ]]; then
  log "ERROR: Refusing to start because ${COMPARISON_OUTPUT} already exists"
  exit 1
fi

# Checkout e2e-benchmarking, the perf&scale repo
# Comment this out if you want to modify e2e-benchmarking temporarily
git submodule update --recursive
if [[ $? -ne 0 ]]; then
  log "ERROR: Failed to update e2e-benchmarking"
  exit 1
fi

#run "baseline" ./tests/replicas1-baseline.env
run ./tests/replicas1-weights-random.env "0f7354c4-1c7e-49a4-a7f3-fa196acfbc8b"
run ./tests/replicas1-weights.env "0f7354c4-1c7e-49a4-a7f3-fa196acfbc8b"
