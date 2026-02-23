# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Pagination
        # Core pagination orchestration model.
        #
        # Responsibilities:
        # - discover index templates
        # - generate configured indexes (`pagination.indexes.generate`)
        # - resolve and filter/sort items per template
        # - emit paginated synthetic pages/documents
        #
        # Used by Generators::PaginationGenerator as the main runtime
        # coordinator for the pagination pipeline.
        class Model
          def initialize(site:, site_config:, log_lambda:, add_item_lambda:, remove_item_lambda:)
            @site = site
            @site_config = site_config
            @log_lambda = log_lambda
            @add_item_lambda = add_item_lambda
            @remove_item_lambda = remove_item_lambda
            @nested_separator = site_config['nested_key_separator']
            @equivalents = site_config['equivalents']
            @item_keyword = site_config.dig('keywords', 'items') || 'items'
          end

          # Runs the full pagination pipeline for the current site build.
          def run
            if @site_config['compatibility'] == 'v1'
              return run_v1_compatibility
            end

            generated_index_count = build_generated_indexes
            @log_lambda.call("Generated #{generated_index_count} index template(s).", 'debug') if @site_config['debug']

            templates = discover_index_templates
            if templates.empty?
              @log_lambda.call('Enabled, but no pagination index pages were discovered.', 'warn')
              return 0
            end

            processed = 0
            templates.each do |template|
              next unless template.data['pagination'].is_a?(Hash)

              template_config = Config::Normaliser.normalise_template_config(@site_config, template.data['pagination'])
              next unless template_config['enabled']

              paginate_template(template, template_config)
              processed += 1
            end

            processed
          end

          private

          # Delegates to isolated v1 compatibility helpers when explicitly
          # configured, preserving legacy semantics.
          def run_v1_compatibility
            all_posts = if @site.site_payload.dig('site', 'posts').is_a?(Array)
                          @site.site_payload['site']['posts']
                        elsif @site.collections['posts']
                          @site.collections['posts'].docs
                        else
                          []
                        end

            all_posts = all_posts.reject { |post| post['hidden'] }

            template = Compatibility::V1::Utils.template_page(@site.pages, @site.config['source'], @site_config['permalink'])
            if template.nil?
              @log_lambda.call('v1 compatibility is enabled, but no template index.html page was found.', 'warn')
              return 0
            end

            Compatibility::V1::Utils.paginate(
              config: @site_config,
              all_posts: all_posts,
              template_page: template,
              page_add_lambda: @add_item_lambda,
              item_keyword: @item_keyword
            )

            1
          end

          # Builds synthetic index templates from `indexes.generate`.
          def build_generated_indexes
            builder = Indexes::Builder.new(
              site: @site,
              site_config: @site_config,
              add_item_lambda: @add_item_lambda,
              resolve_items_lambda: method(:resolve_items),
              log_lambda: @log_lambda
            )
            builder.build
          end

          # Discovers all templates that request pagination, including generated
          # templates when configured.
          def discover_index_templates
            templates = resolve_items(
              @site_config.dig('indexes', 'location'),
              include_index_templates: true,
              include_generated_pages: true,
              include_hidden: true
            )

            templates.select do |item|
              next false unless item.respond_to?(:data)
              next false unless item.data.is_a?(Hash)

              pagination = item.data['pagination']
              pagination.is_a?(Hash) && pagination['enabled']
            end
          end

          # Resolves the shared search format into concrete site items and then
          # applies generic inclusion/exclusion flags.
          def resolve_items(raw_search, include_index_templates: false, include_generated_pages: false, include_hidden: false)
            entries = Query::Parser.parse(raw_search, @site_config['keywords'])
            return [] if entries.empty?

            resolved = []
            entries.each do |entry|
              resolved.concat(resolve_entry(entry))
            end

            resolved.uniq!
            resolved.sort_by! { |item| Utils.relative_item_path(item) }

            resolved.select! { |item| !Utils.generated_index?(item) } unless include_generated_pages
            resolved.select! { |item| !Utils.index_template?(item) } unless include_index_templates
            resolved.select! { |item| !item['hidden'] } unless include_hidden

            resolved
          end

          # Resolves one parsed search entry (`pages`, collection label, etc).
          def resolve_entry(entry)
            type = entry['type']
            paths = entry['paths']

            source_items = case type
                           when 'pages'
                             @site.pages
                           when 'all'
                             all_collection_documents
                           when 'everything'
                             @site.pages + all_collection_documents
                           else
                             @site.collections[type]&.docs || []
                           end

            source_items.select do |item|
              Query::Parser.path_allowed?(Utils.relative_item_path(item), paths)
            end
          end

          def all_collection_documents
            @site.collections.values.flat_map(&:docs)
          end

          # Applies item resolution, filtering, sorting, offset and limit before
          # generating concrete pages.
          def paginate_template(template, config)
            all_items = resolve_items(config['items'])
            filtered_items = Query::Filter.filter_items(
              all_items,
              config['filters'],
              nested_separator: @nested_separator,
              equivalents: @equivalents
            )

            sorted_items = Query::Sorter.apply(
              filtered_items,
              config['sort'],
              nested_separator: @nested_separator,
              equivalents: @equivalents
            )

            offset = [config['offset'].to_i, 0].max
            sorted_items = sorted_items.drop(offset)

            total_pages = Utils.calculate_number_of_pages(sorted_items, config['per_page'])
            total_pages = 1 if total_pages.zero?

            if config['limit'].to_i > 0
              total_pages = [total_pages, config['limit'].to_i].min
            end

            emit_paginated_pages(template, config, sorted_items, total_pages)
          end

          # Replaces a template with one synthetic page/document per page number.
          def emit_paginated_pages(template, config, items, total_pages)
            @remove_item_lambda.call(template)

            new_pages = []
            index_name = config['indexpage'].to_s
            extension = Utils.ensure_leading_dot(config['extension'])
            index_file = "#{index_name}#{extension}"

            first_page_url = template_first_page_url(template)
            paginated_page_url = join_url(first_page_url, config['permalink'])

            (1..total_pages).each do |current_page|
              generated = if template.respond_to?(:collection)
                            Pages::Document.new(template, current_page, total_pages, index_file)
                          else
                            Pages::Page.new(template, current_page, total_pages, index_file)
                          end

              generated.pager = Paginator.new(
                per_page: config['per_page'],
                first_page_url: first_page_url,
                paginated_page_url: paginated_page_url,
                items: items,
                current_page: current_page,
                total_pages: total_pages,
                index_name: index_name,
                extension: extension,
                item_keyword: @item_keyword
              )

              generated.set_url(synthetic_page_url(generated.pager.page_path, index_name, extension))
              generated.data['paginator'] = generated.pager.to_liquid

              if template.data['permalink']
                generated.data['permalink'] = generated.pager.page_path
              end

              base_title = template.data['title'] || @site.config['title']
              if current_page > 1
                generated.data['title'] = Utils.format_page_title(config['title'], base_title, current_page, total_pages)
                generated.data['autogen'] = 'jekyll-paginate-v3'
              else
                generated.data['title'] = base_title
              end

              @add_item_lambda.call(generated)
              new_pages << generated
            end

            apply_page_trail(new_pages, config)
          end

          # Attaches a compact neighbourhood of page links around each generated
          # page when `trail.before/after` is configured.
          def apply_page_trail(generated_pages, config)
            return if generated_pages.length <= 1
            return unless config['trail'].is_a?(Hash)

            before = [config['trail']['before'].to_i, 0].max
            after = [config['trail']['after'].to_i, 0].max
            return if before.zero? && after.zero?

            trail_size = before + after + 1

            generated_pages.each do |page|
              range_start = [page.pager.page - before - 1, 0].max
              range_end = [range_start + trail_size, generated_pages.length].min

              if range_end - range_start < trail_size
                range_start = [range_start - (trail_size - (range_end - range_start)), 0].max
              end

              page.pager.page_trail = generated_pages[range_start...range_end].each_with_index.map do |trail_page, index|
                PageTrail.new(range_start + index + 1, trail_page.url, trail_page.data['title'])
              end
            end
          end

          # Determines the canonical URL for the first pagination page of a template.
          def template_first_page_url(template)
            permalink = template.data['permalink']
            unless permalink.nil? || permalink.to_s.strip.empty?
              return Utils.ensure_leading_slash(permalink.to_s)
            end

            if template.respond_to?(:url) && !template.url.to_s.strip.empty?
              return Utils.ensure_leading_slash(template.url.to_s)
            end

            if template.respond_to?(:cleaned_relative_path)
              return "/#{template.cleaned_relative_path}/"
            end

            "/#{Utils.remove_leading_slash(File.join(template.dir.to_s, template.basename.to_s))}/"
          end

          # Joins a base URL and relative suffix while preserving one leading slash.
          def join_url(base_url, suffix)
            joined = "#{Utils.ensure_trailing_slash(base_url)}#{Utils.remove_leading_slash(suffix.to_s)}"
            Utils.ensure_leading_slash(joined)
          end

          # Converts full output file paths into clean route-style URLs used by
          # Jekyll pages/documents.
          def synthetic_page_url(page_path, index_name, extension)
            full_index_name = "#{index_name}#{extension}"
            if !index_name.to_s.empty? && page_path.end_with?(full_index_name)
              trimmed = page_path[0...-full_index_name.length]
              return Utils.ensure_trailing_slash(trimmed)
            end

            if !extension.to_s.empty? && page_path.end_with?(extension)
              return page_path[0...-extension.length]
            end

            page_path
          end
        end
      end
    end
  end
end
