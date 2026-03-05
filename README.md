# vscode-remote-htcondor

A one-click script to setup and connect vscode to a HTCondor-based HTC compute node, directly from the VS Code remote explorer.

## Features

This script is designed to be used with the [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh) extension for Visual Studio Code.

- Automatically starts a job on a compute node if none is running
- Connects directly to a job.
- No need to manually execute the script on the HTC, just connect from the remote explorer and the script handles everything automagically through `ProxyCommand`.

## Requirements

- `sshd` must be available on the compute node, installed in `/usr/sbin` or available in the PATH
- A typical `sshd` installation is required, it must read login keys from `~/.ssh/authorized_keys`
- You must be allowed to run `sshd` in a job on an arbitrary port above 10000, and connect to it from the login node
- The `nc` command (netcat) must be available on the login node
- Compute node names must resolve to their internal IP addresses
- Compute nodes must be accessible via IP from the login node
- You must have SSH access to the HTC login node

## Installation

Just login to your HTC head node and run the following command to run the installation script. Follow the instructions!

```shell
curl -Os https://raw.githubusercontent.com/fraimondo/vscode-remote-htcondor/refs/heads/main/install.sh && $SHELL install.sh
```

The scripts will be installed in `~/.vscode-remote-htcondor`

## Usage

After you have installed the scripts, and if you followed the instructions, you should be able to connect to a compute node directly from the VS Code remote explorer, by connecting to the special host you've created. If no job is running, the scripts will automatically queue a job and connect to it as soon as it starts running. If a job is already running, it will connect to it directly.

### Running a special job on the cluster (once)

Sometimes you might need to run a special job on the cluster, for example to test if a specific configuration works, or to run a job with a specific number of CPUs or amount of memory. You can do this by running the `vscode-remote` script directly from the command line, and passing it the `start` command, for example:

```shell
~/.vscode-remote-htcondor/vscode-remote start
```

> [!IMPORTANT]
>
> - The job will be killed if no connections are active for more than 10 minutes (can be configured, see below). Make sure to connect within 10 minutes.
> - There will be only one job running, so if you want to change the configuration of the job, you will need to stop it first.

You can also stop a running job by passing the `stop` command:

```
~/.vscode-remote-htcondor/vscode-remote stop
```

You can additionally pass some parameters to customize the job submission, for example:

```shell
VSCODE-REMOTE_HT_REQUEST_CPUS=4 VSCODE-REMOTE_HT_REQUEST_MEMORY=16G ~/.vscode-remote-htcondor/vscode-remote start
```

Or even parameters to the `condor_submit` script:

```shell
~/.vscode-remote-htcondor/vscode-remote start request_cpus=4 request_memory=16G Requirements='Arch == "ppc64le"'
```

## Configuration

The vscode-remote-htcondor script is designed to work out of the box with a basic HTCondor setup, but it can be customized to fit your specific cluster configuration and requirements.

This is, in principle, done by setting environment variables. The files to edit depends on your shell:

- bash: `.bash_profile`, `.profile` or `.bashrc`
- zsh: `.zshenv`

### Controlling the behaviour of the scripts

The script has some environment variables that can be set to control its behaviour:

- `VSCODE-REMOTE_HT_IDLE_TIMEOUT`: time in seconds after which an idle job will be cancelled. Default is 600 seconds (10 minutes).
- `VSCODE-REMOTE_HT_NC_TIMEOUT`: time in seconds after which the bridge between the head node and the compute node will be killed. More technical explaination: `nc` command will timeout if no traffic is present. Default is 120 seconds (2 minutes). This will not kill the job, but it will allow the script to exit and the monitor timer to start running, which will check for idle jobs and cancel them if necessary.
- `VSCODE-REMOTE_HT_DEBUG`: If set, messages with debugging information will be printed.

### Customizing the job submission

By default, the script will submit a job with just a basic configuration, which should work on most HTCondor clusters:

```
# The environment
universe       = vanilla
getenv         = True

# Execution
initial_dir    = $ENV(HOME)
executable     = $ENV(HOME)/.vscode-remote-htcondor/vscode-remote-job.sh

# Logs
log            = $ENV(HOME)/.vscode-remote-htcondor/logs/vscode-remote-htcondor.log
output         = $ENV(HOME)/.vscode-remote-htcondor/logs/vscode-remote-htcondor.out
error          = $ENV(HOME)/.vscode-remote-htcondor/logs/vscode-remote-htcondor.err
```

There are two ways to configure the job submission. You can either 1) edit the `vscode-remote.submit` file directly, or 2) set some environment variables.

1. Editing the `vscode-remote.submit` file directly allows you to have full control over the job submission, and to use any HTCondor features you want, but keep in mind that any updates to the script may overwrite your changes, so it is recommended to keep a backup of your custom submit file.

2. There are two environment variables you can set to customize the job submission:

- `VSCODE-REMOTE_HT_REQUEST_CPUS`: if set, it will be used to request a specific number of CPUs for the job
- `VSCODE-REMOTE_HT_REQUEST_MEMORY`: if set, it will be used to request
  a specific amount of memory for the job (e.g. 8G for 8 GB)

## Troubleshooting

### VScode says something about issues with port-forwarding and it hangs waiting for something to happen?

Open the _Output_ tab in VSCode and look for the _Remote - SSH_ section. You should see some debug prints from the script, which can help you understand what is going on.

### The script fails to submit a job, and you see an error about "Failed to submit job, exiting"

This means that the `condor_submit` command failed to submit a job. The error message from `condor_submit` should be printed in the output, and can help you understand why the submission failed. Most probably you changed the job submit
configuration file and now it is not valid, or you are requesting resources that are not available on your cluster.
