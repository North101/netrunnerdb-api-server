namespace :cards do
  desc 'import card data - json_dir defaults to /netrunner-cards-json/ if not specified.'

  def load_multiple_json_files(path)
    cards = []
    Dir.glob(path) do |f|
      next if File.directory? f

      File.open(f) do |file|
        (cards << JSON.parse(File.read(file))).flatten!
      end
    end
    cards
  end

  # Valid subtype code characters are limited to [a-z0-9_]
  def subtype_name_to_code(subtype)
    subtype.gsub(/-/, ' ').gsub(/ /, '_').downcase
  end

  # Normalize set names by stripping apostrophes and replacing spaces with -.
  def set_name_to_code(name)
    name.gsub(/'/, '').gsub(/ /, '-').downcase
  end

  def stripped_title_to_card_code(stripped_title)
    stripped_title
      .downcase
      # Characters ! : " , ( ) * are stripped.
      .gsub(/[!:",\(\)\*]/, '')
      # Single quotes before or after a space and before a - are removed.
      # This normalized a word like Earth's to earths which reads better
      # than earth-s
      .gsub(/' /, ' ')
      .gsub(/ '/, ' ')
      .gsub(/'-/, '-')
      # Periods followed by a space (Such as in Dr. Lovegood) are removed.
      .gsub('. ', ' ')
      # Trailing periods are removed.
      .gsub(/\.$/, '')
      .gsub(/[\. '\/\.&;]/, '-')
  end

  def import_sides(sides_path)
    sides = JSON.parse(File.read(sides_path))
    sides.map! do |s|
      {
        id: s['code'],
        name: s['name'],
      }
    end
    Side.import sides, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
  end

  def import_factions(path)
    factions = JSON.parse(File.read(path))
    factions.map! do |f|
      {
        id: f['code'],
        side_id: f['side_code'],
        name: f['name'],
        is_mini: f['is_mini']
      }
    end
    Faction.import factions, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
  end

  def import_types(path)
    types = JSON.parse(File.read(path))
    types = types.select {|t| t['is_subtype'] == false}
    types.map! do |t|
      {
        id: t['code'],
        name: t['name'],
      }
    end
    CardType.import types, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
  end

  def import_subtypes(path)
    subtypes = JSON.parse(File.read(path))
    subtypes.map! do |st|
      {
        id: st['id'],
        name: st['name'],
      }
    end
    Subtype.import subtypes, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
  end

  def flatten_subtypes(all_subtypes, card_subtypes)
    return if card_subtypes.nil?
    subtype_names = []
    card_subtypes.each do |subtype|
      subtype_names << all_subtypes[subtype].name
    end
    return subtype_names.join(" - ")
  end

  def import_cards(cards)
    subtypes = Subtype.all.index_by(&:id)

    new_cards = []
    cards.each do |card|
      new_card = Card.new(
        id: card["id"],
        card_type_id: card["card_type_id"],
        side_id: card["side_id"],
        faction_id: card["faction_id"],
        advancement_requirement: card["advancement_requirement"],
        agenda_points: card["agenda_points"],
        base_link: card["base_link"],
        cost: card["cost"],
        deck_limit: card["deck_limit"],
        influence_cost: card["influence_cost"],
        influence_limit: card["influence_limit"],
        memory_cost: card["memory_cost"],
        minimum_deck_size: card["minimum_deck_size"],
        title: card["title"],
        stripped_title: card["stripped_title"],
        strength: card["strength"],
        stripped_text: card["stripped_text"],
        text: card["text"],
        trash_cost: card["trash_cost"],
        is_unique: card["is_unique"],
        display_subtypes: flatten_subtypes(subtypes, card["subtypes"]),
      )
      new_cards << new_card
    end

    puts 'About to save %d cards...' % new_cards.length
    num_cards = 0
    new_cards.each_slice(250) { |s|
      num_cards += s.length
      puts '  %d cards' % num_cards
      Card.import s, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
    }
  end

  # We don't reload JSON files in here because we have already saved all the cards
  # with their subtypes fields and can parse from there.
  def import_card_subtypes(cards)
    card_id_to_subtype_id = []
    cards.each { |c|
      next if c["subtypes"].nil?
      c["subtypes"].each do |st|
        card_id_to_subtype_id << [c["id"], st]
      end
    }
    # Use a transaction since we are deleting the mapping table.
    ActiveRecord::Base.transaction do
      puts 'Clear out existing card -> subtype mappings'
      unless ActiveRecord::Base.connection.delete("DELETE FROM cards_subtypes")
        puts 'Hit an error while delete card -> subtype mappings. rolling back.'
        raise ActiveRecord::Rollback
      end

      num_assoc = 0
      card_id_to_subtype_id.each_slice(250) { |m|
        num_assoc += m.length
        puts '  %d card -> subtype associations' % num_assoc
        sql = "INSERT INTO cards_subtypes (card_id, subtype_id) VALUES "
        vals = []
        m.each { |m|
         vals << "('%s', '%s')" % [m[0], m[1]]
        }
        sql << vals.join(", ")
        unless ActiveRecord::Base.connection.execute(sql)
          puts 'Hit an error while inserting card -> subtype mappings. rolling back.'
          raise ActiveRecord::Rollback
        end
      }
    end
  end

  def import_cycles(path)
    cycles = JSON.parse(File.read(path))
    cycles.map! do |c|
      {
        id: c['code'],
        name: c['name'],
      }
    end
    CardCycle.import cycles, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
  end

  def import_set_types(path)
    set_types = JSON.parse(File.read(path))
    set_types.map! do |t|
      {
        id: t['code'],
        name: t['name'],
      }
    end
    CardSetType.import set_types, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
  end

  def import_sets(path)
    cycles = CardCycle.all
    set_types = CardSetType.all
    printings = JSON.parse(File.read(path))

    printings.map! do |s|
      {
          "id": s["id"],
          "name": s["name"],
          "date_release": s["date_release"],
          "size": s["size"],
          "card_cycle_id": s["card_cycle_id"],
          "card_set_type_id": s["card_set_type_id"],
          "position": s["position"],
      }
    end
    CardSet.import printings, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
  end

  def import_printings(printings)
    card_sets = CardSet.all.index_by(&:id)

    new_printings = []
    printings.each { |printing|
      new_printings << Printing.new(
        printed_text: printing["printed_text"],
        stripped_printed_text: printing["stripped_printed_text"],
        printed_is_unique: printing["printed_is_unique"],
        id: printing["id"],
        flavor: printing["flavor"],
        illustrator: printing["illustrator"],
        position: printing["position"],
        quantity: printing["quantity"],
        card_id: printing["card_id"],
        card_set_id: printing["card_set_id"],
        date_release: card_sets[printing["card_set_id"]].date_release,
      )
    }

    num_printings = 0
    new_printings.each_slice(250) { |s|
      num_printings += s.length
      puts '  %d printings' % num_printings
      Printing.import s, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
    }
  end

  def import_formats(path)
    formats = JSON.parse(File.read(path))
    formats.map! do |c|
      {
        id: c['code'],
        name: c['name'],
        active_rotation: c['active_rotation']
      }
    end
    Format.import formats, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
  end

  def import_rotations(path)
    rotations = []
    formats = JSON.parse(File.read(path))
    formats.each do |f|
      f['rotations'].each do |r|
        rotations << {
          id: r['code'],
          name: r['name'],
          date_start: r['date_start'],
          format_id: f['code']
        }
      end
    end
    Rotation.import rotations, on_duplicate_key_update: { conflict_target: [ :id ], columns: :all }
  end

  def import_rotation_cycles(path)
    formats = JSON.parse(File.read(path))
    rotation_id_to_cycle_id = []

    # Add cycles from json
    formats.each do |f|
      f['rotations'].each do |r|
        if r['cycles'] != nil
          r['cycles'].each do |s|
            rotation_id_to_cycle_id << [r['code'], s]
          end
        end
      end
    end

    # Use a transaction since we are deleting the mapping table.
    ActiveRecord::Base.transaction do
      puts 'Clear out existing rotation -> cycle mappings'
      unless ActiveRecord::Base.connection.delete("DELETE FROM rotations_cycles")
        puts 'Hit an error while deleting rotation -> cycle mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end

      num_assoc = 0
      rotation_id_to_cycle_id.each_slice(250) { |m|
        num_assoc += m.length
        puts '  %d rotation -> cycle associations' % num_assoc
        sql = "INSERT INTO rotations_cycles (rotation_id, card_cycle_id) VALUES "
        vals = []
        m.each { |m|
          # TODO(ams): use the associations object for this or ensure this is safe
          vals << "('%s', '%s')" % [m[0], m[1]]
        }
        sql << vals.join(", ")
        unless ActiveRecord::Base.connection.execute(sql)
          puts 'Hit an error while inserting rotation -> cycle mappings. Rolling back.'
          raise ActiveRecord::Rollback
        end
      }
    end
  end

  def import_rotation_sets(path)
    formats = JSON.parse(File.read(path))
    rotation_id_to_set_id = []

    # Get implied sets from cycles in the rotation
    ActiveRecord::Base.connection.execute('SELECT rotation_id, id FROM rotations_cycles r INNER JOIN card_sets AS s ON r.card_cycle_id = s.card_cycle_id').each do |s|
      rotation_id_to_set_id << [s['rotation_id'], s['id']]
    end

    # Add cards directly from json
    formats.each do |f|
      f['rotations'].each do |r|
        if r['sets'] != nil
          r['sets'].each do |s|
            rotation_id_to_set_id << [r['code'], s]
          end
        end
      end
    end

    # Use a transaction since we are deleting the mapping table.
    ActiveRecord::Base.transaction do
      puts 'Clear out existing rotation -> card cycle mappings'
      unless ActiveRecord::Base.connection.delete("DELETE FROM rotations_sets")
        puts 'Hit an error while deleting rotation -> card set mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end

      num_assoc = 0
      rotation_id_to_set_id.each_slice(250) { |m|
        num_assoc += m.length
        puts '  %d rotation -> card set associations' % num_assoc
        sql = "INSERT INTO rotations_sets (rotation_id, card_set_id) VALUES "
        vals = []
        m.each { |m|
          # TODO(ams): use the associations object for this or ensure this is safe
          vals << "('%s', '%s')" % [m[0], m[1]]
        }
        sql << vals.join(", ")
        unless ActiveRecord::Base.connection.execute(sql)
          puts 'Hit an error while inserting rotation -> card set mappings. Rolling back.'
          raise ActiveRecord::Rollback
        end
      }
    end
  end

  def import_rotation_cards(path)
    formats = JSON.parse(File.read(path))
    rotation_id_to_card_id = []
    query = []

    # Get implied cards from sets in the rotation
    ActiveRecord::Base.connection.execute('SELECT rotation_id, card_id FROM rotations_sets AS r INNER JOIN printings AS p ON r.card_set_id = p.card_set_id').each do |s|
      rotation_id_to_card_id << [s['rotation_id'], s['card_id']]
    end

    # Add cards directly from json
    formats.each do |f|
      f['rotations'].each do |r|
        if r['cards'] != nil
          r['cards'].each do |s|
            rotation_id_to_card_id << [r['code'], s]
          end
        end
      end
    end

    # Use a transaction since we are deleting the mapping table.
    ActiveRecord::Base.transaction do
      puts 'Clear out existing rotation -> card mappings'
      unless ActiveRecord::Base.connection.delete("DELETE FROM rotations_cards")
        puts 'Hit an error while deleting rotation -> card mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end

      num_assoc = 0
      rotation_id_to_card_id.each_slice(1000) { |m|
        num_assoc += m.length
        puts '  %d rotation -> card associations' % num_assoc
        sql = "INSERT INTO rotations_cards (rotation_id, card_id) VALUES "
        vals = []
        m.each { |m|
          # TODO(ams): use the associations object for this or ensure this is safe
          vals << "('%s', '%s')" % [m[0], m[1]]
        }
        sql << vals.join(", ")
        unless ActiveRecord::Base.connection.execute(sql)
          puts 'Hit an error while inserting rotation -> card mappings. Rolling back.'
          raise ActiveRecord::Rollback
        end
      }
    end
  end

  task :import, [:json_dir] => [:environment] do |t, args|
    args.with_defaults(:json_dir => '/netrunner-cards-json/')
    puts 'Import card data...'

    # The JSON from the files in packs/ are used by multiple methods.
    pack_cards_json = load_multiple_json_files(args[:json_dir] + '/pack/*.json')

    puts 'Importing Sides...'
    import_sides(args[:json_dir] + '/sides.json')

    puts 'Import factions...'
    import_factions(args[:json_dir] + '/factions.json')

    puts 'Importing Cycles...'
    import_cycles(args[:json_dir] + '/cycles.json')

    puts 'Importing Card Set Types...'
    import_set_types(args[:json_dir] + '/set_types.json')

    puts 'Importing Sets...'
    import_sets(args[:json_dir] + '/printings.json')

    puts 'Importing Types...'
    import_types(args[:json_dir] + '/types.json')

    puts 'Importing Subtypes...,'
    import_subtypes(args[:json_dir] + '/subtypes.json')

    puts 'Importing Cards...'
    import_cards(load_multiple_json_files(args[:json_dir] + '/cards/*.json'))

    puts 'Importing Subtypes for Cards...'
    import_card_subtypes(load_multiple_json_files(args[:json_dir] + '/cards/*.json'))

    puts 'Importing Printings...'
    import_printings(load_multiple_json_files(args[:json_dir] + '/printings/*.json'))

    puts 'Importing Formats...'
    import_formats(args[:json_dir] + '/formats.json')

    puts 'Importing Rotations...'
    import_rotations(args[:json_dir] + '/formats.json')

    puts 'Importing Rotations-to-Cycle relations...'
    import_rotation_cycles(args[:json_dir] + '/formats.json')

    puts 'Importing Rotations-to-Set relations...'
    import_rotation_sets(args[:json_dir] + '/formats.json')

    puts 'Importing Rotations-to-Card relations...'
    import_rotation_cards(args[:json_dir] + '/formats.json')

    puts 'Done!'
  end
end
