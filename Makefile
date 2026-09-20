PREFIX ?= /usr/local
DESTDIR ?=

APP_ID := org.gnome.SystemMonitor
GETTEXT_PACKAGE := gnome-system-monitor
PKGDIR := $(DESTDIR)$(PREFIX)/share/$(APP_ID)
BINDIR := $(DESTDIR)$(PREFIX)/bin
DATADIR := $(DESTDIR)$(PREFIX)/share

LANGUAGES := $(notdir $(basename $(wildcard po/*.po)))
HELPERS := gsm-kill gsm-renice gsm-taskset

.PHONY: run test lint install uninstall translations clean

# Run out of the checkout.
run:
	bundle exec ruby bin/gnome-system-monitor

test:
	bundle exec rubocop
	bundle exec ruby test/test_units.rb
	bundle exec ruby test/test_procfs.rb
	env -u DISPLAY -u WAYLAND_DISPLAY bundle exec ruby test/test_binding_limits.rb
	env -u DISPLAY -u WAYLAND_DISPLAY bundle exec ruby test/drive_window.rb
	appstreamcli validate --no-net data/$(APP_ID).metainfo.xml
	desktop-file-validate --no-hints data/$(APP_ID).desktop
	find po/ -type f -name "*.po" -print0 | xargs -0 -n1 msgfmt -o /dev/null --check

lint:
	bundle exec rubocop

# Compile the catalogues into data/locale, where Paths.locale_dir looks for
# them — so a checkout is translated too, not just an installed copy.
translations:
	for language in $(LANGUAGES); do \
		install -d data/locale/$$language/LC_MESSAGES; \
		msgfmt --output data/locale/$$language/LC_MESSAGES/$(GETTEXT_PACKAGE).mo po/$$language.po; \
	done

# lib/ and data/ stay siblings so lib/gnome_system_monitor/paths.rb finds the
# data next to it, exactly as it does in the checkout. bin/ too, because the
# polkit policy names the helpers by their installed path.
install: translations
	install -d $(PKGDIR)/lib $(PKGDIR)/data $(PKGDIR)/bin $(BINDIR)
	cp -r lib/. $(PKGDIR)/lib/
	cp -r data/. $(PKGDIR)/data/
	install -m 755 bin/gnome-system-monitor $(PKGDIR)/bin/gnome-system-monitor
	for helper in $(HELPERS); do install -m 755 bin/$$helper $(PKGDIR)/bin/$$helper; done
	glib-compile-schemas --strict $(PKGDIR)/data
	ln -sf $(PREFIX)/share/$(APP_ID)/bin/gnome-system-monitor $(BINDIR)/gnome-system-monitor
	install -Dm644 data/$(APP_ID).desktop $(DATADIR)/applications/$(APP_ID).desktop
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

uninstall:
	rm -rf $(PKGDIR)
	rm -f $(BINDIR)/gnome-system-monitor
	rm -f $(DATADIR)/applications/$(APP_ID).desktop
	rm -f $(DATADIR)/metainfo/$(APP_ID).metainfo.xml
	rm -f $(DATADIR)/glib-2.0/schemas/$(GETTEXT_PACKAGE).gschema.xml
	rm -f $(DATADIR)/polkit-1/actions/$(GETTEXT_PACKAGE).policy
	rm -f $(DATADIR)/icons/hicolor/scalable/apps/$(APP_ID).svg

clean:
	rm -rf data/locale data/gschemas.compiled tmp/shots
