module Moose
  module Page
    class Base
      class ElementError < Moose::Error; end
      class SectionError < Moose::Error; end

      include Actions
      attr_reader :browser

      class << self
        def elements
          @elements ||= {}
        end

        def element(name,&block)
          raise ElementError, "Element name can not be nil" if name.nil?
          if existing_key?(name)
            raise ElementError,"Duplicate definations for Element - #{name} on Page - #{to_s}"
          end
          elements[name] = block
        end

        def sections
          @sections ||= {}
        end

        def section(name, klass, &block)
          raise SectionError, "Section name can not be nil" if name.nil?
          if existing_key?(name)
            raise SectionError,"Duplicate definations for Section - #{name} on Page - #{to_s}"
          end
          sections[name] = {
            :klass => klass,
            :block => block
          }
        end

        def existing_key?(key_name)
          !elements[key_name].nil? || !sections[key_name].nil?
        end

        def inherited(klass)
          klass.elements.merge!(elements)
        end
      end

      def initialize(browser:)
        @browser = browser
        add_element_methods
        add_section_methods
      end

      def go_to(path)
        browser.goto(path)
        wait_until do
          browser.ready_state == 'complete'
        end
      end

      def element_for(*args)
        browser.element_for(*args)
      end

      private

      def add_element_methods # :nodoc:
        self.class.elements.each do |element_name,element_block|
          add_block_method(element_name, element_block)
        end
      end

      def add_section_methods # :nodoc:
        self.class.sections.each do |section_name,section_details|
          klass = section_details.fetch(:klass)
          section_block = section_details.fetch(:block)

          class_eval do
            define_method(section_name) do
              if memoizied = instance_variable_get("@#{section_name}")
                memoizied
              else
                instance_variable_set("@#{section_name}", klass.new(
                  :parent => self,
                  :browser => browser,
                  :element_block => section_block
                ))
              end
            end
          end
        end
      end

      def add_block_method(method_name, block) # :nodoc:
        class_eval do
          define_method(method_name) do |*args|
            self.instance_exec(*args, &block)
          end
        end
      end
    end
  end
end
