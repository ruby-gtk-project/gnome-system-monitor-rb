# frozen_string_literal: true

require "adwaita"

module GnomeSystemMonitor
  # Makes a GtkColumnView re-read rows whose values changed in place.
  #
  # GTK4 list views bind a row to a cell once. Upstream's .ui files keep the
  # cells live with GtkBuilderListItemFactory `<binding>` elements, which
  # follow the property; neither route is open here.
  #
  #   * A GtkExpression binding (`gtk_expression_bind`) segfaults under these
  #     Ruby bindings as soon as list items start being recycled.
  #   * Holding the cell widget — to re-render it from a refresh — segfaults
  #     too: any Ruby reference to a list item or its child that outlives the
  #     bind callback corrupts the heap.
  #
  # Both are reproduced in `test/test_binding_limits.rb`. What is left is to
  # tell the model its items changed, which makes the view bind them again;
  # this restores the selection and the expanded rows around that, since an
  # items-changed drops both.
  module ListRefresh
    module_function

    # Announce the rows of `stores` whose key is in `keys`, one at a time, and
    # put `selection` and the expanded rows of `tree` back as they were —
    # GTK drops both for a row it is told has changed.
    #
    # One row at a time, and only the rows that moved: announcing a whole
    # store at once makes GTK tear down and rebuild every row it holds, and
    # that much churn is what these bindings fall over on.
    def announce(stores, keys, selection: nil, tree: nil)
      changed = positions(stores, keys)

      if !changed.empty?
        around(selection, tree) do
          changed.each { |(store, position)| store.items_changed(position, 1, 1) }
        end
      end
    end

    # Announce every row, for the lists short enough that walking them is
    # cheaper than tracking what changed.
    def announce_all(stores, selection: nil, tree: nil)
      around(selection, tree) do
        stores.each { |store| store.items_changed(0, store.n_items, store.n_items) }
      end
    end

    def around(selection, tree)
      expanded = keys_of(tree) { expanded_keys(tree) }
      selected = keys_of(selection) { selected_keys(selection) }

      yield

      # Nothing expanded and nothing selected means nothing to walk the model
      # for, which is the usual case and worth skipping: every one of these
      # walks reads rows the announcement has just rebuilt.
      if !expanded.empty?
        restore_expanded(tree, expanded)
      end

      if !selected.empty?
        restore_selected(selection, selected)
      end
    end

    # An absent model has no keys to put back.
    def keys_of(model)
      if model
        yield
      else
        []
      end
    end

    def positions(stores, keys)
      stores.flat_map do |store|
        (0...store.n_items).filter_map do |position|
          if keys.include?(store.get_item(position).key)
            [store, position]
          end
        end
      end
    end

    # Rows are identified by their key, not their position: a refresh can move
    # a row, and an exited process takes its position with it.
    def key_for(item)
      case item
      when Gtk::TreeListRow then key_for(item.item)
      when nil then nil
      else item.key
      end
    end

    def expanded_keys(tree)
      (0...tree.n_items).filter_map do |position|
        tree.get_row(position).then do |row|
          if row&.expanded?
            key_for(row)
          end
        end
      end.to_set
    end

    # Top-down, because expanding a row makes its children visible and so
    # lengthens the model as we go.
    def restore_expanded(tree, keys)
      position = 0

      while position < tree.n_items
        expand_if_wanted(tree, position, keys)
        position += 1
      end
    end

    def expand_if_wanted(tree, position, keys)
      tree.get_row(position).then do |row|
        if row && keys.include?(key_for(row))
          row.expanded = true
        end
      end
    end

    def selected_keys(selection)
      selection.selection.then do |bits|
        (0...bits.size).filter_map { |nth| key_for(selection.get_item(bits.get_nth(nth))) }
      end.to_set
    end

    def restore_selected(selection, keys)
      (0...selection.n_items).each do |position|
        if keys.include?(key_for(selection.get_item(position)))
          selection.select_item(position, false)
        end
      end
    end
  end
end
