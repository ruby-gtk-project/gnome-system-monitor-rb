# Known ruby-gnome / environment binding gaps

## test/test_binding_limits.rb — no-display (headless) GTK init

`test_binding_limits.rb` forks a subprocess with `DISPLAY` and
`WAYLAND_DISPLAY` unset, on the documented assumption (see its own header
comment, and `test/gtk_driver.rb`'s module comment) that GTK4 falls back to
an offscreen/broadway surface with no display server running at all.

In this fork's nix devShell, that assumption does not hold: the `gtk4`
package nixpkgs builds here has no broadway/headless GDK backend compiled
in, so `Gtk.init` itself raises `Gtk::InitError: failed to initialize GTK`
before any port code runs, for every variant (`safe`, `label`, `item`,
`expr`) — confirmed by running `ruby test/test_binding_limits.rb safe`
directly with `env -u DISPLAY -u WAYLAND_DISPLAY` and by setting
`GDK_BACKEND=broadway` explicitly (same `Gtk::InitError`).

This is an environment/binding gap, not a port bug: the actual invariant the
test exists to check — that filling a `GtkColumnView` cell's label inside
the `bind` callback and keeping no Ruby reference to the cell survives churn
(the pattern `lib/gnome_system_monitor/list_refresh.rb` relies on) —
genuinely holds. Run the same script under a real (virtual) display instead
of none at all and it passes:

```
nix develop --command xvfb-run -a ruby test/test_binding_limits.rb safe
# => survived
```

`test/drive_window.rb`, the primary proof that the port runs, is driven the
way the task requires — `nix develop --command xvfb-run -a ruby
test/drive_window.rb` — and is unaffected by this gap.
