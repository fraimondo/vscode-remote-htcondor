#!/bin/bash

echo "Starting SSH server on port $1"

if [ ! -d "${HOME:-~}.ssh" ]; then
    echo "Creating .ssh directory in home"
    mkdir -p ${HOME:-~}/.ssh
fi

if [ ! -f "${HOME:-~}/.ssh/vscode-remote-hostkey" ]; then
    echo "Generating SSH host key for vscode remote"
    ssh-keygen -t ed25519 -f ${HOME:-~}/.ssh/vscode-remote-hostkey -N ""
fi

if [ -f "/usr/sbin/sshd" ]; then
    sshd_cmd=/usr/sbin/sshd
else
    sshd_cmd=sshd
fi

cmd="${sshd_cmd} -D -p $1 -f /dev/null -h ${HOME:-~}/.ssh/vscode-remote-hostkey"
echo "Running command: $cmd"
eval $cmd
