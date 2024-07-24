# frozen_string_literal: true

module Appsignal
  class SampleData
    def initialize
      @blocks = []
    end

    def set(data = nil, &block)
      if block_given?
        @blocks = [block]
      elsif accepted_type?(data)
        @blocks = [data]
      end
    end

    def add(data = nil, &block)
      if block_given?
        @blocks << block
      elsif accepted_type?(data)
        @blocks << data
      end
    end

    def value
      value = nil
      @blocks.each do |block_or_value|
        new_value =
          if block_or_value.respond_to?(:call)
            block_or_value.call
          else
            block_or_value
          end
        next unless accepted_type?(new_value)

        value = merge_values(value, new_value)
      end

      value
    end

    def value?
      @blocks.any?
    end

    private

    def accepted_type?(value)
      value.is_a?(Hash) || value.is_a?(Array)
    end

    def merge_values(value_original, value_new)
      unless value_new.instance_of?(value_original.class)
        # Value types don't match. The block is leading so overwrite the value
        return value_new
      end

      case value_original
      when Hash
        value_original.merge(value_new)
      when Array
        value_original.concat(value_new)
      else
        value_new
      end
    end
  end
end
