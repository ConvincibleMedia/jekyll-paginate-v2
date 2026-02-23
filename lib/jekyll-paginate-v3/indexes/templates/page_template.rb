# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Indexes
        module Templates
          # Generated index template page built from a layout file and generated
          # frontmatter. The pagination model later expands this template.
          #
          # Used by Indexes::Builder for generated page-based index templates.
          class PageTemplate < Jekyll::Page
            # Creates an in-memory page that behaves like a hand-authored index.
            def initialize(site:, layout_name:, pagination_config:, frontmatter:, generated_metadata:)
              @site = site
              @base = site.source
              @name = 'index.html'

              layout_dir = '_layouts'
              @path = if site.in_theme_dir(site.source) == site.source
                        site.in_theme_dir(site.source, layout_dir, layout_name)
                      else
                        site.in_source_dir(site.source, layout_dir, layout_name)
                      end

              process(@name)
              read_yaml(File.join(site.source, layout_dir), layout_name)

              layout_data = Jekyll::Utils.deep_merge_hashes(self.data, {})
              self.data = Jekyll::Utils.deep_merge_hashes(frontmatter, layout_data)
              self.data['layout'] = File.basename(layout_name, File.extname(layout_name))
              self.data['pagination'] = Jekyll::Utils.deep_merge_hashes(pagination_config, Utils.safe_hash(layout_data['pagination']))
              self.data['paginate_v3'] = Utils.safe_hash(generated_metadata)
              self.data['autogen'] = 'jekyll-paginate-v3'

              apply_compatibility_metadata!

              apply_permalink!

              data.default_proc = proc do |_, key|
                site.frontmatter_defaults.find(File.join(layout_dir, layout_name), type, key)
              end
            end

            private

            # Adds legacy-friendly fields for generated index pages so existing
            # templates can access `page.autopages.display_name` and key values.
            def apply_compatibility_metadata!
              autopage_data = Utils.safe_hash(data.dig('paginate_v3', 'autopages'))
              return if autopage_data.empty?

              data['autopages'] = autopage_data
              key = autopage_data['key'].to_s
              return if key.empty?
              return if key == 'collection'
              return if key.include?('.') || key.include?(':')

              data[key] = autopage_data['value']
            end

            # Applies frontmatter permalink directly so the synthetic template
            # lands at the intended route before pagination expansion.
            def apply_permalink!
              return unless data['permalink']

              permalink = data['permalink'].to_s
              @dir = permalink
              @url = Utils.ensure_full_path(permalink, 'index', '.html')
            end
          end
        end
      end
    end
  end
end
