INSTALL_DIR=$HOME/.vscode-remote-htcondor
INSTALL_URL=https://raw.githubusercontent.com/fraimondo/vscode-remote-htcondor/refs/heads/main

function self_destruct() {
    echo "Self-destructing now! goodbye!"
    shred -u "$1"
}

filename=$(realpath $0)

echo "Installing vscode-remote in $INSTALL_DIR"

if [ -d "$INSTALL_DIR" ]; then
    echo "Installation exists in ${INSTALL_DIR}, shall we overwrite? (y/N)"
    read yn
    if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
        if [ -f "${INSTALL_DIR}/vscode-remote.submit" ]; then
            cp "${INSTALL_DIR}/vscode-remote.submit" "${INSTALL_DIR}.submit.bak"
            echo "Saved a backup of your submit file to ${INSTALL_DIR}.submit.bak"
        fi
        echo "Deleting all contents of ${INSTALL_DIR}"
        rm -r "${INSTALL_DIR}"
    else
        echo "Aborted"
        self_destruct $filename
        exit 1
    fi

fi


mkdir -p "${INSTALL_DIR}/logs"
echo "Created ${INSTALL_DIR}"

cd $INSTALL_DIR
echo "Downloading files"
for f in vscode-remote-common.sh vscode-remote-job.sh vscode-remote.submit vscode-remote-monitor.sh vscode-remote; do
    # -f: fail on HTTP errors instead of saving the error page as the script
    if ! curl -fsSLO "$INSTALL_URL/$f"; then
        echo "Failed to download $f, aborting"
        self_destruct $filename
        exit 1
    fi
done

chmod +x *.sh
chmod +x vscode-remote

echo "Download completed."
echo ""

SHELL_CMD=`readlink -f /proc/$$/exe`
SHELLNAME=$(basename -- "$SHELL_CMD")
if [ "$SHELLNAME" = "bash" ]; then
    echo "Do you want me to add the vscode-remote script to your PATH by adding it to your .bashrc? (y/N)"
    read yn
    if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
        echo "Adding $INSTALL_DIR to PATH in ~/.bashrc"
        echo "" >> ~/.bashrc
        echo "# Added by vscode-remote-htcondor installer on $(date)" >> ~/.bashrc
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> ~/.bashrc
        echo "Added $INSTALL_DIR to PATH in ~/.bashrc"
    else
        echo "You can manually add $INSTALL_DIR to your PATH by adding the following line to your .bashrc:"
        echo "export PATH=\"\$PATH:$INSTALL_DIR\""
    fi
elif [ "$SHELLNAME" = "zsh" ]; then
    echo "Do you want me to add the vscode-remote script to your PATH by adding it to your .zshrc? (y/N)"
    read yn
    if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
        echo "Adding $INSTALL_DIR to PATH in ~/.zshrc"
        echo "" >> ~/.zshrc
        echo "# Added by vscode-remote-htcondor installer on $(date)" >> ~/.zshrc
        echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> ~/.zshrc
        echo "Added $INSTALL_DIR to PATH in ~/.zshrc"
    else
        echo "You can manually add $INSTALL_DIR to your PATH by adding the following line to your .zshrc:"
        echo "export PATH=\"\$PATH:$INSTALL_DIR\""
    fi
else
    echo "Non-bash shell detected: $SHELLNAME"
    echo "I can't help you configure your PATH"
    echo "You can manually add $INSTALL_DIR to your PATH variable."
fi
echo ""
echo "Do you want me to help you create a configuration entry for you .ssh/config file on your local computer? (y/N)"
read yn
if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
    echo ""
    echo "Please tell me the hostname of the remote server (what you used to connect here!)"
    echo "If your cluster has several login nodes behind one name, use this specific login node: $(hostname -f 2>/dev/null || hostname)"
    read hostname

    echo ""
    echo "Now give me a short name for this hostname (it can be the same if it is already short)"

    read shortname

    echo "So this is what you need to add to your .ssh/config file in your local computer (not here!):"
    echo ""
    echo "Host ${shortname}-vscode"
    echo "    HostName ${hostname}"
    echo "    User ${USER}"
    echo "    ProxyCommand ssh ${USER}@${hostname} \"~/.vscode-remote-htcondor/vscode-remote connect\""
    echo "    HostKeyAlias ${shortname}-vscode"
    echo "    StrictHostKeyChecking accept-new"
    echo ""
    echo "The job always uses the same host key, so it is accepted on the first connection"
    echo "and checked from then on, no matter which compute node the job runs on."
    echo ""
    echo "If you are using a custom port, or key, or any particular config, then you will need to adapt this entry accordingly"
    echo ""
    echo "Have a nice day!"
else
    echo "You are on your own! Feel free to re-use me if you get stuck."
fi
echo ""
self_destruct $filename