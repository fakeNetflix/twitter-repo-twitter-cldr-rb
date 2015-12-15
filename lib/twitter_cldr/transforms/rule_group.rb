# encoding: UTF-8

# Copyright 2012 Twitter, Inc
# http://www.apache.org/licenses/LICENSE-2.0

# http://unicode.org/reports/tr35/tr35-general.html#Transforms
# http://unicode.org/cldr/utility/transform.jsp

module TwitterCldr
  module Transforms

    class RuleGroup
      class << self
        def load(resource_name)
          rule_groups[resource_name] ||= begin
            resource = resource_for(resource_name)
            direction = direction_from(resource)
            new(parse_resource(resource), direction)
          end
        end

        def build(rule_list, direction)
          rules = parse_rules(rule_list)
          new(rules, direction)
        end

        def exists?(resource_name)
          TwitterCldr.resource_exists?(
            'shared', 'transforms', resource_name
          )
        end

        private

        def direction_from(resource)
          case transform_from(resource)[:direction]
            when 'both'
              :bidirectional
            else
              :forward
          end
        end

        def rule_groups
          @rule_groups ||= {}
        end

        def parse_resource(resource)
          parse_rules(rules_from(resource))
        end

        def parse_rules(rule_list)
          symbol_table = {}
          rules = []

          parse_each_rule(rule_list, symbol_table) do |rule|
            if rule.is_a?(VariableRule)
              symbol_table[rule.name] = rule
            else
              rules << rule
            end
          end

          rules
        end

        def parse_each_rule(rule_list, symbol_table)
          rule_list.each_with_index do |rule_text, idx|
            yield parse_rule(rule_text, symbol_table, idx)
          end
        end

        def parse_rule(rule_text, symbol_table, index)
          rule_type = identify_rule_type(rule_text)
          class_for_rule_type(rule_type).parse(
            rule_text, symbol_table, index
          )
        end

        def class_for_rule_type(rule_type)
          rule_type = rule_type.to_s.capitalize

          case rule_type
            when 'Variable'
              VariableRule
            else
              const = TwitterCldr::Transforms.const_get(rule_type + 's')
              const.const_get(rule_type + 'Rule')
          end
        end

        def identify_rule_type(rule_text)
          rule_text.strip!

          case rule_text
            when /\A::[\s]*\(?[\s]*\[/
              :filter
            when /\A::/
              :transform
            when /([^\\]|\A)[<>]{1,2}/
              :conversion
            else
              :variable
          end
        end

        def rules_from(resource)
          transform_from(resource)[:rules]
        end

        def transform_from(resource)
          resource[:transforms].first
        end

        def resource_for(resource_name)
          TwitterCldr.get_resource('shared', 'transforms', resource_name)
        end
      end

      attr_reader :rules, :direction

      def initialize(rules, direction)
        @rules = rules
        @direction = direction
      end

      # all rules are either forward or bidirectional
      def bidirectional?
        direction == :bidirectional
      end

      alias_method :can_invert?, :bidirectional?

      def forward_rule_set
        @forward_rule_set ||= begin
          RuleSet.new(
            filter_rule, inverse_filter_rule, ct_rules
          )
        end
      end

      def backward_rule_set
        if can_invert?
          @backward_rule_set ||= forward_rule_set.invert
        else
          raise NotInvertibleError,
            "cannot invert this #{self.class.name}"
        end
      end

      private

      def ct_rules
        @ct_rules ||= rules.select do |rule|
          rule.is_transform_rule? || rule.is_conversion_rule?
        end
      end

      def filter_rule
        @filter_rule ||= if is_forward_filter?(rules.first)
          rules.first
        else
          Filters::NullFilter.new
        end
      end

      def inverse_filter_rule
        @inverse_filter_rule ||= if is_backward_filter?(rules.last)
          rules.last
        else
          Filters::NullFilter.new
        end
      end

      def is_forward_filter?(rule)
        rule.is_filter_rule? && !rule.backward?
      end

      def is_backward_filter?(rule)
        rule.is_filter_rule? && rule.backward?
      end
    end

  end
end
