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

      # フォルダのスタックは Dock に置かない。工場出荷状態では Downloads が
      # 入っており、宣言していないと新マシンにだけ残る（Mac Studio で発覚）。
      persistent-others = [ ];

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

        # 3本指ドラッグ（trackpad.TrackpadThreeFingerDrag）を使うため、3本指スワイプは
        # 無効にして 4本指へ寄せる。この対応関係を宣言しないと、新マシンでは
        # 3本指スワイプが有効・4本指が無効という既定に戻る。
        TrackpadThreeFingerHorizSwipeGesture = 0;
        TrackpadThreeFingerVertSwipeGesture = 0;

        # 4本指: 横スワイプでデスクトップ切替、縦スワイプで Mission Control。
        TrackpadFourFingerHorizSwipeGesture = 2;
        TrackpadFourFingerVertSwipeGesture = 2;

        # ピンチで Launchpad / デスクトップを表示。
        TrackpadFourFingerPinchGesture = 2;
        TrackpadFiveFingerPinchGesture = 2;

        # ピンチズームと回転。
        TrackpadPinch = 1;
        TrackpadRotate = 1;

        # 右端から2本指スワイプで通知センター。
        TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
      };

      "com.apple.dock" = {
        # トラックパッドのジェスチャに対応する Mission Control 側のスイッチ。
        # 上の Trackpad*Gesture だけでは有効にならない。
        showMissionControlGestureEnabled = 1;
        showAppExposeGestureEnabled = 1;
        showDesktopGestureEnabled = 1;

        # Top-left hot corner: no modifier.
        "wvous-tl-modifier" = 0;

        # Top-right hot corner: no modifier.
        "wvous-tr-modifier" = 0;

        # Bottom-left hot corner: no modifier.
        "wvous-bl-modifier" = 0;

        # Bottom-right hot corner: no modifier.
        "wvous-br-modifier" = 0;
      };

      # 日本語入力（ことえり）。ライブ変換や句読点の種類はここ。
      # 反映には入力メソッドの再起動（ログアウト or 再ログイン）が必要な場合がある。
      "com.apple.inputmethod.Kotoeri" = {
        # ライブ変換（打ちながら自動で変換される機能）を切る。
        JIMPrefLiveConversionKey = 0;

        # 句読点の種類。3 = カンマ・ピリオド（，．）。
        JIMPrefPunctuationTypeKey = 3;

        # 自動修正と予測候補を切る。
        JIMPrefAutocorrectionKey = 0;
        JIMPrefPredictiveCandidateKey = 0;

        # 句読点の入力で変換を確定させない。
        JIMPrefConvertWithPunctuationKey = 0;

        # 数字は半角。
        JIMPrefFullWidthNumeralCharactersKey = 0;

        # Windows 風のキー操作。
        JIMPrefWindowsModeKey = 1;

        # Shift キーの動作。
        JIMPrefShiftKeyActionKey = 1;
      };

      # 入力ソースの構成（ABC + ことえりローマ字入力）。nix-darwin の hitoolbox には
      # AppleFnUsageType しか無いのでここで扱う。反映には再ログインが必要。
      "com.apple.HIToolbox" = {
        AppleEnabledInputSources = [
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = 252;
            "KeyboardLayout Name" = "ABC";
          }
          {
            "Bundle ID" = "com.apple.inputmethod.Kotoeri.RomajiTyping";
            "Input Mode" = "com.apple.inputmethod.Japanese";
            InputSourceKind = "Input Mode";
          }
          {
            "Bundle ID" = "com.apple.inputmethod.Kotoeri.RomajiTyping";
            InputSourceKind = "Keyboard Input Method";
          }
          {
            "Bundle ID" = "com.apple.CharacterPaletteIM";
            InputSourceKind = "Non Keyboard Input Method";
          }
          {
            "Bundle ID" = "com.apple.50onPaletteIM";
            InputSourceKind = "Non Keyboard Input Method";
          }
          {
            "Bundle ID" = "com.apple.PressAndHold";
            InputSourceKind = "Non Keyboard Input Method";
          }
        ];
      };

      # Magic Mouse。トラックパッドと同じく有線/内蔵側と Bluetooth 側の 2 ドメインに書く。
      # nix-darwin に第一級オプションが無いのでここで扱う（速度は NSGlobalDomain 側）。
      "com.apple.AppleMultitouchMouse" = {
        # 副ボタンを使う（右クリック有効）。
        MouseButtonMode = "OneButton";

        # 右クリックの境界位置。
        MouseButtonDivision = 55;

        # スクロールと慣性を有効化。
        MouseVerticalScroll = 1;
        MouseHorizontalScroll = 1;
        MouseMomentumScroll = 1;

        # 1本指ダブルタップは無効、2本指ダブルタップはスマートズーム。
        MouseOneFingerDoubleTapGesture = 0;
        MouseTwoFingerDoubleTapGesture = 3;

        # 2本指の横スワイプでページ間を移動。
        MouseTwoFingerHorizSwipeGesture = 2;
      };

      "com.apple.driver.AppleBluetoothMultitouch.mouse" = {
        MouseButtonMode = "OneButton";
        MouseButtonDivision = 55;
        MouseVerticalScroll = 1;
        MouseHorizontalScroll = 1;
        MouseMomentumScroll = 1;
        MouseOneFingerDoubleTapGesture = 0;
        MouseTwoFingerDoubleTapGesture = 3;
        MouseTwoFingerHorizSwipeGesture = 2;
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

        # ジェスチャは内蔵側と同一に揃える（Magic Trackpad 用）。
        TrackpadThreeFingerTapGesture = 0;
        TrackpadThreeFingerHorizSwipeGesture = 0;
        TrackpadThreeFingerVertSwipeGesture = 0;
        TrackpadFourFingerHorizSwipeGesture = 2;
        TrackpadFourFingerVertSwipeGesture = 2;
        TrackpadFourFingerPinchGesture = 2;
        TrackpadFiveFingerPinchGesture = 2;
        TrackpadPinch = 1;
        TrackpadRotate = 1;
        TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
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
