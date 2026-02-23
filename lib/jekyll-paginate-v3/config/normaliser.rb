# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Config
        # Normalises site and page-level pagination configuration into one
        # predictable v3 shape.
        #
        # Used by the generator and pagination model so downstream logic can
        # assume one consistent config contract.
        class Normaliser
          LEGACY_FILTER_KEYS = %w[category tag locale].freeze
          V2_AUTOPAGE_DEFAULTS = {
            'tags' => {
              'layout' => 'autopage_tags.html',
              'title' => 'Posts tagged with :tag',
              'permalink' => '/tag/:tag',
              'slugify' => {
                'mode' => 'default',
                'cased' => false
              }
            },
            'categories' => {
              'layout' => 'autopage_category.html',
              'title' => 'Posts in category :cat',
              'permalink' => '/category/:cat',
              'slugify' => {
                'mode' => 'default',
                'cased' => false
              }
            },
            'collections' => {
              'layout' => 'autopage_collection.html',
              'title' => 'Posts in collection :coll',
              'permalink' => '/collection/:coll',
              'slugify' => {
                'mode' => 'default',
                'cased' => false
              }
            }
          }.freeze

          # Produces the canonical site-level pagination config.
          #
          # Order matters: defaults -> compatibility profile -> raw config ->
          # migrations/coercions.
          def self.normalise_site_config(site_config)
            site_hash = Utils.safe_hash(site_config)
            raw_pagination = Utils.safe_hash(site_hash['pagination'])

            compatibility_mode = normalise_compatibility(raw_pagination['compatibility'])

            config = Utils.deep_copy(DEFAULTS)
            if compatibility_mode && COMPATIBILITY_PROFILES.key?(compatibility_mode)
              config = Jekyll::Utils.deep_merge_hashes(config, Utils.deep_copy(COMPATIBILITY_PROFILES[compatibility_mode]))
            end

            if compatibility_mode == 'v1'
              config = Jekyll::Utils.deep_merge_hashes(config, legacy_v1_overlay(site_hash))
            end

            config = Jekyll::Utils.deep_merge_hashes(config, raw_pagination)
            config['compatibility'] = compatibility_mode unless compatibility_mode.nil?

            normalise_common!(config, compatibility_mode)
            migrate_legacy_shortcuts!(config, compatibility_mode, raw_pagination)
            migrate_v2_autopages!(config, site_hash['autopages'], compatibility_mode)

            config
          end

          # Produces template-level config by merging page overrides on top of
          # already-normalised site config.
          def self.normalise_template_config(site_config, template_pagination_config)
            page_config = Jekyll::Utils.deep_merge_hashes(
              Utils.deep_copy(site_config),
              Utils.safe_hash(template_pagination_config)
            )

            compatibility_mode = normalise_compatibility(page_config['compatibility']) || normalise_compatibility(site_config['compatibility'])
            page_config['compatibility'] = compatibility_mode unless compatibility_mode.nil?

            normalise_common!(page_config, compatibility_mode)
            migrate_legacy_shortcuts!(page_config, compatibility_mode, template_pagination_config)

            page_config
          end

          class << self
            private

            def normalise_common!(config, compatibility_mode)
              config['enabled'] = !!config['enabled']
              config['compatibility'] = compatibility_mode if compatibility_mode
              config['nested_key_separator'] = normalise_nested_separator(config['nested_key_separator'])
              config['keywords'] = normalise_keywords(config['keywords'])
              config['equivalents'] = normalise_equivalents(config['equivalents'])
              config['items'] = normalise_items_value(config['items'])
              config['filters'] = Utils.safe_hash(config['filters'])
              config['offset'] = [config['offset'].to_i, 0].max
              config['per_page'] = [config['per_page'].to_i, 1].max
              config['limit'] = [config['limit'].to_i, 0].max
              config['permalink'] = config['permalink'].to_s
              config['title'] = config['title'].to_s
              config['indexpage'] = config['indexpage'].to_s
              config['extension'] = config['extension'].to_s
              config['debug'] = !!config['debug']
              config['trail'] = normalise_trail(config['trail'])
              config['sort'] = normalise_sort(config['sort'], config['sort_field'], config['sort_reverse'])
              config['indexes'] = normalise_indexes(config['indexes'])

              # Keep legacy keys out of downstream logic after migration.
              config.delete('sort_field')
              config.delete('sort_reverse')
            end

            def normalise_compatibility(raw_value)
              value = raw_value.to_s.strip.downcase
              return nil if value.empty?
              return value if %w[v1 v2].include?(value)

              nil
            end

            def normalise_nested_separator(raw_separator)
              separator = raw_separator.to_s.strip
              return ':' if separator == ':'

              '.'
            end

            def normalise_keywords(raw_keywords)
              defaults = Utils.deep_copy(DEFAULTS['keywords'])
              keywords = defaults.merge(Utils.safe_hash(raw_keywords))

              keywords.each do |key, value|
                keywords[key] = value.to_s.strip
                keywords[key] = defaults[key] if keywords[key].empty?
              end

              keywords
            end

            def normalise_equivalents(raw_equivalents)
              return false if raw_equivalents == false

              array = Utils.arrayify(raw_equivalents)
              return Utils.deep_copy(DEFAULTS['equivalents']) if array.empty?

              array.map do |group|
                Utils.arrayify(group, split_commas: true).map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
              end.reject { |group| group.length < 2 }
            end

            def normalise_items_value(raw_items)
              return DEFAULTS['items'] if raw_items.nil?
              return raw_items if raw_items.is_a?(Hash) || raw_items.is_a?(Array)

              value = raw_items.to_s.strip
              value.empty? ? DEFAULTS['items'] : value
            end

            def normalise_trail(raw_trail)
              trail = Utils.safe_hash(raw_trail)
              {
                'before' => [trail['before'].to_i, 0].max,
                'after' => [trail['after'].to_i, 0].max
              }
            end

            def normalise_sort(raw_sort, raw_sort_field, raw_sort_reverse)
              sort_entries = Utils.arrayify(raw_sort, split_commas: true).map(&:to_s).map(&:strip).reject(&:empty?)
              return sort_entries unless sort_entries.empty?

              return Utils.deep_copy(DEFAULTS['sort']) if raw_sort_field.nil? || raw_sort_field.to_s.strip.empty?

              direction = raw_sort_reverse ? 'desc' : 'asc'
              ["#{raw_sort_field} #{direction}"]
            end

            def normalise_indexes(raw_indexes)
              defaults = Utils.deep_copy(DEFAULTS['indexes'])
              source = defaults.merge(Utils.safe_hash(raw_indexes))

              source['location'] = defaults['location'] if source['location'].nil? || source['location'].to_s.strip.empty?

              source['generate'] = if source['generate'].is_a?(Array)
                                     source['generate'].map { |entry| Utils.safe_hash(entry) }
                                   elsif source['generate'].is_a?(Hash)
                                     [Utils.safe_hash(source['generate'])]
                                   else
                                     []
                                   end

              source
            end

            # Migrates old v2 shorthand config into canonical v3 fields.
            # Modern keys retain precedence when both forms are supplied.
            def migrate_legacy_shortcuts!(config, compatibility_mode, raw_overrides = nil)
              return unless compatibility_mode == 'v2'

              override_hash = Utils.safe_hash(raw_overrides)
              explicit_indexes = Utils.safe_hash(override_hash['indexes'])
              explicit_filters = Utils.safe_hash(override_hash['filters'])

              if override_hash.key?('collection') && present_config_value?(override_hash['collection']) && !override_hash.key?('items')
                config['items'] = override_hash['collection']
              end

              LEGACY_FILTER_KEYS.each do |legacy_key|
                next unless override_hash.key?(legacy_key)
                next unless present_config_value?(override_hash[legacy_key])
                next if explicit_filters.key?(legacy_key)
                next if legacy_key == 'category' && override_hash[legacy_key].to_s.strip == 'posts'

                config['filters'][legacy_key] = override_hash[legacy_key]
              end

              config.delete('search')
              config.delete('collection')
              LEGACY_FILTER_KEYS.each { |legacy_key| config.delete(legacy_key) }
            end

            # Imports legacy top-level `paginate` settings used by
            # jekyll-paginate v1.
            def legacy_v1_overlay(site_hash)
              overlay = {}

              return overlay if site_hash['paginate'].nil?

              overlay['enabled'] = true
              overlay['per_page'] = site_hash['paginate'].to_i
              overlay['items'] = 'posts'
              overlay['keywords'] = { 'items' => 'posts' }
              overlay['permalink'] = site_hash['paginate_path'].to_s unless site_hash['paginate_path'].nil?

              overlay
            end

            # Legacy migration path for v2 `autopages` into v3 `pagination.indexes.generate`.
            def migrate_v2_autopages!(config, raw_autopages, compatibility_mode)
              return unless compatibility_mode == 'v2'

              autopages = Utils.safe_hash(raw_autopages)
              return if autopages.empty? || autopages['enabled'] == false

              migrated = []

              migrated.concat(migrate_v2_autopage_group(
                                raw_group: autopages['tags'],
                                index_key: 'tag',
                                items: 'all',
                                defaults: V2_AUTOPAGE_DEFAULTS['tags']
                              ))
              migrated.concat(migrate_v2_autopage_group(
                                raw_group: autopages['categories'],
                                index_key: 'category',
                                items: 'all',
                                defaults: V2_AUTOPAGE_DEFAULTS['categories']
                              ))
              migrated.concat(migrate_v2_autopage_group(
                                raw_group: autopages['collections'],
                                index_key: 'collection',
                                items: 'all',
                                defaults: V2_AUTOPAGE_DEFAULTS['collections']
                              ))

              return if migrated.empty?

              config['indexes']['generate'].concat(migrated)
            end

            # Maps one v2 autopages group (tags/categories/collections) to one
            # v3 generate definition.
            def migrate_v2_autopage_group(raw_group:, index_key:, items:, defaults:)
              group = Utils.safe_hash(raw_group)
              return [] if group.empty? || group['enabled'] == false

              layouts = Utils.normalise_layouts(group)
              layouts = [defaults['layout']] if layouts.empty?

              title = group['title']
              title = defaults['title'] unless present_config_value?(title)

              permalink = group['permalink']
              permalink = defaults['permalink'] unless present_config_value?(permalink)

              slugify = if group.key?('slugify')
                          Utils.safe_hash(group['slugify'])
                        else
                          Utils.deep_copy(defaults['slugify'])
                        end

              silent = boolean_config_value(group['silent'])

              [
                {
                  'items' => items,
                  'index' => index_key,
                  'layouts' => layouts,
                  'title' => title,
                  'permalink' => permalink,
                  'slugify' => slugify,
                  'silent' => silent
                }
              ]
            end

            # Indicates whether a config value should be treated as explicitly set.
            def present_config_value?(value)
              return false if value.nil?
              return false if value.is_a?(String) && value.strip.empty?
              return false if value.is_a?(Array) && value.empty?
              return false if value.is_a?(Hash) && value.empty?

              true
            end

            # Coerces loose truthy/falsey config values to a strict boolean.
            def boolean_config_value(value)
              return value if value == true || value == false

              value.to_s.strip.casecmp('true').zero?
            end
          end
        end
      end
    end
  end
end
