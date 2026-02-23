# frozen_string_literal: true

require 'date'

module Jekyll
  module Plugins
    module PaginateV3
      module Query
        # Filtering engine for pagination and generated index discovery.
        #
        # Filters are specified as a hash where each key is a frontmatter key and
        # each value can be:
        # - scalar (String/Integer/Float/Date/Regexp)
        # - comma-delimited String list
        # - Array of values
        # - Hash range: `{ min: ..., max: ... }`
        # - Hash list group: `{ list: [...], join: and|or }`
        class Filter
          def self.filter_items(items, filters, nested_separator:, equivalents:)
            engine = new(nested_separator: nested_separator, equivalents: equivalents)
            engine.filter_items(items, filters)
          end

          def self.filter_to_s(filter)
            normalised = normalise_filter(filter)
            return '[invalid filter]' if normalised == false

            filter_to_s_internal(normalised)
          end

          def initialize(nested_separator:, equivalents:)
            @nested_separator = nested_separator
            @equivalent_lookup = Utils.build_equivalent_lookup(equivalents)
          end

          def filter_items(items, filters)
            return items unless filters.is_a?(Hash)

            current_items = items
            Utils.safe_hash(filters).each do |raw_key, raw_filter|
              normalised = self.class.normalise_filter(raw_filter)
              next if normalised == false

              key = raw_key.to_s
              current_items = current_items.select do |item|
                values = extract_item_values(item, key)
                next false if values.empty?

                check_filter(normalised, values)
              end
            end

            current_items
          end

          class << self
            def normalise_filter(filter, wrapped = false)
              if filter.is_a?(Hash)
                hash_filter = Utils.stringify_keys(filter)
                if hash_filter.key?('list')
                  list = normalise_filter(hash_filter['list'], true)
                  return false if list == false

                  join_mode = hash_filter['join'].to_s.strip.downcase
                  join_mode = 'or' unless %w[or and].include?(join_mode)

                  group = { 'list' => list, 'join' => join_mode }
                  return wrapped ? [group] : group
                end
              end

              conformed = conform_filter_to_array(filter)
              return false unless conformed.is_a?(Array)

              conformed = conformed.flatten.map { |entry| normalise_filter_entry(entry) }.reject { |entry| entry == false }
              return false if conformed.empty?

              wrapped ? conformed : { 'list' => conformed, 'join' => 'or' }
            end

            private

            def conform_filter_to_array(filter)
              if filter.is_a?(Array)
                filter
              elsif filter.is_a?(String)
                filter.split(/,|;/).map(&:strip)
              elsif filter.is_a?(Hash) || filter.is_a?(Regexp) || filter.is_a?(Integer) || filter.is_a?(Float) || filter.is_a?(Date)
                [filter]
              else
                nil
              end
            end

            def normalise_filter_entry(entry)
              if entry.is_a?(String)
                parse_scalar(entry.strip)
              elsif entry.is_a?(Hash)
                normalise_filter_hash(entry)
              elsif entry.is_a?(Regexp) || entry.is_a?(Integer) || entry.is_a?(Float) || entry.is_a?(Date)
                entry
              else
                false
              end
            end

            def normalise_filter_hash(entry)
              hash_entry = Utils.stringify_keys(entry)

              if hash_entry.key?('list')
                nested = normalise_filter(hash_entry)
                return false if nested == false

                return nested
              end

              range_hash = hash_entry.select { |key, _| %w[min max].include?(key) }
              return false if range_hash.empty?

              %w[min max].each do |range_key|
                next unless range_hash.key?(range_key)

                parsed = interpret_numeric_or_date_keyword(range_hash[range_key])
                return false if parsed == false

                range_hash[range_key] = parsed
              end

              return false if range_hash['min'].nil? && range_hash['max'].nil?

              if !range_hash['min'].nil? && !range_hash['max'].nil?
                min_value = range_hash['min']
                max_value = range_hash['max']

                if numeric?(min_value) && numeric?(max_value)
                  range_hash['min'] = min_value.to_f
                  range_hash['max'] = max_value.to_f
                elsif min_value.class != max_value.class
                  return false
                end

                if range_hash['min'] > range_hash['max']
                  range_hash['min'], range_hash['max'] = range_hash['max'], range_hash['min']
                end
              end

              range_hash
            end

            def parse_scalar(value)
              if value =~ %r{\A/(.*?)/([imx]*)\z}
                source = Regexp.last_match(1)
                flags = Regexp.last_match(2)
                options = 0
                options |= Regexp::IGNORECASE if flags.include?('i')
                options |= Regexp::MULTILINE if flags.include?('m')
                options |= Regexp::EXTENDED if flags.include?('x')
                return Regexp.new(source, options)
              end

              interpret_numeric(value)
            end

            def interpret_numeric_or_date_keyword(value)
              normalised = value.to_s.strip.downcase
              return Date.today if %w[now today].include?(normalised)

              interpret_numeric(value, must_cast: true)
            end

            def interpret_numeric(value, must_cast: false)
              return value if value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(Date)

              unless value.is_a?(String)
                return false if must_cast

                return value
              end

              stripped = value.strip
              return stripped.to_i if stripped.match?(/\A[+-]?\d+\z/)
              return stripped.to_f if stripped.match?(/\A[+-]?\d+\.\d+\z/)

              begin
                return Date.parse(stripped)
              rescue ArgumentError
                return false if must_cast

                return stripped
              end
            end

            def numeric?(value)
              value.is_a?(Integer) || value.is_a?(Float)
            end

            def filter_to_s_internal(filter)
              fragments = filter['list'].map do |entry|
                if entry.is_a?(Hash)
                  if entry.key?('list')
                    "(#{filter_to_s_internal(entry)})"
                  elsif entry.key?('min') || entry.key?('max')
                    if entry.key?('min') && entry.key?('max')
                      "#{entry['min']} to #{entry['max']}"
                    elsif entry.key?('min')
                      "#{entry['min']} or more"
                    else
                      "#{entry['max']} or less"
                    end
                  else
                    '[invalid]'
                  end
                else
                  entry.to_s
                end
              end

              fragments.join(" #{filter['join'] || 'or'} ")
            end
          end

          private

          def extract_item_values(item, key)
            data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data : {}
            decorated_data = data.dup

            collection_label = Utils.item_collection_label(item)
            decorated_data['collection'] = collection_label unless collection_label.nil?

            values = Utils.fetch_nested_values(decorated_data, key, @nested_separator, @equivalent_lookup)
            values = values.flat_map { |value| value.is_a?(String) ? value.split(/,|;/).map(&:strip) : Utils.scalar_values(value) }
            values.reject { |value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
          end

          def check_filter(filter, item_values)
            evaluations = filter['list'].map do |part|
              check_filter_part(part, item_values)
            end

            (filter['join'] || 'or') == 'and' ? evaluations.all? : evaluations.any?
          end

          def check_filter_part(part, item_values)
            if part.is_a?(Hash)
              if part.key?('list')
                check_filter(part, item_values)
              elsif part.key?('min') || part.key?('max')
                item_values.any? { |value| range_match?(value, part['min'], part['max']) }
              else
                false
              end
            elsif part.is_a?(Regexp)
              item_values.any? { |value| part.match?(value.to_s) }
            else
              interpreted_values = item_values.map { |value| value.is_a?(String) ? self.class.send(:interpret_numeric, value) : value }
              interpreted_values.include?(part)
            end
          end

          def range_match?(value, min_value, max_value)
            comparable_value = value.is_a?(String) ? self.class.send(:interpret_numeric, value) : value
            return false if comparable_value.nil?

            if !min_value.nil?
              return false unless values_comparable?(comparable_value, min_value)
              return false if comparable_value < min_value
            end

            if !max_value.nil?
              return false unless values_comparable?(comparable_value, max_value)
              return false if comparable_value > max_value
            end

            true
          rescue ArgumentError, NoMethodError
            false
          end

          def values_comparable?(left, right)
            return true if left.class == right.class
            return true if (left.is_a?(Integer) || left.is_a?(Float)) && (right.is_a?(Integer) || right.is_a?(Float))

            !((left <=> right).nil?)
          rescue ArgumentError, NoMethodError
            false
          end
        end
      end
    end
  end
end
