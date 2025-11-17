# Install lua5.4
echo "Installing lua5.4..."
if sudo apt-get update && sudo apt-get install -y lua5.4; then
    echo "✅ lua5.4 installed successfully"
else
    echo "⚠️  Warning: lua5.4 installation failed, but continuing with codespace setup"
    echo "   You can manually install later by running: sudo apt-get update && sudo apt-get install -y lua5.4"
fi
