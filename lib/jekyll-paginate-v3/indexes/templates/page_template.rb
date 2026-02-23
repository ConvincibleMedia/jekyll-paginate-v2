# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Indexes
        module Templates
          # Generated index template page built from a layout file and generated
          # frontmatter. The pagination model later expands this template.
          class PageTemplate < Jekyll::Page
            def initialize(site:, layout_name:, pagination_config:, frontmatter:, token_values:)
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
              self.data['paginate_v3'] = {
                'generated_index' => true,
                'tokens' => token_values
              }

              apply_permalink!

              data.default_proc = proc do |_, key|
                site.frontmatter_defaults.find(File.join(layout_dir, layout_name), type, key)
              end
            end

            private

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
