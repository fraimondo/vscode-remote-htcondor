#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/vscode-remote-common.sh

# wait for job to start
timeout=300
while [ -z "${VSCODE_REMOTE_HT_JOB_NODE}" ] || [ "${VSCODE_REMOTE_HT_JOB_STATE}" != "2" ]; do
    debug_print "Waiting for any job to be running..."
    sleep 5
    query_htcondor
    timeout=$((timeout - 5))
    if [ $timeout -le 0 ]; then
        debug_print "Timeout waiting for job to start, exiting"
        exit 1
    fi
done

# Monitor process to find a vscode-remote process, if there is
# no process after VSCODE_HTCONDOR_IDLE_TIMEOUT seconds, cancel the job and exit
IDLE_START=$(date +%s)
while true; do
    debug_print "Checking for vscode-remote process..."
    cmd="ps -ux | grep 'vscode-remote connect' | grep -v grep"
    debug_print "Running command: $cmd"
    output=$(eval $cmd)
    if [ $? -ne 0 ]; then
        debug_print "Output: $output"
        debug_print "No vscode-remote process found"
        now=$(date +%s)
        elapsed=$((now - IDLE_START))
        debug_print "Elapsed time without vscode-remote process: $elapsed seconds"
        debug_print "Idle timeout: $VSCODE_REMOTE_HT_IDLE_TIMEOUT seconds"
        if [ "$elapsed" -gt "$VSCODE_REMOTE_HT_IDLE_TIMEOUT" ]; then
            debug_print "No vscode-remote process found for more than $VSCODE_REMOTE_HT_IDLE_TIMEOUT seconds, canceling job and exiting" 
            cmd="condor_rm $VSCODE_REMOTE_HT_JOB_ID"
            debug_print "Running command: $cmd"
            eval $cmd
            exit 0
        fi
        # do we actually have a job in the queue at this point? 
        # If not, we should probably exit immediately instead of waiting for the idle timeout
        query_htcondor
        if [ -z "${VSCODE_REMOTE_HT_JOB_ID}" ]; then
            debug_print "No job found in the queue, exiting"
            exit 0
        fi
    else
        debug_print "Output: $output"
        IDLE_START=$(date +%s)
    fi
    sleep 60
done