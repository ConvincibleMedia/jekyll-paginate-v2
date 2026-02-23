require "jekyll-paginate/version"
require "jekyll-paginate/pager"
require "jekyll-paginate/pagination"

module Jekyll
  module Paginate
    # Namespace anchor for the legacy jekyll-paginate v1 implementation.
    #
    # Used by legacy plugin loading to expose classic pager/generator classes.
  end
end
