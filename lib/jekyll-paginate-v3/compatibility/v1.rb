# frozen_string_literal: true

require 'pathname'

module Jekyll
  module Plugins
    module PaginateV3
      module Compatibility
        module V1
          # Synthetic page used exclusively by v1 compatibility pagination.
          class PaginationPage < Jekyll::Page
            attr_accessor :pager

            def initialize(site, base, dir, template_path)
              @site = site
              @base = base
              @dir = dir
              @template = template_path
              @name = 'index.html'

              template_dir = File.dirname(template_path)
              template_file = File.basename(template_path)

              @path = if site.in_theme_dir(base) == base
                        site.in_theme_dir(base, template_dir, template_file)
                      else
                        site.in_source_dir(base, template_dir, template_file)
                      end

              process(@name)
              read_yaml(template_dir, template_file)

              data.default_proc = proc do |_, key|
                site.frontmatter_defaults.find(File.join(template_dir, template_file), type, key)
              end
            end
          end

          # Legacy compatibility helpers for jekyll-paginate v1 behaviour.
          #
          # This code is deliberately isolated so it can be removed in a future
          # major release without touching the v3 pipeline.
          # Used by Pagination::Model when `compatibility: v1` is enabled.
          class Utils
            # Finds the best `index.html` template candidate for v1 pagination.
            def self.template_page(site_pages, source_root, paginate_path)
              site_pages.select do |page|
                pagination_candidate?(source_root, paginate_path, page)
              end.sort_by { |page| -page.path.to_s.size }.first
            end

            # Mirrors legacy candidate detection: index page within paginate path
            # hierarchy.
            def self.pagination_candidate?(source_root, paginate_path, page)
              page_dir = File.dirname(File.expand_path(Jekyll::Plugins::PaginateV3::Utils.remove_leading_slash(page.path), source_root))
              full_paginate_path = File.expand_path(Jekyll::Plugins::PaginateV3::Utils.remove_leading_slash(paginate_path), source_root)
              page.name == 'index.html' && in_hierarchy(source_root, page_dir, File.dirname(full_paginate_path))
            end

            # Recursive helper used by pagination_candidate? to match parent
            # directory chains.
            def self.in_hierarchy(source_root, page_dir, paginate_path)
              return false if paginate_path == File.dirname(paginate_path)
              return false if paginate_path == Pathname.new(source_root).parent

              page_dir == paginate_path || in_hierarchy(source_root, page_dir, File.dirname(paginate_path))
            end

            # Generates v1-compatible pagers and synthetic pages.
            def self.paginate(config:, all_posts:, template_page:, page_add_lambda:, item_keyword:)
              pages = Jekyll::Plugins::PaginateV3::Utils.calculate_number_of_pages(all_posts, config['per_page'].to_i)
              pages = 1 if pages.zero?

              (1..pages).each do |page_number|
                pager = Pagination::Paginator.new(
                  per_page: config['per_page'],
                  first_page_url: template_page.url,
                  paginated_page_url: config['permalink'],
                  items: all_posts,
                  current_page: page_number,
                  total_pages: pages,
                  index_name: '',
                  extension: '',
                  item_keyword: item_keyword
                )

                if page_number == 1
                  if template_page.respond_to?(:pager=)
                    template_page.pager = pager
                  else
                    template_page.instance_variable_set('@pager', pager)
                  end
                  template_page.data['paginator'] = pager.to_liquid
                  next
                end

                template_full_path = File.join(template_page.site.source, template_page.path)
                template_dir = File.dirname(template_page.path)
                generated = PaginationPage.new(template_page.site, template_page.site.source, template_dir, template_full_path)
                generated.pager = pager
                generated.data['paginator'] = pager.to_liquid
                generated.dir = paginate_path(template_page.url, page_number, config['permalink'])
                page_add_lambda.call(generated)
              end
            end

            # Applies the classic v1 `paginate_path` format replacement.
            def self.paginate_path(template_url, page_number, permalink_format)
              return nil if page_number.nil?
              return template_url if page_number <= 1

              unless permalink_format.include?(':num')
                raise ArgumentError, "Invalid pagination path '#{permalink_format}'. It must include ':num'."
              end

              Jekyll::Plugins::PaginateV3::Utils.ensure_leading_slash(
                Jekyll::Plugins::PaginateV3::Utils.format_page_number(permalink_format, page_number)
              )
            end
          end
        end
      end
    end
  end
end
