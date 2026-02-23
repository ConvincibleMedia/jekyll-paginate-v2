# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Generators
        # Jekyll generator entry point for paginate-v3.
        #
        # Used by Jekyll's generator lifecycle to invoke the v3 pagination
        # pipeline for each site build.
        class PaginationGenerator < Jekyll::Generator
          safe true
          priority :lowest

          # Entrypoint called by Jekyll once the site graph is loaded.
          #
          # Normalises config, wires lightweight callbacks for mutating site
          # content, then delegates all pagination behaviour to Pagination::Model.
          def generate(site)
            config = Config::Normaliser.normalise_site_config(site.config)
            config = enable_implicit_v1_compatibility(config, site)

            unless config['enabled']
              Jekyll.logger.info('Pagination:', 'Disabled in site config.')
              return
            end

            # Shared logger callback so deeper layers do not depend directly on
            # Jekyll logger globals.
            log_lambda = lambda do |message, type = 'info'|
              case type
              when 'debug'
                Jekyll.logger.debug('Pagination:', message.to_s)
              when 'warn'
                Jekyll.logger.warn('Pagination:', message.to_s)
              when 'error'
                Jekyll.logger.error('Pagination:', message.to_s)
              else
                Jekyll.logger.info('Pagination:', message.to_s)
              end
            end

            # Abstract site mutation so the model can add pages or documents
            # without knowing where Jekyll stores each item type.
            add_item_lambda = lambda do |item|
              if item.respond_to?(:collection) && !item.collection.nil?
                site.collections[item.collection.label].docs << item
              else
                site.pages << item
              end
              item
            end

            # Mirror add_item_lambda for replacing template pages with generated
            # paginated siblings.
            remove_item_lambda = lambda do |item|
              if item.respond_to?(:collection) && !item.collection.nil?
                site.collections[item.collection.label].docs.delete_if { |doc| doc == item }
              else
                site.pages.delete_if { |page| page == item }
              end
            end

            model = Pagination::Model.new(
              site: site,
              site_config: config,
              log_lambda: log_lambda,
              add_item_lambda: add_item_lambda,
              remove_item_lambda: remove_item_lambda
            )

            processed_templates = model.run
            Jekyll.logger.info('Pagination:', "Complete, processed #{processed_templates} pagination template(s)")
          end

          private

          # Convenience bridge for old jekyll-paginate sites that still define
          # `paginate`/`paginate_path` without explicit v3 config.
          def enable_implicit_v1_compatibility(config, site)
            return config unless config['compatibility'].nil?
            return config unless site.config.key?('paginate')

            Jekyll.logger.warn('Pagination:', 'Detected legacy `paginate` config; enabling `compatibility: v1` automatically.')

            adjusted = Jekyll::Utils.deep_merge_hashes(site.config, {
              'pagination' => {
                'compatibility' => 'v1'
              }
            })

            Config::Normaliser.normalise_site_config(adjusted)
          end
        end
      end
    end
  end
end
