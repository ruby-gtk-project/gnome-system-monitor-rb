# frozen_string_literal: true

require "adwaita"

require_relative "i18n"
require_relative "settings"
require_relative "units"

module GnomeSystemMonitor
  # The Cairo load graph behind all four charts on the Resources tab.
  #
  # This is upstream's load-graph.cpp draw path: a grid with labelled axes,
  # then one line (or stacked filled area) per series, drawn right to left
  # from the newest sample. The geometry constants, the y-axis bar counts and
  # the dynamic rescaling for the network and disk charts are upstream's —
  # they are what make the chart read the same.
  #
  # The background is redrawn with the rest of the frame rather than cached in
  # a surface as upstream caches it; at these sizes the grid is a handful of
  # lines.
  # ponytail: redraw the grid every frame, cache it in a surface if profiling
  # ever says the graph is hot.
  class LoadGraph
    include Translations

    FRAME_WIDTH = 4
    BORDER_ALPHA = 0.7
    GRID_ALPHA = 0.25
    INDENT = 18
    FONT_SIZE = 8.0
    VERTICAL_SECTIONS = 7

    # A sample that was never taken. Upstream fills the history with -1 and
    # skips those points, so a fresh graph draws only what it has measured.
    NO_DATA = -1.0

    # dynamic_scale()'s floor, so an idle network graph does not scale to
    # nothing.
    MINIMUM_MAX = 1024

    def initialize(type:, series:, num_points:, speed:)
      @type = type
      @series = series
      @num_points = num_points
      @speed = speed
      @colors = []
      @max = MINIMUM_MAX
      @recent_maxima = Array.new(num_points, 0)
      reset
    end

    attr_reader :type, :series, :num_points, :max
    attr_accessor :speed
    attr_accessor :colors, :stacked, :smooth, :logarithmic

    def build
      drawing_area.tap do |area|
        area.set_draw_func { |_area, context, width, height| draw(context, width, height) }
      end
    end

    def drawing_area
      @drawing_area ||= Gtk::DrawingArea.new.tap do |area|
        area.hexpand = true
        area.vexpand = true
        area.height_request = 70
        area.add_css_class("loadgraph")
      end
    end

    # load_graph_reset().
    def reset
      @data = Array.new(num_points) { Array.new(series, NO_DATA) }
      @iteration = 0
    end

    def num_points=(points)
      @num_points = points
      @recent_maxima = Array.new(points, 0)
      reset
    end

    # Rotate the history down one and write the newest sample at the front,
    # which is the right-hand edge of the chart.
    def push(partials)
      @data.rotate!(-1)
      @data[0] = partials
      @iteration += 1
      drawing_area.queue_draw
    end

    # The network and disk charts have no natural full scale, so the maximum
    # is chosen from the recent history and rounded to something that makes a
    # readable axis — and when it moves, the stored history is rescaled with
    # it so old samples keep meaning the same throughput.
    def push_rates(rate_in, rate_out)
      rescale(rate_in, rate_out)
      push([rate_in.to_f / max, rate_out.to_f / max])
    end

    def rescale(rate_in, rate_out)
      [rate_in, rate_out].max.then do |sample|
        @recent_maxima.rotate!(-1)
        @recent_maxima[0] = sample

        round_max([sample, @recent_maxima.max].max).then do |new_max|
          # A maximum that has only dipped a little is left alone, so the
          # chart is not constantly rescaling under a steady load.
          if new_max > max || new_max <= 0.8 * max
            apply_scale(new_max)
          end
        end
      end
    end

    def apply_scale(new_max)
      (max.to_f / new_max).then do |scale|
        @data.each do |point|
          point.map! { |value| value >= 0.0 ? value * scale : value }
        end
      end

      @max = new_max
    end

    # dynamic_scale()'s rounding: give the value a little headroom, then keep
    # a single significant digit of its leading power-of-1024 coefficient.
    def round_max(value)
      [(1.1 * value).to_i, MINIMUM_MAX].max.then do |padded|
        (Math.log2(padded).floor / 10).then do |base10|
          (1 << (base10 * 10)).then do |unit|
            (padded.to_f / unit).ceil.then do |coefficient|
              (10**Math.log10(coefficient).floor).then do |factor|
                (coefficient.to_f / factor).ceil * factor * unit
              end
            end
          end
        end
      end
    end

    def draw(context, width, height)
      (width - (2 * FRAME_WIDTH)).then do |inner_width|
        (height - (2 * FRAME_WIDTH)).then do |inner_height|
          num_bars(inner_height).then do |bars|
            ((inner_height - 15) / bars).then do |bar_height|
              geometry(
                inner_width,
                inner_height,
                bars,
                bar_height,
                bar_height * bars,
              ).then do |g|
                draw_background(context, g)
                draw_series(context, g)
              end
            end
          end
        end
      end
    end

    Geometry = Struct.new(
      :width,
      :height,
      :bars,
      :bar_height,
      :draw_height,
      :right_margin,
    )

    def geometry(width, height, bars, bar_height, draw_height)
      Geometry.new(
        width,
        height,
        bars,
        bar_height,
        draw_height,
        6 * FONT_SIZE,
      )
    end

    # gsm_graph_get_num_bars(): how many horizontal grid lines fit, kept to a
    # count that divides 100% evenly.
    def num_bars(height)
      (height / (FONT_SIZE + 14)).to_i.then do |fits|
        case
        when fits <= 1 then 1
        when fits <= 3 then 2
        when fits == 4 then 4
        when fits == 5 then logarithmic ? 4 : 5
        else logarithmic ? 6 : 5
        end
      end
    end

    def draw_background(context, g)
      context.save
      context.translate(FRAME_WIDTH, FRAME_WIDTH)
      context.set_line_width(0.25)

      draw_horizontal_grid(context, g)
      draw_vertical_grid(context, g)

      context.stroke
      context.restore
    end

    def draw_horizontal_grid(context, g)
      (0..g.bars).each do |index|
        (index * g.bar_height).then do |y|
          draw_label(
            context,
            g,
            horizontal_label_position(g, index, y),
            caption(index, g.bars),
            :end,
          )

          set_grid_color(context, index.zero? || index == g.bars)
          context.move_to(INDENT, y)
          context.line_to(g.width - g.right_margin + 4, y)
        end
      end
    end

    # The topmost label sits below its line and the bottom one above it, so
    # neither is clipped by the edge of the chart.
    def horizontal_label_position(g, index, y)
      case
      when index.zero? then [g.width - INDENT - 23, y + 0.5]
      when index == g.bars then [g.width - INDENT - 23, y - FONT_SIZE]
      else [g.width - INDENT - 23, y - (FONT_SIZE / 2)]
      end
    end

    def draw_vertical_grid(context, g)
      total_seconds.then do |total|
        (0...VERTICAL_SECTIONS).each do |index|
          ((index * (g.width - g.right_margin - INDENT)) / (VERTICAL_SECTIONS - 1).to_f).ceil.then do |x|
            (total - (index * total / (VERTICAL_SECTIONS - 1))).then do |seconds|
              draw_label(
                context,
                g,
                [x + INDENT, g.height - FONT_SIZE - 2],
                format_duration(seconds),
                vertical_label_alignment(index),
              )
            end

            set_grid_color(context, index.zero? || index == VERTICAL_SECTIONS - 1)
            context.move_to(x + INDENT, 0)
            context.line_to(x + INDENT, g.draw_height + 4)
          end
        end
      end
    end

    def vertical_label_alignment(index)
      case
      when index.zero? then :start
      when index == VERTICAL_SECTIONS - 1 then :end
      else :center
      end
    end

    # The whole chart's span: one sample per tick, two points held off the
    # ends for the smooth scroll.
    def total_seconds = (speed * (num_points - 2)).to_i

    def draw_label(context, _g, position, text, alignment)
      context.save
      context.select_font_face("Sans", Cairo::FontSlant::NORMAL, Cairo::FontWeight::NORMAL)
      context.set_font_size(0.9 * FONT_SIZE)
      foreground_color(context, 1.0)

      context.text_extents(text).then do |extents|
        case alignment
        when :end then context.move_to(position[0] - extents.width, position[1] + extents.height)
        when :center then context.move_to(position[0] - (extents.width / 2), position[1] + extents.height)
        else context.move_to(position[0], position[1] + extents.height)
        end
      end

      context.show_text(text)
      context.restore
    end

    # LoadGraph::get_caption(): what the y axis is counting depends on the
    # chart — a percentage, a network rate or a disk rate.
    def caption(index, bars)
      (100.0 - (index * 100.0 / bars)).then do |percentage|
        case type
        when :net then Units.rate((percentage * max / 100).to_i, Settings[Settings::NETWORK_IN_BITS])
        when :disk then Units.rate((percentage * max / 100).to_i, false)
        else percentage_caption(percentage, bars, index)
        end
      end
    end

    def percentage_caption(percentage, bars, index)
      if logarithmic
        (index == bars ? 0 : 100**(percentage / 100.0)).then do |value|
          # Translators: loadgraphs y axis percentage labels: 0 %, 50%, 100%
          format(_("%.0f %%"), value)
        end
      else
        format(_("%.0f %%"), percentage)
      end
    end

    # format_duration() from load-graph.cpp: hours, minutes and seconds, each
    # dropped when zero.
    def format_duration(seconds)
      [
        seconds / 3600,
        (seconds % 3600) / 60,
        seconds % 60,
      ].then do |(hours, minutes, remainder)|
        [
          hours.positive? ? n_("%u hr", "%u hrs", hours) % hours : nil,
          minutes.positive? ? n_("%u min", "%u mins", minutes) % minutes : nil,
          remainder.positive? ? n_("%u sec", "%u secs", remainder) % remainder : nil,
        ].compact.join(" ")
      end
    end

    def draw_series(context, g)
      context.save
      context.set_line_width(1)
      context.set_line_cap(Cairo::LINE_CAP_ROUND)
      context.set_line_join(Cairo::LINE_JOIN_ROUND)
      context.rectangle(
        INDENT + FRAME_WIDTH,
        FRAME_WIDTH,
        g.width - g.right_margin - INDENT,
        g.draw_height,
      )
      context.clip

      ((g.width - g.right_margin - INDENT) / (num_points - 2).to_f).then do |x_step|
        (g.width - g.right_margin + FRAME_WIDTH).then do |x_offset|
          (series - 1).downto(0) do |index|
            draw_one_series(
              context,
              g,
              index,
              x_step,
              x_offset,
            )
          end
        end
      end

      context.restore
    end

    # Drawn from the newest sample on the right back through the history. The
    # stacked form closes the path along the bottom and fills it; the line
    # form just strokes.
    def draw_one_series(context, g, index, x_step, x_offset)
      set_series_color(context, index)

      context.move_to(x_offset, FRAME_WIDTH + ((1.0 - @data[0][index]) * g.draw_height))

      (1...num_points).each do |point|
        if @data[point][index] != NO_DATA
          plot(
            context,
            g,
            index,
            point,
            x_step,
            x_offset,
          )
        end
      end

      if stacked
        context.line_to(x_offset - ((num_points - 1) * x_step), FRAME_WIDTH + g.draw_height)
        context.line_to(x_offset, FRAME_WIDTH + g.draw_height)
        context.close_path
        context.fill
      else
        context.stroke
      end
    end

    def plot(context, g, index, point, x_step, x_offset)
      (FRAME_WIDTH + ((1.0 - @data[point][index]) * g.draw_height)).then do |y|
        if smooth
          context.curve_to(
            x_offset - ((point - 0.5) * x_step),
            FRAME_WIDTH + ((1.0 - @data[point - 1][index]) * g.draw_height),
            x_offset - ((point - 0.5) * x_step),
            y,
            x_offset - (point * x_step),
            y,
          )
        else
          context.line_to(x_offset - (point * x_step), y)
        end
      end
    end

    def set_series_color(context, index)
      colors.fetch(index, nil).then do |color|
        if color
          context.set_source_rgba(
            color.red,
            color.green,
            color.blue,
            color.alpha,
          )
        else
          foreground_color(context, 1.0)
        end
      end
    end

    def set_grid_color(context, border)
      foreground_color(context, border ? BORDER_ALPHA : GRID_ALPHA)
    end

    # The chart's ink follows the theme's foreground colour, which is what
    # keeps it legible in both light and dark.
    def foreground_color(context, alpha)
      drawing_area.style_context.color.then do |color|
        context.set_source_rgba(
          color.red,
          color.green,
          color.blue,
          alpha,
        )
      end
    end
  end
end
