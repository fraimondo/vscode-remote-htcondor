#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source $SCRIPT_DIR/vscode-remote-common.sh

# Usage: vscode-remote-monitor.sh JOB_ID
JOB_ID=$1
if [ -z "$JOB_ID" ]; then
    >&2 echo "Usage: $0 JOB_ID"
    exit 1
fi

# Monitor process to find a vscode-remote process, if there is
# no process for VSCODE_REMOTE_HT_IDLE_TIMEOUT seconds, cancel the job and exit.
# Time spent idle in the queue does not count, and we exit once the job leaves the queue.
IDLE_START=$(date +%s)
while true; do
    state=$(job_status $JOB_ID)
    if [ $? -ne 0 ]; then
        debug_print "condor_q failed, retrying later"
        sleep 60
        continue
    fi
    if [ -z "$state" ]; then
        debug_print "Job $JOB_ID is no longer in the queue, exiting"
        exit 0
    fi

    debug_print "Checking for vscode-remote process..."
    cmd="ps -ux | grep 'vscode-remote connect' | grep -v grep"
    debug_print "Running command: $cmd"
    output=$(eval $cmd)
    if [ $? -eq 0 ]; then
        debug_print "Output: $output"
        IDLE_START=$(date +%s)
    elif [ "$state" == "1" ]; then
        debug_print "Job $JOB_ID is still idle in the queue"
        IDLE_START=$(date +%s)
    else
        debug_print "No vscode-remote process found"
        now=$(date +%s)
        elapsed=$((now - IDLE_START))
        debug_print "Elapsed time without vscode-remote process: $elapsed seconds"
        debug_print "Idle timeout: $VSCODE_REMOTE_HT_IDLE_TIMEOUT seconds"
        if [ "$elapsed" -gt "$VSCODE_REMOTE_HT_IDLE_TIMEOUT" ]; then
            debug_print "No vscode-remote process found for more than $VSCODE_REMOTE_HT_IDLE_TIMEOUT seconds, canceling job and exiting"
            cmd="condor_rm $JOB_ID"
            debug_print "Running command: $cmd"
            eval $cmd
            exit 0
        fi
    fi
    sleep 60
done
