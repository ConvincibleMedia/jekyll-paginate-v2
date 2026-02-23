# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Indexes
        # Builds generated index templates from `pagination.indexes.generate`.
        #
        # Generated templates are ordinary pages/documents with
        # `pagination.enabled: true`, so the core pagination model can process
        # them exactly like hand-written index pages.
        #
        # Used by Pagination::Model before normal page pagination starts.
        class Builder
          SPECIAL_KEYS = %w[items index filter filters layout layouts location frontmatter permalink title slugify silent].freeze

          def initialize(site:, site_config:, add_item_lambda:, resolve_items_lambda:, log_lambda:)
            @site = site
            @site_config = site_config
            @add_item_lambda = add_item_lambda
            @resolve_items_lambda = resolve_items_lambda
            @log_lambda = log_lambda
            @nested_separator = site_config['nested_key_separator']
            @equivalents = site_config['equivalents']
            @compatibility_mode = site_config['compatibility']
          end

          # Builds all configured generated index templates.
          def build
            generate_definitions = @site_config.dig('indexes', 'generate')
            return 0 unless generate_definitions.is_a?(Array)

            default_location = default_generation_location
            generated_count = 0

            generate_definitions.each do |raw_definition|
              definition = normalise_definition(raw_definition, default_location)
              next if definition.nil?

              source_items = @resolve_items_lambda.call(definition['items'])
              source_items = Query::Filter.filter_items(
                source_items,
                definition['filters'],
                nested_separator: @nested_separator,
                equivalents: @equivalents
              )

              generated_count += build_for_definition(definition, source_items)
            end

            generated_count
          end

          private

          # Expands one generate definition into concrete template pages/documents.
          def build_for_definition(definition, source_items)
            entries = build_index_entries(source_items, definition['index'])
            return 0 if entries.empty?

            created = 0
            entries.each do |entry|
              definition['layouts'].each do |layout_name|
                page = build_template(definition, entry, layout_name)
                next if page.nil?

                @add_item_lambda.call(page)
                created += 1
              end
            end

            created
          end

          # Builds a single template object for one index value tuple and layout.
          def build_template(definition, entry, layout_name)
            token_map = build_token_map(definition['index'], entry['values'], slugify_config: definition['slugify'])
            generated_permalink = Utils.replace_tokens(definition['permalink'], token_map)
            generated_title = Utils.replace_tokens(definition['title'], token_map)
            generated_metadata = build_generated_metadata(definition['index'], entry['values'], token_map)

            generated_frontmatter = Utils.deep_copy(definition['frontmatter'])
            generated_frontmatter['title'] = generated_title unless generated_title.nil? || generated_title.empty?
            generated_frontmatter['permalink'] = generated_permalink unless generated_permalink.nil? || generated_permalink.empty?

            pagination_config = Utils.deep_copy(definition['pagination_overrides'])
            pagination_config['enabled'] = true
            pagination_config['items'] = definition['items']
            pagination_config['filters'] = Utils.deep_copy(definition['filters']).merge(entry['filters'])

            if definition['location'] == 'pages'
              Templates::PageTemplate.new(
                site: @site,
                layout_name: layout_name,
                pagination_config: pagination_config,
                frontmatter: generated_frontmatter,
                generated_metadata: generated_metadata
              )
            else
              collection = @site.collections[definition['location']]
              if collection.nil?
                @log_lambda.call("Skipping generated index in unknown collection '#{definition['location']}'.", 'warn') unless definition['silent']
                return nil
              end

              Templates::DocumentTemplate.new(
                site: @site,
                collection: collection,
                layout_name: layout_name,
                pagination_config: pagination_config,
                frontmatter: generated_frontmatter,
                generated_metadata: generated_metadata
              )
            end
          rescue StandardError => error
            @log_lambda.call("Unable to generate index template from layout '#{layout_name}': #{error.message}", 'warn') unless definition['silent']
            nil
          end

          # Recursively groups items by index keys to produce one entry per
          # unique key/value combination.
          def build_index_entries(items, index_keys)
            entries = []
            recurse_build_entries(items, index_keys, 0, {}, {}, entries)
            entries
          end

          # Depth-first grouping for multi-level indexes such as
          # `index: category, subcategory`.
          def recurse_build_entries(items, index_keys, depth, active_filters, active_values, entries)
            if depth >= index_keys.length
              entries << {
                'filters' => active_filters,
                'values' => active_values
              }
              return
            end

            key = index_keys[depth]
            grouped_items = group_items_by_key(items, key)

            grouped_items.each do |value, grouped|
              next if value.nil?

              next_filters = active_filters.merge(key => value)
              next_values = active_values.merge(key => value)
              recurse_build_entries(grouped, index_keys, depth + 1, next_filters, next_values, entries)
            end
          end

          # Groups items by one frontmatter key (supports nested/equivalent keys).
          def group_items_by_key(items, key)
            equivalent_lookup = Utils.build_equivalent_lookup(@equivalents)
            grouped = Hash.new { |hash, value_key| hash[value_key] = [] }

            items.each do |item|
              values = values_for_key(item, key, equivalent_lookup)
              values.each { |value| grouped[value] << item }
            end

            grouped
          end

          # Extracts unique scalar values for a key, including comma/semicolon
          # string lists.
          def values_for_key(item, key, equivalent_lookup)
            data = item.respond_to?(:data) && item.data.is_a?(Hash) ? item.data.dup : {}
            collection_label = Utils.item_collection_label(item)
            data['collection'] = collection_label unless collection_label.nil?

            values = Utils.fetch_nested_values(data, key, @nested_separator, equivalent_lookup)
            values = values.flat_map do |value|
              if value.is_a?(String)
                value.split(/,|;/).map(&:strip)
              else
                Utils.scalar_values(value)
              end
            end

            values.map { |value| value.to_s.strip }.reject(&:empty?).uniq
          end

          # Normalises one raw `indexes.generate` definition into a predictable
          # internal shape.
          def normalise_definition(raw_definition, default_location)
            definition = Utils.safe_hash(raw_definition)
            return nil if definition.empty?
            silent = normalise_boolean(definition['silent'])

            index_keys = Utils.comma_delimited_array(definition['index'])
            if index_keys.empty?
              @log_lambda.call('Skipping generated index config with missing `index` key.', 'warn') unless silent
              return nil
            end

            layouts = Utils.normalise_layouts(definition)
            if layouts.empty?
              @log_lambda.call('Skipping generated index config with no `layout`/`layouts` value.', 'warn') unless silent
              return nil
            end

            filters = Utils.safe_hash(definition['filters'])
            if definition.key?('filter')
              index_keys.each { |key| filters[key] = definition['filter'] unless filters.key?(key) }
            end

            {
              'items' => definition['items'].nil? ? @site_config['items'] : definition['items'],
              'index' => index_keys,
              'filters' => filters,
              'layouts' => layouts,
              'location' => normalise_location(definition['location'], default_location),
              'frontmatter' => Utils.safe_hash(definition['frontmatter']),
              'permalink' => definition['permalink'].to_s,
              'title' => definition['title'].to_s,
              'slugify' => normalise_slugify_config(definition['slugify']),
              'silent' => silent,
              'pagination_overrides' => extract_pagination_overrides(definition)
            }
          end

          # Splits non-special keys from a generate definition so they can be
          # merged into the generated template's pagination config.
          def extract_pagination_overrides(definition)
            overrides = Utils.safe_hash(definition).reject { |key, _| SPECIAL_KEYS.include?(key) }

            # `permalink` and `title` on generate definitions are page-level values
            # for generated templates, not paginator suffix patterns.
            overrides
          end

          def normalise_location(raw_location, default_location)
            location = raw_location.to_s.strip
            return default_location if location.empty?

            return 'pages' if location == 'pages'
            return default_location if location == 'all' || location == 'everything'

            location
          end

          # Uses `indexes.location` to infer whether generated templates should
          # default to `pages` or a collection.
          def default_generation_location
            first_type = Query::Parser.first_type(@site_config.dig('indexes', 'location'), @site_config['keywords'])
            return 'pages' if first_type.nil?
            return 'pages' if %w[pages all everything].include?(first_type)

            first_type
          end

          # Builds placeholder values used by generated `permalink` and `title`
          # strings.
          def build_token_map(index_keys, values, slugify_config:)
            token_map = {}

            index_keys.each do |key|
              value = values[key]
              token_map[key] = slugify_value(value, slugify_config)
            end

            apply_legacy_token_aliases!(token_map, index_keys)
            token_map
          end

          # Applies v2 legacy token aliases (`:coll`, `:cat`, `:tag`) for
          # generated title/permalink placeholders.
          def apply_legacy_token_aliases!(token_map, index_keys)
            if @compatibility_mode == 'v2'
              if index_keys.include?('collection')
                token_map['coll'] = token_map['collection']
              end

              if index_keys.include?('category') || index_keys.include?('categories')
                token_map['cat'] = token_map['category'] || token_map['categories']
              end

              if index_keys.include?('tag') || index_keys.include?('tags')
                token_map['tag'] = token_map['tag'] || token_map['tags']
              end
            end
          end

          # Normalises slugify config accepted on `indexes.generate[]`.
          # Supports both `slugify.case` and `slugify.cased`.
          def normalise_slugify_config(raw_slugify)
            slugify = Utils.safe_hash(raw_slugify)
            mode = slugify['mode'].to_s.strip
            mode = 'default' if mode.empty?

            cased = if slugify.key?('cased')
                      normalise_boolean(slugify['cased'])
                    else
                      normalise_boolean(slugify['case'])
                    end

            {
              'mode' => mode,
              'cased' => cased
            }
          end

          # Slugifies one token value according to an index definition.
          def slugify_value(value, slugify_config)
            mode = slugify_config['mode']
            cased = slugify_config['cased']
            Jekyll::Utils.slugify(value.to_s, mode: mode, cased: cased)
          end

          # Coerces loose truthy/falsey config values to a strict boolean.
          def normalise_boolean(value)
            return value if value == true || value == false

            value.to_s.strip.casecmp('true').zero?
          end

          # Captures generated-index metadata for compatibility and template use.
          def build_generated_metadata(index_keys, raw_values, token_map)
            metadata = {
              'generated_index' => true,
              'index_keys' => index_keys,
              'tokens' => Utils.deep_copy(raw_values)
            }

            if index_keys.length == 1
              key = index_keys.first
              metadata['autopages'] = {
                'key' => key,
                'value' => token_map[key],
                'display_name' => raw_values[key].to_s
              }
            end

            metadata
          end
        end
      end
    end
  end
end
