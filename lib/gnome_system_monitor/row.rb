# frozen_string_literal: true

require "adwaita"

module GnomeSystemMonitor
  # Builds the GObject classes the column views hold.
  #
  # GtkColumnView sorts with GtkStringSorter and GtkNumericSorter, both of
  # which read a GObject property through a GtkPropertyExpression — so every
  # field a column sorts on has to be a real property, not just a Ruby
  # attribute. `install_property` in these bindings wires a property to
  # accessors of the same name rather than defining them, so each field needs
  # both.
  module Row
    PARAMS = {
      string: ->(name) { GLib::Param::String.new(
        name,
        name,
        name,
        "",
        GLib::Param::READWRITE,
      ) },
      uint:   ->(name) { GLib::Param::UInt.new(
        name,
        name,
        name,
        0,
        2**32 - 1,
        0,
        GLib::Param::READWRITE,
      ) },
      int:    ->(name) { GLib::Param::Int.new(
        name,
        name,
        name,
        -2**31,
        2**31 - 1,
        0,
        GLib::Param::READWRITE,
      ) },
      uint64: ->(name) { GLib::Param::UInt64.new(
        name,
        name,
        name,
        0,
        2**63 - 1,
        0,
        GLib::Param::READWRITE,
      ) },
      double: ->(name) { GLib::Param::Double.new(
        name,
        name,
        name,
        0.0,
        1e12,
        0.0,
        GLib::Param::READWRITE,
      ) },
    }.freeze

    EMPTY = {
      string: "",
      double: 0.0,
    }.freeze

    module_function

    # Install `fields` — a hash of name to type — as properties on `klass`,
    # and give it the accessors and the blank starting values that go with
    # them.
    def install(klass, fields)
      fields.each do |name, type|
        klass.attr_accessor(name)
        klass.install_property(PARAMS.fetch(type).call(name.to_s))
      end

      klass.define_method(:clear_fields) do
        fields.each { |name, type| send(:"#{name}=", EMPTY.fetch(type, 0)) }
      end

      klass.define_method(:key) { send(fields.keys.first) }

      klass.define_method(:assign) do |values|
        values.each do |name, value|
          if send(name) != value
            send(:"#{name}=", value)
            notify(name.to_s)
          end
        end
      end
    end

    # A ready-made row class for the detail views, which only ever need a
    # fixed set of fields and a wholesale refresh. The GType name has to be
    # given: the class is anonymous, so there is no Ruby name to derive one
    # from.
    #
    # Cached by that name, because a GType can only be registered once — and
    # every Memory Maps window wants the same row class. Registering it twice
    # leaves a half-built type behind and the second window hangs on it.
    def define(type_name, fields)
      classes[type_name] ||= build_class(type_name, fields)
    end

    def classes = @classes ||= {}

    def build_class(type_name, fields)
      Class.new(GLib::Object) do
        type_register(type_name)
        Row.install(self, fields)

        def initialize
          super
          clear_fields
        end
      end
    end
  end
end
