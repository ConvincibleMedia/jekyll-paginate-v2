# frozen_string_literal: true

require 'jekyll-paginate-v3/utils/core'
require 'jekyll-paginate-v3/utils/paths'
require 'jekyll-paginate-v3/utils/formatting'
require 'jekyll-paginate-v3/utils/nested_data'
require 'jekyll-paginate-v3/utils/items'

module Jekyll
  module Plugins
    module PaginateV3
      # Shared helper surface used across the plugin.
      #
      # The implementation is split across focused utility modules under
      # `lib/jekyll-paginate-v3/utils/`.
      module Utils
        extend Core
        extend Paths
        extend Formatting
        extend NestedData
        extend Items
      end
    end
  end
end