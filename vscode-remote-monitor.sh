#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/vscode-remote-common.sh

# wait for job to start
while [ -z "${VSCODE_REMOTE_JOB_NODE}" ] || [ "${VSCODE_REMOTE_JOB_STATE}" != "2" ]; do
    debug_print "Waiting for job to start..."
    sleep 5
    query_htcondor
done

# Monitor process to find a vscode-remote process, if there is
# no process after VSCODE_HTCONDOR_IDLE_TIMEOUT seconds, cancel the job and exit
IDLE_START=$(date +%s)
while true; do
    debug_print "Checking for vscode-remote process..."
    cmd="ps -ux | grep 'vscode-remote.sh connect' | grep -v grep"
    debug_print "Running command: $cmd"
    output=$(eval $cmd)
    if [ $? -ne 0 ]; then
        debug_print "Output: $output"
        debug_print "No vscode-remote process found"
        if [ $(($(date +%s) - IDLE_START)) -gt $VSCODE_HTCONDOR_IDLE_TIMEOUT ]; then
            debug_print "No vscode-remote process found for more than $VSCODE_HTCONDOR_IDLE_TIMEOUT seconds, canceling job and exiting" 
            cmd="condor_rm $VSCODE_REMOTE_JOB_ID"
            debug_print "Running command: $cmd"
            eval $cmd
            exit 1
        fi
    else
        debug_print "Output: $output"
        IDLE_START=$(date +%s)
    fi
    sleep 60
done