#!/bin/zsh

# Install brew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
if [ "$(uname -m)" = "arm64" ] ; then
  (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> /Users/${USER}/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install xcode
# Check if command line tools are installed
if ! xcode-select --print-path &> /dev/null; then
  # Install command line tools
  echo "Command line tools not found. Installing..."
  xcode-select --install
else
  echo "Command line tools are already installed."
fi

# Install Rosetta 2 for Apple Silicon
# Check if Rosetta 2 is installed
if [[ $(sysctl -n machdep.cpu.brand_string) != *"Apple M"* ]]; then
  echo "Rosetta 2 is already installed."
  exit 0
fi

# Install Rosetta 2
/usr/sbin/softwareupdate --install-rosetta --agree-to-license
if [ $? -ne 0 ]; then
  echo "Error: Failed to install Rosetta 2."
  exit 1
fi

echo "Rosetta 2 has been installed successfully."
exit 0

# Install Fish shell
if ! command -v fish >/dev/null 2>&1; then
    echo "Installing Fish shell..."
    brew install fish
    # Add Fish to the list of valid shells
    echo "$(which fish)" | sudo tee -a /etc/shells
    # Change the default shell to Fish
    chsh -s "$(which fish)"
    echo "Fish shell installed and set as default."
else
    echo "Fish shell is already installed."
fi

# Install Fisher for Fish package management
if ! command -v fisher >/dev/null 2>&1; then
    echo "Installing Fisher..."
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
    echo "Fisher installed."
else
    echo "Fisher is already installed."
fi

# Install oh-my-fish/theme-bobthefish theme
if ! fish -c "fisher list | grep -q 'oh-my-fish/theme-bobthefish'"; then
    echo "Installing oh-my-fish/theme-bobthefish theme..."
    fish -c "fisher install oh-my-fish/theme-bobthefish"
    echo "oh-my-fish/theme-bobthefish theme installed."
else
    echo "oh-my-fish/theme-bobthefish theme is already installed."
fi
