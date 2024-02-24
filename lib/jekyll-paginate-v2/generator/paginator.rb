require 'awesome_print'

module Jekyll
  module PaginateV2::Generator
    
    #
    # Handles the preparation of all the posts based on the current page index
    #
    class Paginator
      attr_reader :page, :per_page, :posts, :total_posts, :total_pages,
        :previous_page, :previous_page_path, :next_page, :next_page_path, :page_path, :page_trail,
        :first_page, :first_page_path, :last_page, :last_page_path

      def page_trail
        @page_trail
      end

      def page_trail=(page_array)
        @page_trail = page_array
      end
      
      #
      # Initialise a new paginator
      #
      # @param config_per_page The per_page config value set for paginator
      # @param first_index_page_url Location of the first index page
      # @param paginated_page_url Permalink style - combination of first index page + style defined in config
      # @param posts The whole, filtered set of items that are to be paginated
      # @param cur_page_nr The number of the page among the set of pages on which this paginator is operating
      # @param num_pages The total number of pages that this paginator is spread across
      # @param default_indexpage The name of the indexpage as defined in config. Can be ''.
      # @param default_ext The extension to use as defined in config. Can be ''.
      #
      def initialize(config_per_page, first_index_page_url, paginated_page_url, posts, cur_page_nr, num_pages, default_indexpage, default_ext)
        #puts 'Initializing paginator for page: ' + cur_page_nr.to_s
        @page = cur_page_nr
        @per_page = config_per_page.to_i
        @total_pages = num_pages

        #ap [['config_per_page', 'first_index_page_url', 'paginated_page_url', 'posts', 'cur_page_nr', 'num_pages', 'default_indexpage', 'default_ext'],[config_per_page, first_index_page_url, paginated_page_url, posts, cur_page_nr, num_pages, default_indexpage, default_ext]].transpose.to_h

        if @page > @total_pages
          raise RuntimeError, "page number can't be greater than total pages: #{@page} > #{@total_pages}"
        end

        init = (@page - 1) * @per_page
        offset = (init + @per_page - 1) >= posts.size ? posts.size : (init + @per_page - 1)

        # Ensure that the current page has correct extensions if needed
        # This function forces indexpage = 'index' if it is empty
        # This function forces ext = '.html' if it is empty
        this_page_url = Utils.ensure_full_path(@page == 1 ? first_index_page_url : paginated_page_url,
                                               !default_indexpage || default_indexpage.length == 0 ? 'index' : default_indexpage,
                                               !default_ext || default_ext.length == 0 ? '.html' : default_ext)
        
        puts 'Paginator determines this_page_url = ' + this_page_url.inspect
        # To support customizable pagination pages we attempt to explicitly append the page name to 
        # the url incase the user is using extensionless permalinks. 
        if default_indexpage && default_indexpage.length > 0
          #puts 'Adjusting page URLs as default indexpage is defined'
          # Adjust first page url
          first_index_page_url = Utils.ensure_full_path(first_index_page_url, default_indexpage, default_ext)
          # Adjust the paginated pages as well
          paginated_page_url = Utils.ensure_full_path(paginated_page_url, default_indexpage, default_ext)
        end

        @total_posts = posts.size
        @posts = posts[init..offset]
        @page_path = Utils.format_page_number(this_page_url, cur_page_nr, @total_pages)

#        puts 'After swapping placeholders, @page_path is: ' + @page_path

        @previous_page = @page != 1 ? @page - 1 : nil
        @previous_page_path = @page == 1 ? nil : 
                              @page == 2 ? Utils.format_page_number(first_index_page_url, 1, @total_pages) : 
                              Utils.format_page_number(paginated_page_url, @previous_page, @total_pages)
        @next_page = @page != @total_pages ? @page + 1 : nil
        @next_page_path = @page != @total_pages ? Utils.format_page_number(paginated_page_url, @next_page, @total_pages) : nil

        @first_page = 1
        @first_page_path = Utils.format_page_number(first_index_page_url, 1, @total_pages)
        @last_page = @total_pages
        @last_page_path = Utils.format_page_number(paginated_page_url, @total_pages, @total_pages)

        puts '@previous_page_path is: ' + @previous_page_path.inspect
      end

      # Convert this Paginator's data to a Hash suitable for use by Liquid.
      #
      # Returns the Hash representation of this Paginator.
      def to_liquid
        {
          'per_page' => per_page,
          'posts' => posts,
          'total_posts' => total_posts,
          'total_pages' => total_pages,
          'page' => page,
          'page_path' => page_path,
          'previous_page' => previous_page,
          'previous_page_path' => previous_page_path,
          'next_page' => next_page,
          'next_page_path' => next_page_path,
          'first_page' => first_page,
          'first_page_path' => first_page_path,
          'last_page' => last_page,
          'last_page_path' => last_page_path,
          'page_trail' => page_trail
        }
      end
      
    end # class Paginator

    # Small utility class that handles individual pagination trails 
    # and makes them easier to work with in Liquid
    class PageTrail
      attr_reader :num, :path, :title

      def initialize( num, path, title )
        @num = num
        @path = path
        @title = title
      end #func initialize

      def to_liquid
        {
          'num' => num,
          'path' => path,
          'title' => title
        }
      end
    end #class PageTrail

  end # module PaginateV2
end # module Jekyll