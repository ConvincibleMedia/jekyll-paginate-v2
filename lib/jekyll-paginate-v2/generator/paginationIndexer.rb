module Jekyll
  module PaginateV2::Generator

    # 
    # Performs indexing of the posts or collection documents
    # as well as filtering said collections when requested by the defined filters.
    class PaginationIndexer
      #
      # Create a hash index for all post based on a key in the post.data table
      #
      def self.index_posts_by(all_posts, index_key)
        return nil if all_posts.nil?
        return all_posts if index_key.nil?
        index = {}
        all_posts.each do |post|
          next if post.data.nil?
          next if !post.data.has_key?(index_key)
          next if post.data[index_key].nil?
          next if post.data[index_key].size <= 0
          next if post.data[index_key].to_s.strip.length == 0
          
          # Only tags and categories come as premade arrays, locale does not, so convert any data
          # elements that are strings into arrays
          post_data = post.data[index_key]
          if post_data.is_a?(String)
            post_data = post_data.split(/;|,|\s/)
          end
          
          post_data.each do |key|
            key = key.to_s.downcase.strip
            # If the key is a delimetered list of values 
            # (meaning the user didn't use an array but a string with commas)
            key.split(/;|,/).each do |k_split|
              k_split = k_split.to_s.downcase.strip #Clean whitespace and junk
              if !index.has_key?(k_split)
                index[k_split.to_s] = []
              end
              index[k_split.to_s] << post
            end
          end
        end
        return index
      end # function index_posts_by
      
      #
      # Creates an intersection (only returns common elements)
      # between multiple arrays
      #
      def self.intersect_arrays(first, *rest)
        return nil if first.nil?
        return nil if rest.nil?
        
        intersect = first
        rest.each do |item|
          return [] if item.nil?
          intersect = intersect & item
        end
        return intersect
      end #function intersect_arrays
      
      #
      # Creates a union (returns unique elements from both)
      # between multiple arrays
      #
      def self.union_arrays(first, *rest)
        return nil if first.nil?
        return nil if rest.nil?

        union = first
        rest.each do |item|
          return [] if item.nil?
          union = union | item
        end
        return union
      end #function union_arrays

      #
      # Filters posts to only include those with a metadata key matching a filter
      #
      def self.filter_posts(posts, key, filter)
        return nil if posts.nil?
        return posts if key.nil?
        return posts if filter.nil?

        # Normalize the representation of the filter test
        # False = invalid filter
        filter = normalize_filter(filter)
        return posts if filter == false

        return posts.select { |item|
          next nil unless item.has_key?(key) # Ensure the specified key exists
      
          # Array-ify the value we're checking against
          item_value = item[key]
          item_value = item_value.split(/,|;/).map(&:strip) unless item_value.is_a?(Array)
      
          # Run filter on this item value
          check_filter(filter, item_value)

          }.compact
        end
        
      end #function read_config_value_and_filter_posts

      def check_filter(filter, item_value)
        filter['list'].any? do |filter_part|
          if filter_part.is_a?(String)
            item_value.include?(filter_part)
          elsif filter_part.is_a?(Integer)
            item_value.include?(filter_part)
          elsif filter_part.is_a?(Regexp)
            item_value.any? { |v| filter_part.match?(v) }
          elsif filter_part.is_a?(Hash)
            if filter_part.has_key?('list')
              check_filter(filter_part)
            elsif filter_part.has_key?('min') || filter_part.has_key?('max')
              item_value.any? { |v| v >= filter_part['min'] && v <= filter_part['max'] }
            end
          else
            false # Invalid filter part
          end
        end
      end

      #
      # Conform how the filter is specified, into a hash
      #
      def normalize_filter(filter, wrapped = false)
        # User has specified a hash in the final normalized form (with list key)
        if filter.is_a?(Hash)
          filter = filter.stringify_keys
          if filter.has_key?('list')
            filter = filter.slice['list', 'join'] # Only allowed these keys
            # Recurse
            filter['list'] = normalize_filter(filter['list'], true)
            # If operating on the list failed, the filter is invalid
            return false if filter['list'] == false
            # Ensure join is valid (if present)
            if filter.has_key('join')
              filter['join'] = filter['join'].to_s.strip.lower
              filter.delete('join') if !['or', 'and'].include?(filter['join'])
            end
            # Return valid filter
            return filter
          end
        end

        # Past this point the filter is not a normalized hash

        # Conform the filter into an array
        if filter.is_a?(String)
          # Split strings into arrays
          filter = filter.split(/,|;/).map(&:strip)
        elsif filter.is_a?(Integer) || filter.is_a?(Regexp)
          # Wrap integers/regexes to arrays of 1 item
          filter = [filter]
        elsif filter.is_a?(Hash)
          filter = [filter]
        end
      
        # Now process arrays
        if filter.is_a?(Array)
          # No arrays of arrays
          filter.flatten!
          # Operate on values in array
          filter = filter.map do |value|
            if value.is_a?(String)
              # Check if string is numeric or date
              value = interpret_numeric(value)
              # Check if string is a regex
              if value =~ /^\/.+\/[i]?$/
                Regexp.new(value[1..-2], Regexp.options(value))
              else
                value # it's just a string
              end
            elsif value.is_a?(Hash)
              # Only certain allowed keys in hash
              value = value.slice['min', 'max']
              # If hash has min/max keys, conform them
              ['min', 'max'].each do |numeric_key|
                if value.has_key?(numeric_key)
                  interpeted = interpret_numeric_or_date_keyword(value[numeric_key])
                  value.delete(numeric_key) if value[numeric_key] == false
                end
              end
              # If min/max values have survived so far...
              if value['min'] != nil && value['max'] != nil
                # Min/max comparison must be of same data type
                if ( value['min'].class == Float && value['max'].class == Integer ) ||
                  ( value['min'].class == Integer && value['max'].class == Float )
                  value['min'] = value['min'].to_f
                  value['max'] = value['max'].to_f
                end
                next false if value['min'].class != value['max'].class
                # Normalize order of min/max
                if value['min'] > value['max']
                  max = value['max'].dup
                  value['max'] = value['min'].dup
                  value['min'] = max
                end
              end
              if 
              # Invalid hash
              next false if value == {}
              # Conformed hash
              value
            elsif value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(Date)
              # Return acceptable data type
              value
            else
              # Value in array is not of acceptable type
              next false
            end
          end
          # Remove invalid filters in array
          filter = filter.select { |value| value != false }
          return false if filter.length == 0
        end
      
        # Filter is now an array of valid filters
        if wrapped
          filter
        else
          { list: filter, join: 'or' } # default join is 'or'
        end
      end

      #
      # Converts string representations of numerics into numeric data types
      # Additionally interpreting 'now'/'today' as Date.now
      #
      def interpret_numeric_or_date_keyword(value)
        return Date.now if ['now', 'today'].include(value)
        return interpret_numeric(value, true)
      end

      #
      # Converts string representations of numerics into numeric data types
      #
      def interpret_numeric(value, must_be_numeric = false)
        # Check if value is already interpreted
        [Integer, Float, Date].each do |type|
          return value if value.is_a?(type)
        end
        
        if value.is_a?(String)
          # Check for Integer
          return value.to_i if value.match?(/\A[+-]?\d+\z/)
          # Check for Float
          return value.to_f if value.match?(/\A[+-]?\d+\.\d+\z/)
          # Check for Date
          begin
            return Date.parse(value)
          rescue ArgumentError
            return value
          end
        end

        # Couldn't interpret string as another type
        if must_be_numeric
          # But it had to be another type, so return false
          return false
        else
          # Return it as it was
          return value
        end
      end

      #
      # Create a single-line string representation of a normalized filter which could be hash, array, etc.
      #
      def self.filter_to_s(filter)
        string = ''
        list = []
        filter['list'].each do |value|
          if value.is_a?(Hash)
            if value.has_key?('list')
              list << '(' + filter_to_s(value) + ')'
            elsif value.has_key?('min') || value.has_key?('max')
              comparison = ''
              if value.has_key?('min')
                comparison << value['min'].to_s
                if value.has_key?('max')
                  comparison << ' to ' + value['max']
                else
                  comparison << ' or more'
                end
              else
                comparison << value['max'].to_s + ' or less'
              end
              list << comparison
            end
          else
            list << value.to_s.gsub(/[\s\n\r]+/, ' ').strip
          end
        end
        string << list.join(' ' + (filter['join'] || 'or') + ' ')
        string
      end

    end #class PaginationIndexer

  end #module PaginateV2
end #module Jekyll
