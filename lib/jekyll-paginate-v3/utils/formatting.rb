# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Utils
        # Helpers for formatter-style macro replacement.
        module Formatting
          # Replaces `:num` and optionally `:max` placeholders.
          def format_page_number(pattern, current_page, max_pages = nil)
            output = pattern.to_s.sub(':num', current_page.to_i.to_s)
            output = output.sub(':max', max_pages.to_i.to_s) unless max_pages.nil?
            output
          end

          # Replaces `:title` and numeric placeholders in title patterns.
          def format_page_title(pattern, title, current_page = nil, max_pages = nil)
            format_page_number(pattern.to_s.sub(':title', title.to_s), current_page, max_pages)
          end

          # Replaces placeholders in a string where keys are in `token_map`.
          # Longest-key-first replacement avoids collisions between nested tokens.
          def replace_tokens(template, token_map)
            output = template.to_s
            keys = token_map.keys.sort_by { |key| -key.length }
            keys.each do |key|
              output = output.gsub(":#{key}", token_map[key].to_s)
            end
            output
          end
        end
      end
    end
  end
end