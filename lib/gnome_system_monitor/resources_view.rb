# frozen_string_literal: true

require "adwaita"

require_relative "graph"
require_relative "i18n"
require_relative "settings"
require_relative "system_stats"
require_relative "units"

module GnomeSystemMonitor
  # The Resources tab: four expanders, each holding a LoadGraph and the
  # labels that spell out what it is drawing.
  #
  # The layout, the label wording and the colour pickers are interface.cpp's;
  # the sampling is load-graph.cpp's get_load/get_memory/get_net/get_disk,
  # reading SystemStats rather than libgtop.
  class ResourcesView
    include Translations

    # gsm_color_button's swatch width.
    COLOR_BUTTON_WIDTH = 32

    # Enough room for "100.0%" so the row does not shuffle sideways as the
    # numbers change.
    CPU_LABEL_CHARS = 6

    def initialize
      @cpu_count = SystemStats.cpu_count
      @previous = {}
    end

    attr_reader :cpu_count

    def build
      scrolled_window.tap do |sw|
        sw.child = box

        box.tap do |b|
          b.append(
            build_expander(
              cpu_expander,
              cpu_graph,
              cpu_table,
              "resources-cpu-expanded",
            ),
          )
          b.append(
            build_expander(
              memory_expander,
              memory_graph,
              memory_table,
              "resources-mem-expanded",
            ),
          )
          b.append(
            build_expander(
              network_expander,
              network_graph,
              network_table,
              "resources-net-expanded",
            ),
          )
          b.append(
            build_expander(
              disk_expander,
              disk_graph,
              disk_table,
              "resources-disk-expanded",
            ),
          )
        end

        build_cpu_table
        build_memory_table
        build_network_table
        build_disk_table
      end

      apply_settings
      scrolled_window
    end

    # Each section is an expander whose state is remembered, holding the graph
    # above the labels that describe it.
    def build_expander(expander, graph, table, setting)
      expander.tap do |e|
        e.child = Gtk::Box.new(:vertical, 6).tap do |content|
          content.margin_top = 6
          content.hexpand = true
          content.vexpand = true
          content.append(graph.build)
          content.append(table)
        end

        Settings.settings.bind(
          setting,
          e,
          "expanded",
          Gio::SettingsBindFlags::DEFAULT,
        )
        e.bind_property(
          "expanded",
          e,
          "vexpand",
          GLib::BindingFlags::DEFAULT,
        )
      end
    end

    # One sampling tick for every chart. Called on the graph interval.
    def update
      update_cpu
      update_memory
      update_network
      update_disk
    end

    # get_load(): each core's share of its own time since the last tick.
    def update_cpu
      SystemStats.cpu_times.then do |cpus|
        cpus.drop(1).each_with_index.map { |cpu, index| core_load(cpu, index) }.then do |loads|
          loads.each_with_index do |load, index|
            cpu_value_labels[index].label = Units.percentage(load * 100)
          end

          cpu_graph.push(stack(loads))
        end
      end
    end

    def core_load(cpu, index)
      @previous[[:cpu, index]].then do |last|
        @previous[[:cpu, index]] = cpu

        if last.nil?
          0.0
        else
          (cpu.total - last.total).then do |total|
            (cpu.used - last.used) / [total, 1].max.to_f
          end
        end
      end
    end

    # The stacked chart divides each core's load by the core count and adds
    # the one below it, so the areas pile up to the machine's total.
    def stack(loads)
      if Settings[Settings::CPU_STACKED_AREA_CHART]
        loads.each_with_index.map { |_load, index| loads[0..index].sum / loads.length.to_f }
      else
        loads
      end
    end

    # get_memory(): the memory line is the used fraction, the swap line is
    # dropped entirely when there is no swap.
    def update_memory
      SystemStats.memory.then do |memory|
        SystemStats.swap.then do |swap|
          (memory[:user].to_f / memory[:total]).then do |memory_fraction|
            (swap[:total].zero? ? 0.0 : swap[:used].to_f / swap[:total]).then do |swap_fraction|
              memory_label.label = memory_text(
                memory[:user],
                memory[:cached],
                memory[:total],
                memory_fraction,
              )
              swap_label.label = memory_text(
                swap[:used],
                0,
                swap[:total],
                swap_fraction,
              )
              swap_color_button.sensitive = swap[:total].positive?

              memory_graph.push(
                [
                  logarithmic(memory_fraction),
                                swap[:total].positive? ? logarithmic(swap_fraction) : LoadGraph::NO_DATA,
                ],
              )
            end
          end
        end
      end
    end

    # translate_to_log_partial_if_needed(): the memory chart can compress its
    # lower range so small amounts are still visible.
    def logarithmic(fraction)
      if Settings[Settings::LOGARITHMIC_SCALE] && fraction.positive?
        Math.log10(fraction * 100) / 2
      else
        fraction
      end
    end

    # set_memory_label_and_picker().
    def memory_text(used, cached, total, fraction)
      Settings[Settings::RESOURCES_MEMORY_IN_IEC].then do |iec|
        if total.zero?
          _("not available")
        else
          # xgettext: "540MiB (53 %) of 1.0 GiB" or "540MB (53 %) of 1.0 GB"
          format(
            _("%<used>s (%<percent>.1f%%) of %<total>s"),
            used:    Units.byte_size(used, iec),
            percent: 100.0 * fraction,
            total:   Units.byte_size(total, iec),
          ).then { |text| append_cache(text, cached, iec) }
        end
      end
    end

    def append_cache(text, cached, iec)
      if cached.zero?
        text
      else
        # xgettext: Used cache string, e.g.: "Cache 2.4GiB" or "Cache 2.4GB"
        [text, format(_("Cache %s"), Units.byte_size(cached, iec))].join("\n")
      end
    end

    def update_network
      SystemStats.network.then do |totals|
        rates(:net, totals[:in], totals[:out]).then do |(rate_in, rate_out)|
          Settings[Settings::NETWORK_IN_BITS].then do |bits|
            network_in_label.label = Units.rate(rate_in, bits)
            network_out_label.label = Units.rate(rate_out, bits)
          end

          Settings[Settings::NETWORK_TOTAL_IN_BITS].then do |total_bits|
            network_in_total_label.label = Units.volume(totals[:in], total_bits)
            network_out_total_label.label = Units.volume(totals[:out], total_bits)
          end

          network_graph.push_rates(rate_in, rate_out)
        end
      end
    end

    def update_disk
      SystemStats.disk.then do |totals|
        rates(:disk, totals[:read], totals[:write]).then do |(rate_read, rate_write)|
          disk_read_label.label = Units.rate(rate_read, false)
          disk_write_label.label = Units.rate(rate_write, false)
          disk_read_total_label.label = Units.volume(totals[:read], false)
          disk_write_total_label.label = Units.volume(totals[:write], false)

          disk_graph.push_rates(rate_read, rate_write)
        end
      end
    end

    # handle_dynamic_max_value(): rates come from the counter difference over
    # the wall time actually elapsed, and a counter that went backwards (an
    # interface that came and went) reads as no traffic rather than as a
    # spike.
    def rates(key, first, second)
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC).then do |now|
        @previous[key].then do |last|
          @previous[key] = [first, second, now]

          if last.nil? || first < last[0] || second < last[1]
            [0, 0]
          else
            (now - last[2]).then do |elapsed|
              [((first - last[0]) / elapsed).to_i, ((second - last[1]) / elapsed).to_i]
            end
          end
        end
      end
    end

    # The preference-driven flags the graphs read, applied on startup and
    # whenever one of them changes.
    def apply_settings
      Settings[Settings::GRAPH_DATA_POINTS].then do |points|
        graphs.each do |graph|
          graph.smooth = Settings[Settings::CPU_SMOOTH_GRAPH]
          graph.speed = Settings.graph_update_interval

          if graph.num_points != points
            graph.num_points = points
          end
        end
      end

      cpu_graph.stacked = Settings[Settings::CPU_STACKED_AREA_CHART]
      memory_graph.logarithmic = Settings[Settings::LOGARITHMIC_SCALE]
      apply_colors
      graphs.each { |graph| graph.drawing_area.queue_draw }
    end

    # The colours are settings too, so a change in Preferences shows up in the
    # chart and on its picker at once.
    def apply_colors
      @applying_colors = true
      set_colors
      @applying_colors = false
    end

    def set_colors
      cpu_graph.colors = cpu_colors
      cpu_colors.each_with_index { |color, index| cpu_color_buttons[index].rgba = color }

      memory_graph.colors = [color_setting("mem-color"), color_setting("swap-color")]
      memory_color_button.rgba = memory_graph.colors[0]
      swap_color_button.rgba = memory_graph.colors[1]

      network_graph.colors = [color_setting("net-in-color"), color_setting("net-out-color")]
      network_in_color_button.rgba = network_graph.colors[0]
      network_out_color_button.rgba = network_graph.colors[1]

      disk_graph.colors = [color_setting("disk-read-color"), color_setting("disk-write-color")]
      disk_read_color_button.rgba = disk_graph.colors[0]
      disk_write_color_button.rgba = disk_graph.colors[1]
    end

    # cpu-colors is a list of (index, colour) pairs, one per CPU the settings
    # have ever seen; a machine with more cores than the list covers reuses
    # the colours from the start.
    def cpu_colors
      Settings["cpu-colors"].then do |pairs|
        (0...cpu_count).map { |index| parse_color(pairs[index % pairs.length][1]) }
      end
    end

    def color_setting(key) = parse_color(Settings[key])

    def parse_color(text) = Gdk::RGBA.parse(text) || Gdk::RGBA.parse("#000000")

    def graphs = [cpu_graph, memory_graph, network_graph, disk_graph]

    # Widgets
    def scrolled_window
      @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |sw|
        sw.hexpand = true
        sw.vexpand = true
      end
    end

    def box
      @box ||= Gtk::Box.new(:vertical, 10).tap do |b|
        b.hexpand = true
        b.vexpand = true
        b.margin_top = 12
        b.margin_bottom = 30
        b.margin_start = 24
        b.margin_end = 24
      end
    end

    def cpu_expander = @cpu_expander ||= section_expander(_("CPU"))
    def memory_expander = @memory_expander ||= section_expander(_("Memory and Swap"))
    def network_expander = @network_expander ||= section_expander(_("Network"))
    def disk_expander = @disk_expander ||= section_expander(_("Disk"))

    def section_expander(title)
      Gtk::Expander.new.tap do |expander|
        expander.vexpand = true
        expander.expanded = true
        expander.label_widget = Gtk::Label.new(title).tap do |label|
          label.halign = :start
          label.margin_start = 6
          label.attributes = Pango::AttrList.new.tap do |attributes|
            attributes.insert(Pango::AttrWeight.new(Pango::Weight::BOLD))
          end
        end
      end
    end

    def cpu_graph
      @cpu_graph ||= LoadGraph.new(
        type:       :cpu,
        series:     cpu_count,
        num_points: Settings[Settings::GRAPH_DATA_POINTS],
        speed:      Settings.graph_update_interval,
      )
    end

    def memory_graph
      @memory_graph ||= LoadGraph.new(
        type:       :memory,
        series:     2,
        num_points: Settings[Settings::GRAPH_DATA_POINTS],
        speed:      Settings.graph_update_interval,
      )
    end

    def network_graph
      @network_graph ||= LoadGraph.new(
        type:       :net,
        series:     2,
        num_points: Settings[Settings::GRAPH_DATA_POINTS],
        speed:      Settings.graph_update_interval,
      )
    end

    def disk_graph
      @disk_graph ||= LoadGraph.new(
        type:       :disk,
        series:     2,
        num_points: Settings[Settings::GRAPH_DATA_POINTS],
        speed:      Settings.graph_update_interval,
      )
    end

    def cpu_table
      @cpu_table ||= Gtk::Grid.new.tap do |grid|
        grid.margin_start = 21
        grid.hexpand = true
        grid.row_spacing = 1
        grid.column_spacing = 6
        grid.row_homogeneous = true
        grid.column_homogeneous = true
      end
    end

    # Four columns, more on a machine with a great many cores, filled column
    # by column as interface.cpp fills them.
    def build_cpu_table
      (4 + (cpu_count / 32)).then do |columns|
        ((cpu_count + columns - 1) / columns).then do |rows|
          (0...cpu_count).each do |index|
            cpu_table.attach(
              cpu_row(index),
              index / rows,
              index % rows,
              1,
              1,
            )
          end
        end
      end
    end

    def cpu_row(index)
      Gtk::Box.new(:horizontal, 4).tap do |row|
        row.append(cpu_color_buttons[index])
        row.append(Gtk::Label.new(cpu_title(index)))
        row.append(cpu_value_labels[index])
      end
    end

    def cpu_title(index)
      if cpu_count == 1
        _("CPU")
      else
        format(_("CPU%d"), index + 1)
      end
    end

    def cpu_color_buttons
      @cpu_color_buttons ||= Array.new(cpu_count) do |index|
        color_button("cpu-colors", index)
      end
    end

    def cpu_value_labels
      @cpu_value_labels ||= Array.new(cpu_count) { tabular_label(CPU_LABEL_CHARS) }
    end

    def memory_table = @memory_table ||= label_grid(54)
    def network_table = @network_table ||= label_grid(54)
    def disk_table = @disk_table ||= label_grid(54)

    def label_grid(margin_start)
      Gtk::Grid.new.tap do |grid|
        grid.margin_start = margin_start
        grid.margin_end = 12
        grid.hexpand = true
        grid.column_spacing = 6
        grid.row_homogeneous = true
      end
    end

    def build_memory_table
      memory_table.tap do |grid|
        grid.attach(
          memory_color_button,
          0,
          0,
          1,
          2,
        )
        grid.attach(
          expanding_heading(_("Memory")),
          1,
          0,
          1,
          1,
        )
        grid.attach(
          memory_label,
          1,
          1,
          1,
          1,
        )
        grid.attach(
          swap_color_button,
          2,
          0,
          1,
          2,
        )
        grid.attach(
          expanding_heading(_("Swap")),
          3,
          0,
          1,
          1,
        )
        grid.attach(
          swap_label,
          3,
          1,
          1,
          1,
        )
      end
    end

    def build_network_table
      network_table.tap do |grid|
        grid.attach(
          network_in_color_button,
          0,
          0,
          1,
          2,
        )
        grid.attach(
          heading(_("Receiving")),
          1,
          0,
          1,
          1,
        )
        grid.attach(
          network_in_label,
          2,
          0,
          1,
          1,
        )
        grid.attach(
          heading(_("Total Received")),
          1,
          1,
          1,
          1,
        )
        grid.attach(
          network_in_total_label,
          2,
          1,
          1,
          1,
        )
        grid.attach(
          network_out_color_button,
          4,
          0,
          1,
          2,
        )
        grid.attach(
          heading(_("Sending")),
          5,
          0,
          1,
          1,
        )
        grid.attach(
          network_out_label,
          6,
          0,
          1,
          1,
        )
        grid.attach(
          heading(_("Total Sent")),
          5,
          1,
          1,
          1,
        )
        grid.attach(
          network_out_total_label,
          6,
          1,
          1,
          1,
        )
      end
    end

    def build_disk_table
      disk_table.tap do |grid|
        grid.attach(
          disk_read_color_button,
          0,
          0,
          1,
          2,
        )
        grid.attach(
          heading(_("Reading")),
          1,
          0,
          1,
          1,
        )
        grid.attach(
          disk_read_label,
          2,
          0,
          1,
          1,
        )
        grid.attach(
          heading(_("Total Read")),
          1,
          1,
          1,
          1,
        )
        grid.attach(
          disk_read_total_label,
          2,
          1,
          1,
          1,
        )
        grid.attach(
          disk_write_color_button,
          4,
          0,
          1,
          2,
        )
        grid.attach(
          heading(_("Writing")),
          5,
          0,
          1,
          1,
        )
        grid.attach(
          disk_write_label,
          6,
          0,
          1,
          1,
        )
        grid.attach(
          heading(_("Total Written")),
          5,
          1,
          1,
          1,
        )
        grid.attach(
          disk_write_total_label,
          6,
          1,
          1,
          1,
        )
      end
    end

    def heading(text)
      Gtk::Label.new(text).tap do |label|
        label.halign = :start
      end
    end

    def expanding_heading(text)
      heading(text).tap { |label| label.hexpand = true }
    end

    def memory_label = @memory_label ||= tabular_label(0)
    def swap_label = @swap_label ||= tabular_label(0)

    # The rate and total labels expand, so the two halves of the network and
    # disk tables share the width instead of the second half hugging the
    # right edge.
    def network_in_label = @network_in_label ||= value_label
    def network_out_label = @network_out_label ||= value_label
    def network_in_total_label = @network_in_total_label ||= value_label
    def network_out_total_label = @network_out_total_label ||= value_label
    def disk_read_label = @disk_read_label ||= value_label
    def disk_write_label = @disk_write_label ||= value_label
    def disk_read_total_label = @disk_read_total_label ||= value_label
    def disk_write_total_label = @disk_write_total_label ||= value_label

    def value_label
      tabular_label(0).tap do |label|
        label.hexpand = true
        label.margin_start = 6
      end
    end

    # make_tnum_label(): tabular figures, so a changing number does not shift
    # the text around it.
    def tabular_label(width_chars)
      Gtk::Label.new.tap do |label|
        label.halign = :start
        label.xalign = 0
        label.attributes = Pango::AttrList.new.tap do |attributes|
          attributes.insert(Pango::AttrFontFeatures.new("tnum=1"))
        end

        if width_chars.positive?
          label.width_chars = width_chars
        end
      end
    end

    def memory_color_button = @memory_color_button ||= color_button("mem-color", nil)
    def swap_color_button = @swap_color_button ||= color_button("swap-color", nil)
    def network_in_color_button = @network_in_color_button ||= color_button("net-in-color", nil)
    def network_out_color_button = @network_out_color_button ||= color_button("net-out-color", nil)
    def disk_read_color_button = @disk_read_color_button ||= color_button("disk-read-color", nil)
    def disk_write_color_button = @disk_write_color_button ||= color_button("disk-write-color", nil)

    # Upstream draws its own GsmColorButton; GTK4 ships a colour button of its
    # own now, so this uses that and writes the chosen colour straight back to
    # the setting the chart reads.
    def color_button(key, index)
      Gtk::ColorDialogButton.new(Gtk::ColorDialog.new).tap do |button|
        button.width_request = COLOR_BUTTON_WIDTH
        button.valign = :center

        button.signal_connect("notify::rgba") do
          store_color(key, index, button.rgba)
        end
      end
    end

    # apply_colors writes back to every picker, which would re-enter here
    # through notify::rgba — so a colour being applied is not a colour being
    # chosen.
    def store_color(key, index, rgba)
      if !@applying_colors
        hex_color(rgba).then do |hex|
          if index
            store_cpu_color(index, hex)
          else
            Settings[key] = hex
          end

          apply_colors
          graphs.each { |graph| graph.drawing_area.queue_draw }
        end
      end
    end

    def hex_color(rgba)
      [rgba.red, rgba.green, rgba.blue].map { |channel| (channel * 255).round }
                                       .then { |(red, green, blue)| format(
                                         "#%02x%02x%02x",
                                         red,
                                         green,
                                         blue,
                                       ) }
    end

    def store_cpu_color(index, hex)
      Settings["cpu-colors"].dup.then do |pairs|
        pairs[index] = [index, hex]
        Settings["cpu-colors"] = pairs
      end
    end
  end
end
