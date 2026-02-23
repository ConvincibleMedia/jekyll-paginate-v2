# frozen_string_literal: true

module Jekyll
  module Plugins
    module PaginateV3
      module Utils
        # General helpers for coercion and normalisation.
        module Core
          # Deep copy helper for plain Ruby hashes/arrays used in config merging.
          def deep_copy(value)
            if value.is_a?(Hash)
              value.each_with_object({}) { |(key, child), copy| copy[key] = deep_copy(child) }
            elsif value.is_a?(Array)
              value.map { |child| deep_copy(child) }
            else
              value
            end
          end

          # Converts a value into an array. Strings can be treated as comma-delimited lists.
          def arrayify(value, split_commas: false)
            if value.nil?
              []
            elsif value.is_a?(Array)
              value.flatten.compact
            elsif split_commas && value.is_a?(String)
              value.split(',').map(&:strip).reject(&:empty?)
            else
              [value]
            end
          end

          # Normalises hash keys recursively to strings.
          def stringify_keys(value)
            return value unless value.is_a?(Hash)

            value.each_with_object({}) do |(key, child), copy|
              copy[key.to_s] = child.is_a?(Hash) ? stringify_keys(child) : child
            end
          end

          # Returns a hash from any input object, or an empty hash for unsupported values.
          def safe_hash(value)
            value.is_a?(Hash) ? stringify_keys(value) : {}
          end

          # Parses any config field that allows comma-delimited arrays.
          def comma_delimited_array(value)
            if value.is_a?(Array)
              value.flatten.map { |entry| entry.to_s.strip }.reject(&:empty?)
            else
              value.to_s.split(',').map(&:strip).reject(&:empty?)
            end
          end

          # Expands `layout` + `layouts` config into a unique array of layout names.
          def normalise_layouts(config)
            source = safe_hash(config)
            layouts = []
            layouts.concat(arrayify(source['layouts'], split_commas: true)) if source.key?('layouts')
            layouts.concat(arrayify(source['layout'], split_commas: true)) if source.key?('layout')
            layouts.map { |entry| entry.to_s.strip }.reject(&:empty?).uniq
          end
        end
      end
    end
  end
end