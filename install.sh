#!/bin/sh

# Create symlinks to dot files
create_symlinks() {
    # Get the directory in which this script lives.
    script_dir=$(dirname "$(readlink -f "$0")")

    # Get a list of all files in this directory that start with a dot.
    files=$(find -maxdepth 1 -type f -name ".*")

    # Create a symbolic link to each file in the home directory.
    for file in $files; do
        name=$(basename $file)
        echo "Creating symlink to $name in home directory."
        rm -rf ~/$name
        ln -s $script_dir/$name ~/$name
    done
}

# Install lua5.4
echo "Installing lua5.4..."
if sudo apt-get update && sudo apt-get install -y lua5.4; then
    echo "✅ lua5.4 installed successfully"
else
    echo "⚠️  Warning: lua5.4 installation failed, but continuing with codespace setup"
    echo "   You can manually install later by running: sudo apt-get update && sudo apt-get install -y lua5.4"
fi

create_symlinks
