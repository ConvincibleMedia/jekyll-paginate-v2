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
        # false = invalid filter
        filter = normalize_filter(filter)
        return posts if filter == false

        posts.select do |item|
          data = item.respond_to?(:data) ? item.data : item
          next false unless data.is_a?(Hash)

          has_value, item_value = fetch_filter_value(data, key)
          next false unless has_value

          # Array-ify the value we are checking against.
          # Strings may represent several values delimited by commas/semicolons.
          item_values = if item_value.is_a?(Array)
                          item_value.flatten
                        elsif item_value.is_a?(String)
                          item_value.split(/,|;/).map(&:strip)
                        else
                          [item_value]
                        end

          # Run filter on this item value
          check_filter(filter, item_values)
        end
      end #function read_config_value_and_filter_posts

      #
      # Conform how the filter is specified, into a hash
      #
      def self.normalize_filter(filter, wrapped = false)
        # User has specified a hash in the final normalized form (with list key)
        if filter.is_a?(Hash)
          filter = stringify_hash_keys(filter)
          if filter.key?('list')
            filter = filter.select { |k, _| ['list', 'join'].include?(k) } # Only allow these keys
            # Recurse
            filter['list'] = normalize_filter(filter['list'], true)
            # If operating on the list failed, the filter is invalid
            return false if filter['list'] == false
            # Ensure join is valid (if present)
            filter['join'] = filter['join'].to_s.strip.downcase if filter.key?('join')
            filter['join'] = 'or' unless ['or', 'and'].include?(filter['join'])
            # Return valid filter
            return wrapped ? [filter] : filter
          end
        end

        # Past this point the filter is not a normalized hash

        # Conform the filter into an array
        if filter.is_a?(String)
          # Split strings into arrays
          filter = filter.split(/,|;/).map(&:strip)
        elsif filter.is_a?(Integer) || filter.is_a?(Float) || filter.is_a?(Date) || filter.is_a?(Regexp)
          # Wrap scalars to arrays of 1 item
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
              value = value.strip
              # Check if string is numeric or date
              value = interpret_numeric(value)
              # Check if string is a regex
              if value.is_a?(String) && value =~ %r{\A/(.*?)/([imx]*)\z}
                regex_source = Regexp.last_match(1)
                regex_flags = Regexp.last_match(2)
                options = 0
                options |= Regexp::IGNORECASE if regex_flags.include?('i')
                options |= Regexp::MULTILINE if regex_flags.include?('m')
                options |= Regexp::EXTENDED if regex_flags.include?('x')
                Regexp.new(regex_source, options)
              else
                value # it's just a string
              end
            elsif value.is_a?(Hash)
              value = stringify_hash_keys(value)

              # Support nested boolean grouping ({list: [...], join: and|or}).
              if value.key?('list')
                nested = normalize_filter(value)
                next false if nested == false
                next nested
              end

              # Only certain allowed keys in hash
              value = value.select { |k, _| ['min', 'max'].include?(k) }
              # If hash has min/max keys, conform them
              ['min', 'max'].each do |numeric_key|
                if value.key?(numeric_key)
                  interpreted = interpret_numeric_or_date_keyword(value[numeric_key])
                  if interpreted == false
                    value.delete(numeric_key)
                  else
                    value[numeric_key] = interpreted
                  end
                end
              end
              # If min/max values have survived so far...
              if !value['min'].nil? && !value['max'].nil?
                # Min/max comparison must be of same data type
                if (value['min'].is_a?(Float) && value['max'].is_a?(Integer)) ||
                   (value['min'].is_a?(Integer) && value['max'].is_a?(Float))
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
          { 'list' => filter, 'join' => 'or' } # default join is 'or'
        end
      end

      #
      # Converts string representations of numerics into numeric data types
      # Additionally interpreting 'now'/'today' as Date.today
      #
      def self.interpret_numeric_or_date_keyword(value)
        normalized_value = value.to_s.strip.downcase
        return Date.today if ['now', 'today'].include?(normalized_value)

        interpret_numeric(value, true)
      end

      #
      # Converts string representations of numerics into numeric data types
      #
      def self.interpret_numeric(value, must_be_numeric = false)
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
        # Normalise ad-hoc filter input so debug output is still safe.
        filter = normalize_filter(filter) if !filter.is_a?(Hash) || !filter.key?('list')
        return '[invalid filter]' if filter == false

        filter_to_s_internal(filter)
      end

      private

      # Build a compact human-readable debug string from a normalised filter.
      def self.filter_to_s_internal(filter)
        string = ''
        list = []
        filter['list'].each do |value|
          if value.is_a?(Hash)
            if value.key?('list')
              list << '(' + filter_to_s_internal(value) + ')'
            elsif value.key?('min') || value.key?('max')
              comparison = ''
              if value.key?('min')
                comparison << value['min'].to_s
                if value.key?('max')
                  comparison << ' to ' + value['max'].to_s
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

      # Evaluate whether any/all parts of the filter match, depending on join mode.
      def self.check_filter(filter, item_values)
        values = item_values.map { |value| value.is_a?(String) ? interpret_numeric(value) : value }
        evaluations = filter['list'].map do |filter_part|
          if filter_part.is_a?(String) || filter_part.is_a?(Integer) || filter_part.is_a?(Float) || filter_part.is_a?(Date)
            values.include?(filter_part)
          elsif filter_part.is_a?(Regexp)
            item_values.any? { |value| filter_part.match?(value.to_s) }
          elsif filter_part.is_a?(Hash)
            if filter_part.key?('list')
              check_filter(filter_part, item_values)
            elsif filter_part.key?('min') || filter_part.key?('max')
              values.any? { |value| filter_range_match?(value, filter_part['min'], filter_part['max']) }
            else
              false
            end
          else
            false
          end
        end

        (filter['join'] || 'or') == 'and' ? evaluations.all? : evaluations.any?
      end

      # Evaluate a single value against an optional min/max range.
      def self.filter_range_match?(value, min_value, max_value)
        return false if value.nil?

        comparable_value = value.is_a?(String) ? interpret_numeric(value) : value

        if !min_value.nil?
          return false unless values_comparable?(comparable_value, min_value)
          return false if comparable_value < min_value
        end

        if !max_value.nil?
          return false unless values_comparable?(comparable_value, max_value)
          return false if comparable_value > max_value
        end

        true
      rescue ArgumentError, NoMethodError
        false
      end

      # Check if values can be safely compared with < and >.
      def self.values_comparable?(left, right)
        return true if left.class == right.class
        return true if (left.is_a?(Integer) || left.is_a?(Float)) && (right.is_a?(Integer) || right.is_a?(Float))

        left.respond_to?(:<=>) && !((left <=> right).nil?)
      rescue ArgumentError, NoMethodError
        false
      end

      # Fetch a key from page/document metadata using common key variants.
      def self.fetch_filter_value(data, key)
        return [true, data[key]] if data.key?(key)

        key_string = key.to_s
        return [true, data[key_string]] if data.key?(key_string)

        key_symbol = key_string.to_sym
        return [true, data[key_symbol]] if data.key?(key_symbol)

        [false, nil]
      end

      # Recursively normalise hash keys to strings.
      def self.stringify_hash_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(key, value), result|
          result[key.to_s] = value.is_a?(Hash) ? stringify_hash_keys(value) : value
        end
      end

      private_class_method :filter_to_s_internal, :check_filter, :filter_range_match?, :values_comparable?, :fetch_filter_value, :stringify_hash_keys, :interpret_numeric_or_date_keyword, :interpret_numeric

    end #class PaginationIndexer

  end #module PaginateV2
end #module Jekyll
