module Jekyll
  module PaginateV2::Generator
  
    #
    # The main entry point into the generator, called by Jekyll
    # this function extracts all the necessary information from the jekyll end and passes it into the pagination 
    # logic. Additionally it also contains all site specific actions that the pagination logic needs access to
    # (such as how to create new pages)
    # 
    class PaginationGenerator < Generator
      # This generator is safe from arbitrary code execution.
      safe true

      # This generator should be passive with regard to its execution
      priority :lowest
      
      # Generate paginated pages if necessary (Default entry point)
      # site - The Site.
      #
      # Returns nothing.
      def generate(site)
      #begin
        # Generate the AutoPages first
        PaginateV2::AutoPages.create_autopages(site)

        # Retrieve and merge the pagination configuration from the site yml file
        default_config = Jekyll::Utils.deep_merge_hashes(DEFAULT, site.config['pagination'] || {})

        # Compatibility Note: (REMOVE AFTER 2018-01-01)
        # If the legacy paginate logic is configured then read those values and merge with config
        if !site.config['paginate'].nil?
          Jekyll.logger.info "Pagination:","Legacy paginate configuration settings detected and will be used."
          # You cannot run both the new code and the old code side by side
          if !site.config['pagination'].nil?
            err_msg = "The new jekyll-paginate-v2 and the old jekyll-paginate logic cannot both be configured in the site config at the same time. Please disable the old 'paginate:' config settings by either omitting the values or setting them to 'paginate:off'."
            Jekyll.logger.error err_msg 
            raise ArgumentError.new(err_msg)
          end

          default_config['per_page'] = site.config['paginate'].to_i
          default_config['legacy_source'] = site.config['source']
          if !site.config['paginate_path'].nil?
            default_config['permalink'] = site.config['paginate_path'].to_s
          end
          # In case of legacy, enable pagination by default
          default_config['enabled'] = true
          default_config['legacy'] = true
        end # Compatibility END (REMOVE AFTER 2018-01-01)

        # If disabled then simply quit
        if !default_config['enabled']
          Jekyll.logger.info "Pagination:","Disabled in site.config."
          return
        end

        # Handle deprecation of settings and features
        if( !default_config['title_suffix' ].nil? )
          Jekyll::Deprecator.deprecation_message "Pagination: The 'title_suffix' configuration has been deprecated. Please use 'title'. See https://github.com/sverrirs/jekyll-paginate-v2/blob/master/README-GENERATOR.md#site-configuration"
        end

        Jekyll.logger.debug "Pagination:","Starting"

        ################ 0 ####################
        # Get the types of pages/docs to look over.
        # Specified as 'type' => ['path', 'path']
        # type is either 'pages' or a collection name
        # User can also specify 'all' or 'collections' to mean all collections
        # In addition, selected pages/docs must begin with at least one of 'path'
        # 'path' can contain * as a wildcard
        search = Hash.new { |hash, key| hash[key] = [] }

        # Load the search list
        list = default_config['search']
        
        if list.is_a?(Hash) && list.size > 0
          # Normalize the list hash
          list = list.to_a.map { |s|
            type, paths = s
            if paths.is_a?(Array)
              paths = paths.flatten.map { |p|
                Utils.remove_leading_slash(p.to_s.gsub(/\s+/, '').gsub(/\*{2,}/, '*'))
              }
            else
              paths = [paths.to_s.strip]
            end
            paths.reject!(&:empty?)
            # Default to no path filtering if couldn't get a path string
            paths = ['*'] if paths.empty?
            [
              type.to_s.strip,
              paths
            ]
          }.to_h
          
          # Validation
          collections_except_posts = site.collection_names - ['posts']
          valid_collection_catchall = ['all', 'collections']
          valid_types = collections_except_posts + valid_collection_catchall + ['pages']

          # Keys can only be 'pages', collection names or all-collection keyword
          list.select! do |type, paths|
            valid_types.include?(type)
          end

          # Parse the hash in order of specification
          # Later specification combines with prior specification
          # e.g. specifying a path for 'all' first, and then one for a specific collection, will result in that specific collection having two search paths
          # Search list is built up
          list.each do |type, paths|
            if valid_collection_catchall.include?(type)
              # User has specified all collections (in either of 2 ways)
              # Swap this out with the actual collection names
              collections_except_posts.each do |t|
                search[t] += paths
              end
            else
              search[type] += paths
            end
          end

        end

        # Force default if list parsing has resulted in an empty search
        if search.empty?
          search = { DEFAULT['search'].keys[0] => [DEFAULT['search'].values[0]] }
          Jekyll.logger.warn "Pagination:", "List of types to search over was invalid. Defaulting to all pages."
        end

        # Process path strings into Regexp's
        wildcard = '.*?'
        search = search.to_a.map { |s|
          type, paths = s
          paths.uniq!
          if paths.include?('*')
            # If any path has been reduced to just a wildcard, the rest of the set doesn't matter
            # False is interpreted later as "no path-based filter"
            paths = false
          else
            paths.map! do |path|
              fragments = path.split('*').reject(&:empty?).map { |f| Regexp.escape(f) }
              '^' +
              (path.start_with?('*') ? wildcard : '') +
              fragments.join(wildcard) +
              (path.end_with?('*') ? wildcard : '')
            end
            # Reduce all paths down to one Regex with a union
            paths = Regexp.new(paths.join('|'))
          end
          [type, paths]
        }.to_h
        

        ################ 1 ####################
        # Get pages to search over to find the pagination templates
        all_pages = []
        search.each do |type, paths|
          if type == 'pages'
            new_pages = site.pages
            count = new_pages.length
            new_pages = new_pages.sort_by { |d| d.relative_path } # Useful for debugging
            
            new_pages.select! { |page|
              paths.match?(
                Utils.remove_leading_slash(page.relative_path)
              )
            } if paths

          else
            # Collection docs have slightly different path handling
            new_pages = site.collections[type].docs
            count = new_pages.length
            new_pages = new_pages.sort_by { |d| d.cleaned_relative_path } # Useful for debugging

            new_pages.select! { |page|
              paths.match?(
                Utils.remove_leading_slash(
                  # cleaned_relative_path is relative_path without collection folder and without ext
                  page.cleaned_relative_path + page.extname
                )
              )
            } if paths

          end
          Jekyll.logger.debug "Pagination:", "Will search #{new_pages.length} of #{count} site.#{type} for pagination pages."
          all_pages += new_pages
        end

        # Get the default title of the site (used as backup when there is no title available for pagination)
        site_title = site.config['title']

        ################ 2 #################### 
        # Specify the callback function that returns the correct docs/posts based on the collection name
        # "posts" are just another collection in Jekyll but a specialized version that require timestamps
        # This collection is the default and if the user doesn't specify a collection in their front-matter then that is the one we load
        # If the collection is not found then empty array is returned
        collection_by_name_lambda = lambda do |collection_name|
          coll = []
          if collection_name == "all"
            # the 'all' collection_name is a special case and includes all collections in the site (except posts!!)
            # this is useful when you want to list items across multiple collections
            site.collections.each do |coll_name, coll_data|
              if( !coll_data.nil? && coll_name != 'posts')
                coll += coll_data.docs.select { |doc| !doc.data.has_key?('pagination') } # Exclude all pagination pages
              end
            end
          else
            # Just the one collection requested
            if !site.collections.has_key?(collection_name)
              return []
            end

            coll = site.collections[collection_name].docs.select { |doc| !doc.data.has_key?('pagination') } # Exclude all pagination pages
          end
          return coll
        end

        ################ 3 ####################
        # Create the proc that constructs the real-life site page
        # This is necessary to decouple the code from the Jekyll site object
        page_add_lambda = lambda do | newpage |
          if newpage.respond_to?(:collection)
            site.collections[newpage.collection.label].docs << newpage
          else
            site.pages << newpage # Add the page to the site so that it is generated correctly
          end
          return newpage # Return the site to the calling code
        end

        ################ 3.5 ####################
        # lambda that removes a page from the site pages list
        page_remove_lambda = lambda do | page_to_remove |
          if page_to_remove.respond_to?(:collection)
            site.collections[page_to_remove.collection.label].docs.delete_if {|page| page == page_to_remove }
          else
            site.pages.delete_if {|page| page == page_to_remove }
          end
        end

        ################ 4 ####################
        # Create a proc that will delegate logging
        # Decoupling Jekyll specific logging
        logging_lambda = lambda do | message, type="info" |
          if type == 'debug'
            Jekyll.logger.debug "Pagination:","#{message}"
          elsif type == 'error'
            Jekyll.logger.error "Pagination:", "#{message}"
          elsif type == 'warn'
            Jekyll.logger.warn "Pagination:", "#{message}"
          else
            Jekyll.logger.info "Pagination:", "#{message}"
          end
        end

        ################ 5 ####################
        # Now create and call the model with the real-life page creation proc and site data
        model = PaginationModel.new(logging_lambda, page_add_lambda, page_remove_lambda, collection_by_name_lambda)
        if( default_config['legacy'] ) #(REMOVE AFTER 2018-01-01)
          Jekyll.logger.warn "Pagination:", "You are running jekyll-paginate backwards compatible pagination logic. Please ignore all earlier warnings displayed related to the old jekyll-paginate gem."
          all_posts = site.site_payload['site']['posts'].reject { |post| post['hidden'] }
          model.run_compatability(default_config, all_pages, site_title, all_posts) #(REMOVE AFTER 2018-01-01)
        else
          count = model.run(default_config, all_pages, site_title)
          Jekyll.logger.info "Pagination:", "Complete, processed #{count} pagination page(s)"
        end

      #rescue => ex
      #  puts ex.backtrace
      #  raise
      #end
      end # function generate
    end # class PaginationGenerator

  end # module PaginateV2
end # module Jekyll
