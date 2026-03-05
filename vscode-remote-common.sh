#!/bin/bash

VSCODE_REMOTE_HT_IDLE_TIMEOUT=${VSCODE_REMOTE_HT_IDLE_TIMEOUT:-600} # Time in seconds after which an idle job will be cancelled
VSCODE_REMOTE_HT_INSTALL_DIR=${VSCODE_REMOTE_HT_INSTALL_DIR:-"${HOME:-~}/.vscode-remote-htcondor"}
VSCODE_REMOTE_HT_NC_TIMEOUT=${VSCODE_REMOTE_HT_NC_TIMEOUT:-120} # Time in seconds after which nc will timeout if no traffic is present
# Uncomment for debugging
# VSCODE_REMOTE_HT_DEBUG=1

function debug_print ()
{
    if [ "$VSCODE_REMOTE_HT_DEBUG" == "1" ]; then
        >&2 echo "[DEBUG] $1"
    fi
}

function start ()
{
    # check if there is already a job running, if so, error
    query_htcondor
    if [ ! -z "${VSCODE_REMOTE_HT_JOB_NODE}" ]; then
        echo "A job is already running with ID $VSCODE_REMOTE_HT_JOB_ID on node $VSCODE_REMOTE_HT_JOB_NODE"
        exit 1
    fi

    # submit job
    port=$(shuf -i 10000-65000 -n 1)
    cmd="VSCODE_REMOTE_HT_JOB_PORT=${port} condor_submit -batch-name VSCODE_REMOTE_HT-${port} ${@} ${VSCODE_REMOTE_HT_INSTALL_DIR}/vscode_remote.submit"
    debug_print "Running command: $cmd"
    output=$(eval $cmd)
    if [ $? -ne 0 ]; then
        debug_print "Output: $output"
        >&2 echo "Failed to submit job, exiting"
        >&2 echo $output
        exit 1
    fi
    debug_print "Output: $output"
    submit_id=$(echo $output | awk -F ' cluster ' '{print $2}' | awk -F '.' '{print $1}')
    debug_print "Submitted job with ID $submit_id"
    
    # wait for job to start
    debug_print "Waiting for job ${submit_id} to start..."
    job_started=0
    while [ $job_started -eq 0 ]; do
        cmd="condor_q -long $submit_id"
        VSCODE_REMOTE_HT_JOB_STATE=$($cmd | grep "^JobStatus" | awk -F ' = ' '{print $2}')
        if [ "$VSCODE_REMOTE_HT_JOB_STATE" == "2" ]; then
            job_started=1
            debug_print "Job stated"
        else
            sleep 1
        fi
    done

    # Update job vars
    query_htcondor

    debug_print "Starting monitor for job ${VSCODE_REMOTE_HT_JOB_ID}"
    if [ -z "$VSCODE_REMOTE_HT_DEBUG" ]; then
        cmd="nohup ${SCRIPT_DIR}/vscode-remote-monitor.sh > /dev/null 2>&1 &"
    else
        log_file="${VSCODE_REMOTE_HT_INSTALL_DIR}/logs/vscode-remote-monitor.log"
        debug_print "Debug mode is on, sending monitor log to $log_file"
        cmd="${SCRIPT_DIR}/vscode-remote-monitor.sh > $log_file 2>&1 &"
    fi
    debug_print "Running command: $cmd"
    eval $cmd
}

function stop()
{
    query_htcondor
    if [ ! -z "${VSCODE_REMOTE_HT_JOB_NODE}" ]; then
        echo "Stopping running job $VSCODE_REMOTE_HT_JOB_ID on $VSCODE_REMOTE_HT_JOB_NODE"
        cmd="condor_rm $VSCODE_REMOTE_HT_JOB_ID"
        debug_print "Running command: $cmd"
        eval $cmd
    else
        echo "No running job found"
    fi
}

function query_htcondor () 
{
    debug_print "Querying HTCondor for running jobs with name VSCODE_REMOTE_HT"
    cmd="condor_q | grep VSCODE_REMOTE_HT"
    debug_print "Running command: $cmd"
    output=$(eval $cmd)
    if [ $? -ne 0 ]; then
        debug_print "Output: $output"
        debug_print "No job found"
        # no job found
        VSCODE_REMOTE_HT_JOB_ID=""
        VSCODE_REMOTE_HT_JOB_STATE=""
        VSCODE_REMOTE_HT_JOB_NODE=""
        VSCODE_REMOTE_HT_JOB_PORT=""
    else
        debug_print "Output: $output"
        # parse output to get job id, state and node
        debug_print "Job found"
        # this is very fragile and depends on the output format of condor_q, but it should work for now
        VSCODE_REMOTE_HT_JOB_ID=$(echo $output | awk '{print $9}')
        debug_print "Job ID: $VSCODE_REMOTE_HT_JOB_ID"
        cmd="condor_q -long $VSCODE_REMOTE_HT_JOB_ID"
        VSCODE_REMOTE_HT_JOB_STATE=$($cmd | grep "^JobStatus" | awk -F ' = ' '{print $2}')
        VSCODE_REMOTE_HT_JOB_NODE=$($cmd | grep "RemoteHost" | awk '{print $0}' | cut -d@ -f2 | cut -d\" -f1)
        VSCODE_REMOTE_HT_JOB_PORT=$($cmd | grep "JobBatchName" | awk -F ' = ' '{print $2}' | cut -d- -f2 | cut -d\" -f1)
        debug_print "Job ID: $VSCODE_REMOTE_HT_JOB_ID, Job State: $VSCODE_REMOTE_HT_JOB_STATE, Job Node: $VSCODE_REMOTE_HT_JOB_NODE, Job Port: $VSCODE_REMOTE_HT_JOB_PORT"
    fi
}

function connect () {
    query_htcondor
    if [ -z "${VSCODE_REMOTE_HT_JOB_NODE}" ]; then
        echo "No running job found, starting a job first"
        start
    fi

    echo "Connecting to $VSCODE_REMOTE_HT_JOB_NODE"

    while ! nc -z $VSCODE_REMOTE_HT_JOB_NODE $VSCODE_REMOTE_HT_JOB_PORT; do 
        timeout
        sleep 1 
    done

    # Timeout NC Without traffic. This will not kill the job.
    # The monitor timeout will start running after this process ends.
    nc -w $VSCODE_REMOTE_HT_NC_TIMEOUT $VSCODE_REMOTE_HT_JOB_NODE $VSCODE_REMOTE_HT_JOB_PORT
}

function clearlogs() {
    log_dir="${VSCODE_REMOTE_HT_INSTALL_DIR}/logs"
    if [ -d "$log_dir" ]; then
        echo "Clearing log files in $log_dir"
        rm -f $log_dir/*
    else
        echo "No log directory found at $log_dir, nothing to clear"
    fi
}