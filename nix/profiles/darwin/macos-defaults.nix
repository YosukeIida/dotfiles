{
  username,
  homedir,
  ...
}:

{
  nix = {
    # Run Nix garbage collection automatically.
    gc = {
      automatic = true;
      interval = {
        Hour = 12;
        Minute = 0;
      };
      options = "--delete-older-than 7d";
    };

    settings = {
      # Allow builds to use binary substitutes when available.
      always-allow-substitutes = true;
    };
  };

  # Use Touch ID for sudo.
  security.pam.services.sudo_local.touchIdAuth = true;

  # Keep Touch ID sudo working inside tmux.
  security.pam.services.sudo_local.reattach = true;

  # macOS defaults managed by nix-darwin.
  system.defaults = {
    # Dock settings.
    dock = {
      # Auto-hide the Dock.
      autohide = true;

      # Dock icon size.
      tilesize = 67;

      # Place the Dock on the right.
      orientation = "right";

      # Hide recent apps in the Dock.
      show-recents = false;

      # Use the scale minimize effect.
      mineffect = "scale";

      # Keep System Settings pinned in the Dock.
      persistent-apps = [
        "/System/Applications/System Settings.app/"
      ];

      # Magnify Dock icons on hover.
      magnification = true;

      # Magnified Dock icon size.
      largesize = 30;

      # Minimize windows into app icons.
      minimize-to-application = true;

      # Keep Spaces in fixed order.
      mru-spaces = false;

      # Top-left hot corner: start screen saver.
      wvous-tl-corner = 5;

      # Top-right hot corner: Notification Center.
      wvous-tr-corner = 12;

      # Bottom-left hot corner: Launchpad.
      wvous-bl-corner = 11;

      # Bottom-right hot corner: Mission Control.
      wvous-br-corner = 2;
    };

    # Finder settings.
    finder = {
      # Show hidden files.
      AppleShowAllFiles = true;

      # Show the status bar.
      ShowStatusBar = true;

      # Show the path bar.
      ShowPathbar = true;

      # Use column view by default.
      FXPreferredViewStyle = "clmv";

      # Use the custom path below for new windows.
      NewWindowTarget = "Other";

      # Open new windows in Downloads.
      NewWindowTargetPath = "file://${homedir}/Downloads/";

      # Do not sort folders first.
      _FXSortFoldersFirst = false;

      # Keep extension-change warnings enabled.
      FXEnableExtensionChangeWarning = true;
    };

    # Global macOS settings.
    NSGlobalDomain = {
      # Use dark mode.
      AppleInterfaceStyle = "Dark";

      # Show all file extensions.
      AppleShowAllExtensions = true;

      # Fast key repeat.
      KeyRepeat = 2;

      # Short key repeat delay.
      InitialKeyRepeat = 15;

      # Disable spelling correction.
      NSAutomaticSpellingCorrectionEnabled = false;

      # Disable smart quotes.
      NSAutomaticQuoteSubstitutionEnabled = false;

      # Disable smart dashes.
      NSAutomaticDashSubstitutionEnabled = false;

      # Enable natural scrolling.
      "com.apple.swipescrolldirection" = true;
    };

    # Screenshot settings.
    screencapture = {
      # Save screenshots as PNG files.
      type = "png";
    };

    # Trackpad settings.
    trackpad = {
      # Enable tap to click.
      Clicking = true;

      # Enable two-finger right click.
      TrackpadRightClick = true;

      # Enable three-finger drag.
      TrackpadThreeFingerDrag = true;
    };

    # Defaults without first-class nix-darwin options.
    CustomUserPreferences = {
      "com.apple.AppleMultitouchTrackpad" = {
        # Click pressure: medium.
        FirstClickThreshold = 1;

        # Force Click pressure: medium.
        SecondClickThreshold = 1;

        # Enable haptic feedback.
        ActuateDetents = 1;

        # Keep Force Click enabled.
        ForceSuppressed = 0;

        # Disable three-finger tap lookup.
        TrackpadThreeFingerTapGesture = 0;
      };

      "com.apple.dock" = {
        # Top-left hot corner: no modifier.
        "wvous-tl-modifier" = 0;

        # Top-right hot corner: no modifier.
        "wvous-tr-modifier" = 0;

        # Bottom-left hot corner: no modifier.
        "wvous-bl-modifier" = 0;

        # Bottom-right hot corner: no modifier.
        "wvous-br-modifier" = 0;
      };

      "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
        # Click pressure: medium.
        FirstClickThreshold = 1;

        # Force Click pressure: medium.
        SecondClickThreshold = 1;

        # Enable haptic feedback.
        ActuateDetents = 1;

        # Keep Force Click enabled.
        ForceSuppressed = 0;
      };
    };
  };

  # Menu bar spacing is stored in the current-host global domain.
  # nix-darwin writes NSGlobalDomain to the regular global domain, so keep
  # these two ByHost keys in a small idempotent activation script.
  system.activationScripts.postActivation.text = ''
    echo >&2 "current-host macOS defaults..."
    launchctl asuser "$(id -u -- ${username})" \
      sudo --user=${username} -- \
      defaults -currentHost write -globalDomain NSStatusItemSpacing -int 1
    launchctl asuser "$(id -u -- ${username})" \
      sudo --user=${username} -- \
      defaults -currentHost write -globalDomain NSStatusItemSelectionPadding -int 1
  '';
}
