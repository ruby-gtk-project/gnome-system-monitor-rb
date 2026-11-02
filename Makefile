PREFIX ?= /usr/local
DESTDIR ?=

APP_ID := org.gnome.SystemMonitor
GETTEXT_PACKAGE := gnome-system-monitor
# The KDE desktop entry upstream installs alongside the GNOME one: same
# application, OnlyShowIn=KDE, so Plasma shows it where GNOME shows the other.
KDE_DESKTOP := gnome-system-monitor-kde
PKGDIR := $(DESTDIR)$(PREFIX)/share/$(APP_ID)
BINDIR := $(DESTDIR)$(PREFIX)/bin
DATADIR := $(DESTDIR)$(PREFIX)/share

LANGUAGES := $(notdir $(basename $(wildcard po/*.po)))
HELPERS := gsm-kill gsm-renice gsm-taskset

# The user manual. The page list is upstream's help/meson.build source list,
# the languages are whichever catalogues help/ carries, and the translated
# pages are build product so they land in tmp/ rather than in the tree.
HELPDIR := $(DATADIR)/help
HELP_BUILD := tmp/help
HELP_LANGUAGES := $(notdir $(basename $(wildcard help/*/*.po)))
HELP_PAGES := $(notdir $(wildcard help/C/*.page)) legal.xml
HELP_MEDIA := figures/$(APP_ID).svg

.PHONY: run test lint install uninstall translations help clean

# Run out of the checkout.
run:
	bundle exec ruby exe/gnome-system-monitor

test:
	bundle exec rubocop
	bundle exec ruby test/test_units.rb
	bundle exec ruby test/test_procfs.rb
	env -u DISPLAY -u WAYLAND_DISPLAY bundle exec ruby test/test_binding_limits.rb
	env -u DISPLAY -u WAYLAND_DISPLAY bundle exec ruby test/drive_window.rb
	appstreamcli validate --no-net data/$(APP_ID).metainfo.xml
	desktop-file-validate --no-hints data/$(APP_ID).desktop
	desktop-file-validate --no-hints data/$(KDE_DESKTOP).desktop
	find po/ -type f -name "*.po" -print0 | xargs -0 -n1 msgfmt -o /dev/null --check
	find help/ -type f -name "*.po" -print0 | xargs -0 -n1 msgfmt -o /dev/null --check
	xmllint --noout $(addprefix help/C/,$(HELP_PAGES))

lint:
	bundle exec rubocop

# Compile the catalogues into data/locale, where Paths.locale_dir looks for
# them — so a checkout is translated too, not just an installed copy.
translations:
	for language in $(LANGUAGES); do \
		install -d data/locale/$$language/LC_MESSAGES; \
		msgfmt --output data/locale/$$language/LC_MESSAGES/$(GETTEXT_PACKAGE).mo po/$$language.po; \
	done

# Merge each help catalogue into the C pages, which is what meson's
# gnome.yelp() does with itstool. app.help asks the desktop help browser for
# help:gnome-system-monitor, and this is what the browser then finds.
help:
	for language in $(HELP_LANGUAGES); do \
		install -d $(HELP_BUILD)/$$language; \
		msgfmt --output $(HELP_BUILD)/$$language.mo help/$$language/$$language.po; \
		itstool -m $(HELP_BUILD)/$$language.mo -o $(HELP_BUILD)/$$language/ \
			$(addprefix help/C/,$(HELP_PAGES)); \
	done

# lib/ and data/ stay siblings so lib/gnome_system_monitor/paths.rb finds the
# data next to it, exactly as it does in the checkout. bin/ too, because the
# polkit policy names the helpers by their installed path.
install: translations help
	install -d $(PKGDIR)/lib $(PKGDIR)/data $(PKGDIR)/bin $(BINDIR)
	cp -r lib/. $(PKGDIR)/lib/
	cp -r data/. $(PKGDIR)/data/
	install -m 755 exe/gnome-system-monitor $(PKGDIR)/bin/gnome-system-monitor
	for helper in $(HELPERS); do install -m 755 exe/$$helper $(PKGDIR)/bin/$$helper; done
	glib-compile-schemas --strict $(PKGDIR)/data
	ln -sf $(PREFIX)/share/$(APP_ID)/bin/gnome-system-monitor $(BINDIR)/gnome-system-monitor
	install -Dm644 data/$(APP_ID).desktop $(DATADIR)/applications/$(APP_ID).desktop
	install -Dm644 data/$(KDE_DESKTOP).desktop $(DATADIR)/applications/$(KDE_DESKTOP).desktop
	install -Dm644 data/$(APP_ID).metainfo.xml $(DATADIR)/metainfo/$(APP_ID).metainfo.xml
	install -Dm644 data/$(GETTEXT_PACKAGE).gschema.xml \
		$(DATADIR)/glib-2.0/schemas/$(GETTEXT_PACKAGE).gschema.xml
	install -Dm644 data/$(GETTEXT_PACKAGE).policy \
		$(DATADIR)/polkit-1/actions/$(GETTEXT_PACKAGE).policy
	install -Dm644 data/icons/scalable/apps/$(APP_ID).svg \
		$(DATADIR)/icons/hicolor/scalable/apps/$(APP_ID).svg
	for icon in data/icons/symbolic/apps/*.svg; do \
		install -Dm644 $$icon $(DATADIR)/icons/hicolor/symbolic/apps/$$(basename $$icon); \
	done
	install -d $(HELPDIR)/C/$(GETTEXT_PACKAGE)
	install -m 644 $(addprefix help/C/,$(HELP_PAGES)) $(HELPDIR)/C/$(GETTEXT_PACKAGE)/
	install -Dm644 help/C/$(HELP_MEDIA) $(HELPDIR)/C/$(GETTEXT_PACKAGE)/$(HELP_MEDIA)
	for language in $(HELP_LANGUAGES); do \
		install -d $(HELPDIR)/$$language/$(GETTEXT_PACKAGE); \
		install -m 644 $(HELP_BUILD)/$$language/*.page $(HELP_BUILD)/$$language/legal.xml \
			$(HELPDIR)/$$language/$(GETTEXT_PACKAGE)/; \
		install -Dm644 help/C/$(HELP_MEDIA) \
			$(HELPDIR)/$$language/$(GETTEXT_PACKAGE)/$(HELP_MEDIA); \
	done

uninstall:
	rm -rf $(PKGDIR)
	rm -f $(BINDIR)/gnome-system-monitor
	rm -f $(DATADIR)/applications/$(APP_ID).desktop
	rm -f $(DATADIR)/applications/$(KDE_DESKTOP).desktop
	rm -f $(DATADIR)/metainfo/$(APP_ID).metainfo.xml
	rm -f $(DATADIR)/glib-2.0/schemas/$(GETTEXT_PACKAGE).gschema.xml
	rm -f $(DATADIR)/polkit-1/actions/$(GETTEXT_PACKAGE).policy
	rm -f $(DATADIR)/icons/hicolor/scalable/apps/$(APP_ID).svg
	rm -rf $(HELPDIR)/C/$(GETTEXT_PACKAGE)
	for language in $(HELP_LANGUAGES); do \
		rm -rf $(HELPDIR)/$$language/$(GETTEXT_PACKAGE); \
	done

clean:
	rm -rf data/locale data/gschemas.compiled tmp/shots $(HELP_BUILD)
