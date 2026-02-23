# frozen_string_literal: true

# Entry point for the jekyll-paginate-v3 gem.
#
# The plugin runtime is namespaced under Jekyll::Plugins::PaginateV3, with
# plugin-type modules grouped under nested modules (for example Generators).

require 'jekyll'
require 'jekyll-paginate-v3/version'
require 'jekyll-paginate-v3/config/defaults'
require 'jekyll-paginate-v3/config/normaliser'
require 'jekyll-paginate-v3/utils'
require 'jekyll-paginate-v3/query/parser'
require 'jekyll-paginate-v3/query/filter'
require 'jekyll-paginate-v3/query/sorter'
require 'jekyll-paginate-v3/pagination/paginator'
require 'jekyll-paginate-v3/pagination/pages/page'
require 'jekyll-paginate-v3/pagination/pages/document'
require 'jekyll-paginate-v3/indexes/templates/page_template'
require 'jekyll-paginate-v3/indexes/templates/document_template'
require 'jekyll-paginate-v3/indexes/builder'
require 'jekyll-paginate-v3/compatibility/v1'
require 'jekyll-paginate-v3/pagination/model'
require 'jekyll-paginate-v3/generators/pagination_generator'

module Jekyll
  module Plugins
    module PaginateV3
    end
  end
end
