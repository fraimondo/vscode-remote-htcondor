#!/bin/bash

VSCODE_REMOTE_HT_IDLE_TIMEOUT=${VSCODE_REMOTE_HT_IDLE_TIMEOUT:-600} # Time in seconds after which an idle job will be cancelled
VSCODE_REMOTE_HT_INSTALL_DIR=${VSCODE_REMOTE_HT_INSTALL_DIR:-"${HOME:-~}/.vscode-remote-htcondor"}
VSCODE_REMOTE_HT_NC_TIMEOUT=${VSCODE_REMOTE_HT_NC_TIMEOUT:-120} # Time in seconds after which nc will timeout if no traffic is present
# Uncomment for debugging
# VSCODE_REMOTE_HT_DEBUG=1

function debug_print ()
{
    if [ ! -z "$VSCODE_REMOTE_HT_DEBUG" ]; then
        >&2 echo "[DEBUG] $1"
    fi
}

function job_status ()
{
    # Print the JobStatus of job $1, or nothing if the job is no longer in the queue.
    # Returns non-zero if condor_q itself failed (e.g. busy scheduler), so the status is unknown.
    condor_q $1 -af JobStatus 2>/dev/null
}

function wait_for_job ()
{
    # Wait for job $1 to be running. Returns 1 if the job is held or leaves the queue.
    while true; do
        VSCODE_REMOTE_HT_JOB_STATE=$(job_status $1)
        if [ $? -ne 0 ]; then
            debug_print "condor_q failed, retrying"
            sleep 1
            continue
        fi
        case "$VSCODE_REMOTE_HT_JOB_STATE" in
            2)  debug_print "Job started"
                return 0 ;;
            1)  sleep 1 ;;
            5)  >&2 echo "Job $1 is on hold: $(condor_q $1 -af HoldReason)"
                return 1 ;;
            "") >&2 echo "Job $1 is no longer in the queue, check the logs in ${VSCODE_REMOTE_HT_INSTALL_DIR}/logs"
                return 1 ;;
            *)  >&2 echo "Job $1 is in unexpected state $VSCODE_REMOTE_HT_JOB_STATE"
                return 1 ;;
        esac
    done
}

function start ()
{
    # Lock so that concurrent connects don't submit more than one job.
    # Released once the job is submitted (or when the script exits).
    exec 9> "${VSCODE_REMOTE_HT_INSTALL_DIR}/.submit.lock"
    flock 9

    # check if there is already a job, if so, return with an error
    query_htcondor
    if [ ! -z "${VSCODE_REMOTE_HT_JOB_ID}" ]; then
        exec 9>&-
        >&2 echo "A job already exists with ID $VSCODE_REMOTE_HT_JOB_ID (node: ${VSCODE_REMOTE_HT_JOB_NODE:-none, not running yet})"
        return 1
    fi

    # submit job
    port=$(shuf -i 10000-65000 -n 1)
    # Use an array (not eval) so arguments with spaces or quotes are passed as-is
    params=(-batch-name "VSCODE_REMOTE_HT-${port}")
    if [ ! -z "$VSCODE_REMOTE_HT_REQUEST_CPUS" ]; then
        params+=("request_cpus=${VSCODE_REMOTE_HT_REQUEST_CPUS}")
    fi
    if [ ! -z "$VSCODE_REMOTE_HT_REQUEST_MEMORY" ]; then
        params+=("request_memory=${VSCODE_REMOTE_HT_REQUEST_MEMORY}")
    fi
    if [ ! -z "$VSCODE_REMOTE_HT_PRIORITY" ]; then
        params+=("priority=${VSCODE_REMOTE_HT_PRIORITY}")
    fi
    params+=("$@" "${VSCODE_REMOTE_HT_INSTALL_DIR}/vscode-remote.submit")
    debug_print "Running command: VSCODE_REMOTE_HT_JOB_PORT=${port} condor_submit $(printf '%q ' "${params[@]}")"
    output=$(VSCODE_REMOTE_HT_JOB_PORT=${port} condor_submit "${params[@]}")
    if [ $? -ne 0 ]; then
        debug_print "Output: $output"
        >&2 echo "Failed to submit job, exiting"
        >&2 echo $output
        exit 1
    fi
    debug_print "Output: $output"
    submit_id=$(echo $output | awk -F ' cluster ' '{print $2}' | awk -F '.' '{print $1}')
    if [ -z "$submit_id" ]; then
        >&2 echo "Could not parse the job ID from the condor_submit output: $output"
        exit 1
    fi
    debug_print "Submitted job with ID $submit_id"
    # The job is in the queue now, release the lock before starting the
    # monitor so it does not inherit it
    exec 9>&-

    # Start the monitor right away, so the job is cancelled even if we get
    # interrupted while waiting for it to start
    debug_print "Starting monitor for job ${submit_id}"
    if [ -z "$VSCODE_REMOTE_HT_DEBUG" ]; then
        log_file=/dev/null
    else
        log_file="${VSCODE_REMOTE_HT_INSTALL_DIR}/logs/vscode-remote-monitor.log"
        debug_print "Debug mode is on, sending monitor log to $log_file"
    fi
    debug_print "Running command: nohup ${SCRIPT_DIR}/vscode-remote-monitor.sh $submit_id < /dev/null > $log_file 2>&1 &"
    nohup "${SCRIPT_DIR}/vscode-remote-monitor.sh" $submit_id < /dev/null > "$log_file" 2>&1 &

    # wait for job to start
    wait_for_job $submit_id || exit 1

    # Update job vars
    query_htcondor
}

function stop()
{
    query_htcondor
    if [ ! -z "${VSCODE_REMOTE_HT_JOB_ID}" ]; then
        echo "Stopping job $VSCODE_REMOTE_HT_JOB_ID (node: ${VSCODE_REMOTE_HT_JOB_NODE:-none, not running yet})"
        cmd="condor_rm $VSCODE_REMOTE_HT_JOB_ID"
        debug_print "Running command: $cmd"
        eval $cmd
    else
        echo "No running job found"
    fi

    echo "Stopping all monitors"
    cmd="pkill -u $USER -f 'vscode-remote-monitor.sh'"
    eval $cmd

    echo "Stopping all nc processes"
    cmd="pkill -u $USER -f 'vscode-remote connect'"
    eval $cmd

}

function query_htcondor () 
{
    debug_print "Querying HTCondor for jobs with batch name VSCODE_REMOTE_HT-*"
    # A single condor_q with explicit attributes, so we don't depend on the
    # column layout of the default output.
    # If condor_q fails, retry: assuming there is no job would submit a duplicate.
    while true; do
        output=$(condor_q $USER -constraint 'regexp("^VSCODE_REMOTE_HT-", JobBatchName)' \
            -af ClusterId JobStatus RemoteHost JobBatchName 2>/dev/null)
        [ $? -eq 0 ] && break
        debug_print "condor_q failed, retrying"
        sleep 1
    done
    debug_print "Output: $output"

    # There should be only one job, use the first one
    read -r VSCODE_REMOTE_HT_JOB_ID VSCODE_REMOTE_HT_JOB_STATE remote_host batch_name <<< "$(echo "$output" | head -n 1)"
    if [ -z "$VSCODE_REMOTE_HT_JOB_ID" ]; then
        debug_print "No job found"
        unset VSCODE_REMOTE_HT_JOB_ID
        unset VSCODE_REMOTE_HT_JOB_STATE
        unset VSCODE_REMOTE_HT_JOB_NODE
        unset VSCODE_REMOTE_HT_JOB_PORT
        return
    fi
    # RemoteHost is "slot1_1@node" while running, "undefined" otherwise
    if [ "$remote_host" == "undefined" ]; then
        unset VSCODE_REMOTE_HT_JOB_NODE
    else
        VSCODE_REMOTE_HT_JOB_NODE=${remote_host#*@}
    fi
    VSCODE_REMOTE_HT_JOB_PORT=${batch_name#VSCODE_REMOTE_HT-}
    debug_print "Job ID: $VSCODE_REMOTE_HT_JOB_ID, Job State: $VSCODE_REMOTE_HT_JOB_STATE, Job Node: $VSCODE_REMOTE_HT_JOB_NODE, Job Port: $VSCODE_REMOTE_HT_JOB_PORT"
}

function connect () {
    # stdout is the SSH stream (ProxyCommand), all messages must go to stderr
    query_htcondor
    if [ -z "${VSCODE_REMOTE_HT_JOB_ID}" ]; then
        >&2 echo "No job found, starting a job first"
        # If another connect submitted a job in the meantime, start returns 1
        # and leaves that job's info in the VSCODE_REMOTE_HT_JOB_* vars
        start
    fi

    # It might happen that we have a job in the queue, but it is not running yet. 
    # In that case, we should wait for it to start before trying to connect to it.
    wait_for_job $VSCODE_REMOTE_HT_JOB_ID || exit 1

    # The node is only known once the job is running
    query_htcondor

    >&2 echo "Connecting to $VSCODE_REMOTE_HT_JOB_NODE"

    tries=0
    # Probe the port with bash's /dev/tcp: `nc -z` is not supported by all netcat variants
    while ! (: < /dev/tcp/$VSCODE_REMOTE_HT_JOB_NODE/$VSCODE_REMOTE_HT_JOB_PORT) 2>/dev/null; do
        tries=$((tries + 1))
        # If sshd fails to start (e.g. port in use), the job ends and we would wait forever.
        # condor_q is heavy on the scheduler, so only check every 10 tries.
        if [ $((tries % 10)) -eq 0 ]; then
            state=$(job_status $VSCODE_REMOTE_HT_JOB_ID)
            if [ $? -eq 0 ] && [ "$state" != "2" ]; then
                >&2 echo "Job $VSCODE_REMOTE_HT_JOB_ID stopped running before sshd was reachable, check the logs in ${VSCODE_REMOTE_HT_INSTALL_DIR}/logs"
                exit 1
            fi
        fi
        sleep 1
    done

    # Timeout NC Without traffic. This will not kill the job.
    # The monitor timeout will start running after this process ends.
    # Ncat (default on RHEL-like systems) uses -i for the idle timeout, -w is only the connect timeout
    if nc --version 2>&1 | grep -q Ncat; then
        nc -i $VSCODE_REMOTE_HT_NC_TIMEOUT $VSCODE_REMOTE_HT_JOB_NODE $VSCODE_REMOTE_HT_JOB_PORT
    else
        nc -w $VSCODE_REMOTE_HT_NC_TIMEOUT $VSCODE_REMOTE_HT_JOB_NODE $VSCODE_REMOTE_HT_JOB_PORT
    fi
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
