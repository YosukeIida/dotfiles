# Do everything.
all: init link defaults brew

# Set initial preference.
# install homebrew, xcode, Rosetta2
# run init.sh
init:
	@echo "\033[0;34mRun init.sh\033[0m"
	@.bin/init.sh
	@echo "\033[0;34mDone.\033[0m"

# Link dotfiles.
link:
	@echo "\033[0;34mRun link.sh\033[0m"
	@.bin/link.sh
	@echo "\033[0;34mDone.\033[0m"

# Set macOS system preferences.
defaults:
	@echo "\033[0;34mRun defaults.sh\033[0m"
	@.bin/defaults.sh
	@echo "\033[0;32mDone.\033[0m"

# Install macOS applications.
brew:
	@echo "\033[0;34mRun brew.sh\033[0m"
	@.bin/brew.sh
	@echo "\033[0;32mDone.\033[0m"

# Set Github
github:
	@echo "\033[0;34mRun github.sh\033[0m"
	@.bin/gitsetup.sh
	@echo "\033[0;32mDone.\033[0m"