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

      # トラックパッドの軌跡の速さ（システム設定のスライダ相当）。
      "com.apple.trackpad.scaling" = 2.5;
    };

    # Screenshot settings.
    screencapture = {
      # Save screenshots as PNG files.
      type = "png";
    };

    # メニューバーの時計は時刻だけにする（曜日と日付を出さない）。
    # 24 時間表示はロケール由来なので Show24Hour / ShowAMPM は触らない。
    menuExtraClock = {
      ShowDate = 2; # 0=スペースがあるとき 1=常に 2=表示しない
      ShowDayOfWeek = false;
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
      NSGlobalDomain = {
        # マウスの軌跡の速さ。nix-darwin に第一級オプションが無い
        # （トラックパッド側の com.apple.trackpad.scaling だけ存在する）。
        "com.apple.mouse.scaling" = 1.5;

        # スクロールホイールの速さ。
        "com.apple.scrollwheel.scaling" = 0.75;
      };

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

  # ByHost（-currentHost）にしか書けない設定。nix-darwin の system.defaults は
  # 通常ドメインにしか書かないため、ここだけ冪等な activation スクリプトで扱う。
  system.activationScripts.postActivation.text = ''
    echo >&2 "current-host macOS defaults..."

    _byhost() {
      launchctl asuser "$(id -u -- ${username})" \
        sudo --user=${username} -- \
        defaults -currentHost write "$@"
    }

    # メニューバーのアイコン間隔を詰める。
    _byhost -globalDomain NSStatusItemSpacing -int 1
    _byhost -globalDomain NSStatusItemSelectionPadding -int 1

    # Spotlight の虫眼鏡アイコンをメニューバーから消す（検索機能自体は Raycast に寄せている）。
    _byhost com.apple.Spotlight MenuItemHidden -int 1

    # デフォルトブラウザ（Arc）。LaunchServices の割り当ては nix-darwin の
    # system.defaults では扱えないので duti で行う。
    # 既に Arc なら叩かない: macOS はデフォルトブラウザの変更時に確認ダイアログを
    # 出すことがあり、switch のたびに出ると鬱陶しいため。
    # Arc 未導入・duti 未配備でも switch は止めない（fail-soft）。
    _duti="/etc/profiles/per-user/${username}/bin/duti"
    if [ -d /Applications/Arc.app ] && [ -x "$_duti" ]; then
      _asuser() {
        launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- "$@"
      }
      if ! _asuser "$_duti" -x html 2>/dev/null | grep -qi 'company.thebrowser.Browser'; then
        echo >&2 "setting default browser to Arc..."
        for _scheme in http https public.html; do
          _asuser "$_duti" -s company.thebrowser.Browser "$_scheme" all || true
        done
      fi
    fi

    # Arc の全プロファイルに Bitwarden 拡張を入れる。
    #
    # Arc は Chromium ベースで、ArcCore.framework に ExtensionInstallForcelist の
    # 文字列が含まれている（＝ポリシー機構は組み込まれている）。machine ポリシーなので
    # プロファイルごとの手作業が不要になる。実際 Air では 7 プロファイル中 5 つにしか
    # 入っておらず、手動では抜けが出ていた。
    #
    # 副作用: 強制インストールなのでユーザーが削除・無効化できなくなる。
    # 将来 MDM を入れるならこのファイルは MDM が管理するので、ここでの書き込みは外すこと。
    # plist は heredoc で直接書く。`defaults write` は cfprefsd 経由で
    # /Library/Managed Preferences には書き込めず、ファイルが作られなかった
    # （2026-08-19、Mac Studio で chmod が No such file or directory で失敗）。
    if [ -d /Applications/Arc.app ]; then
      mkdir -p "/Library/Managed Preferences"
      cat > "/Library/Managed Preferences/company.thebrowser.Browser.plist" <<'ARCPOLICY'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>ExtensionInstallForcelist</key>
      <array>
        <string>nngceckbapebfimnlniiiahkandclblb;https://clients2.google.com/service/update2/crx</string>
      </array>
    </dict>
    </plist>
    ARCPOLICY
      chmod 644 "/Library/Managed Preferences/company.thebrowser.Browser.plist"
      plutil -lint "/Library/Managed Preferences/company.thebrowser.Browser.plist" >/dev/null \
        || echo >&2 "warning: Arc policy plist is malformed"
    fi
  '';
}
