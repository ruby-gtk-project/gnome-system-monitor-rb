{
  description = "gnome-system-monitor — a Ruby GTK4 port";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, utils }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Shared libraries every ruby-gnome extension links against.
        gtkStack = with pkgs; [
          glib
          gobject-introspection
          cairo
          pango
          gdk-pixbuf
          graphene
          atk
          gtk4
          libadwaita
          harfbuzz
          libgtop
        ]
        # The Ruby `pkg-config` gem resolves `Requires.private` transitively and
        # hard-fails if any .pc in the chain is missing, so gtk4's whole private
        # closure has to be on PKG_CONFIG_PATH, not just its public deps.
        ++ (with pkgs; [
          expat
          freetype
          fontconfig
          fribidi
          lerc
          libdatrie
          libdeflate
          libepoxy
          libpng
          libpthread-stubs
          libselinux
          libsepol
          libsysprof-capture
          libthai
          libwebp
          libxkbcommon
          libX11
          libXau
          libxcb
          libXdmcp
          libXext
          libXrender
          libXcursor
          libXfixes
          libXi
          libXinerama
          libXrandr
          xorgproto
          wayland
          zlib
          icu
          libffi
          brotli
          bzip2
          graphite2
          pcre2
          pixman
          util-linux
          xz
          zstd
          libyaml
        ]);

        # ruby-gnome gems build C extensions with extconf.rb + the pkg-config
        # gem; nixpkgs only ships gemConfig entries for the GTK3-era subset, so
        # the GTK4 gems get their build inputs declared here.
        rubyGnomeGem = _attrs: {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = gtkStack;
        };

        gemConfig = pkgs.defaultGemConfig // {
          gtk4 = rubyGnomeGem;
          gdk4 = rubyGnomeGem;
          gsk4 = rubyGnomeGem;
          adwaita = rubyGnomeGem;
          glib2 = rubyGnomeGem;
          gio2 = rubyGnomeGem;
          gobject-introspection = rubyGnomeGem;
          pango = rubyGnomeGem;
          gdk_pixbuf2 = rubyGnomeGem;
          cairo-gobject = rubyGnomeGem;
          atk = rubyGnomeGem;
        };

        # `makeSearchPath` would take each package's *first* output, and glib's
        # first output is `bin`, which carries no typelibs — hence the explicit
        # `.out`.
        typelibPath = pkgs.lib.makeSearchPath "lib/girepository-1.0"
          (map (drv: drv.out or drv) gtkStack);

        # nix/ and not the repo root: the root Gemfile is kettle-jem's
        # development bundle — rubocop, rspec, yard, the kettle-dev stack — and
        # must not end up in a packaged app's runtime closure. nix/Gemfile holds
        # the gemspec's runtime dependencies only.
        gems = pkgs.bundlerEnv {
          name = "gnome-system-monitor-rb-gems";
          ruby = pkgs.ruby_3_4;
          inherit gemConfig;
          gemdir = ./nix;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "gnome-system-monitor-devshell";

          nativeBuildInputs = with pkgs; [ pkg-config wrapGAppsHook4 ];

          packages = [
            gems
            gems.wrappedRuby
            pkgs.bundler
            pkgs.bundix
            pkgs.gettext
            pkgs.rubyPackages_3_4.gettext
            # The spec runner. The gems the full development bundle needs are
            # not in this shell — it carries the app's runtime closure — but
            # the suite is plain RSpec, so this is enough to run it.
            pkgs.rubyPackages_3_4.rspec
            pkgs.rubyPackages_3_4.minitest
            pkgs.gsettings-desktop-schemas
            pkgs.adwaita-icon-theme
            # This machine may have no display server at all, so the shell
            # carries one it can start itself: `xvfb-run ruby exe/<app>` both
            # launches the app and is how test/drive_window.rb is run.
            pkgs.xvfb-run
            # `make test` validates the appstream and desktop metadata, and
            # `make help` merges the help catalogues into the C pages and
            # checks they parse.
            pkgs.appstream
            pkgs.desktop-file-utils
            pkgs.itstool
            pkgs.libxml2
            pkgs.openssl
          ] ++ gtkStack;

          # Icons, GSettings schemas and the GTK portal all resolve through
          # XDG_DATA_DIRS; without these the window opens with blank icons.
          # RUBYLIB is what makes `ruby exe/gnome-system-monitor` and
          # `ruby test/drive_window.rb` work from a checkout: without it
          # `require "gnome_system_monitor"` only resolves against an
          # installed gem.
          shellHook = ''
            export XDG_DATA_DIRS="${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk4}/share/gsettings-schemas/${pkgs.gtk4.name}:${pkgs.adwaita-icon-theme}/share:$XDG_DATA_DIRS"
            export GI_TYPELIB_PATH="${typelibPath}''${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
            export RUBYLIB="$PWD/lib''${RUBYLIB:+:$RUBYLIB}"
            [ -d data/schemas ] && export GSETTINGS_SCHEMA_DIR="$PWD/data/schemas"
            unset BUNDLE_GEMFILE BUNDLE_FROZEN
            echo "gnome-system-monitor devshell — ruby $(ruby -e 'print RUBY_VERSION')"
            echo "run the app:   xvfb-run ruby exe/gnome-system-monitor"
            echo "drive the app: xvfb-run ruby test/drive_window.rb"
            echo "run the specs: ruby -e 'require \"rspec/core\"; exit RSpec::Core::Runner.run([\"--format\", \"progress\", \"--require\", \"spec_helper\", \"spec\"])'"
          '';
        };
      }
    );
}
