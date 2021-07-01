module Jekyll
  module PaginateV2::Generator

    #
    # This page handles the creation of the fake pagination pages based on the original page configuration
    # The code does the same things as the default Jekyll/page.rb code but just forces the code to look
    # into the template instead of the (currently non-existing) pagination page.
    #
    # This page exists purely in memory and is not read from disk
    #
    class PaginationPage < Page
      def initialize(page_to_copy, cur_page_nr, total_pages, index_pageandext)
        @site = page_to_copy.site
        @base = ''
        @url = ''
        @name = index_pageandext.nil? ? 'index.html' : index_pageandext

        self.process(@name) # Creates the basename and ext member values

        # Only need to copy the data part of the page as it already contains the layout information
        self.data = Jekyll::Utils.deep_merge_hashes( page_to_copy.data, {} )
        if !page_to_copy.data['autopage']
          self.content = page_to_copy.content
        else
          # If the page is an auto page then migrate the necessary autopage info across into the
          # new pagination page (so that users can get the correct keys etc)
          if( page_to_copy.data['autopage'].has_key?('display_name') )
            self.data['autopages'] = Jekyll::Utils.deep_merge_hashes( page_to_copy.data['autopage'], {} )
          end
        end

        # Store the current page and total page numbers in the pagination_info construct
        self.data['pagination_info'] = {"curr_page" => cur_page_nr, 'total_pages' => total_pages }       

        # Retain the extention so the page exists in site.html_pages
        self.ext = page_to_copy.extname
        
        # Map the first page back to the source file path, to play nice with other plugins
        self.data['path'] = page_to_copy.path if cur_page_nr == 1

        if page_to_copy.respond_to?(:collection)
          @collection = page_to_copy.collection
          self.data['collection'] = @collection.label
        end

        # Perform some validation that is also performed in Jekyll::Page
        validate_data! page_to_copy.path
        validate_permalink! page_to_copy.path

        # Trigger a page event
        #Jekyll::Hooks.trigger :pages, :post_init, self
      end

      def set_url(url_value)
        @url = url_value
      end
    end # class PaginationPage

    class PaginationDoc < Document

      def initialize(page_to_copy, cur_page_nr, total_pages, index_pageandext)
        @site = page_to_copy.site
        #@base = ''
        #@url = ''
        #@name = index_pageandext.nil? ? 'index.html' : index_pageandext

        @path = page_to_copy.path
        #@extname = File.extname(path)
        @collection = page_to_copy.collection
        @type = @collection.label.to_sym
        @has_yaml_header = nil

        if draft?
          categories_from_path("_drafts")
        else
          categories_from_path(collection.relative_directory)
        end

        data.default_proc = proc do |_, key|
          site.frontmatter_defaults.find(relative_path, type, key)
        end


        # Copy the data from the template page into this pagination page
        merge_data!(page_to_copy.data)

        if !page_to_copy.data['autopage']
          # ... and copy its content in too
          self.content = page_to_copy.content
        else
          # If the page is an auto page then migrate the necessary autopage info across into the
          # new pagination page (so that users can get the correct keys etc)
          if( page_to_copy.data['autopage'].has_key?('display_name') )
            self.data['autopages'] = Jekyll::Utils.deep_merge_hashes( page_to_copy.data['autopage'], {} )
          end
        end

        # Store the current page and total page numbers in the pagination_info construct
        self.data['pagination_info'] = {"curr_page" => cur_page_nr, 'total_pages' => total_pages }       

        # Retain the extention so the page exists in site.html_pages
        @extname = page_to_copy.extname
        
        # Map the first page back to the source file path, to play nice with other plugins
        # devnote: ensure other keys are also set on othe rpages
        self.data['path'] = page_to_copy.path if cur_page_nr == 1

        # Perform some validation that is also performed in Jekyll::Page
        #validate_data! page_to_copy.path
        #validate_permalink! page_to_copy.path

        #puts 'Initialized pagination page for: ' + self.data['path'].inspect

        # Trigger a page event
        trigger_hooks(:post_init)
        #Jekyll::Hooks.trigger :pages, :post_init, self
      end

      alias_method :ext, :extname

      attr_accessor :pager

      # Allows the reported URL for this pagination page to be set and overriden
      def set_url(url_value)
        @url = url_value
      end

    end


  end # module PaginateV2
end # module Jekyll
