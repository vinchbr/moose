require 'thread'

module Moose
  module TestGroup
    class Instance < Base
      attr_accessor :start_time, :end_time
      attr_reader :directory, :description, :test_suite

      def initialize(directory:, description:, test_suite:)
        @directory = directory
        @description = description
        @test_suite = test_suite
        read_key_words_yamls
      end

      def build
        Dir.glob(File.join(directory, "/**/*.rb")) do |file|
          if file =~ /_configuration.rb$/
            configuration.load_file(file)
          else
            add_test_case_from(file)
          end
        end
      end

      def run!(opts = {})
        self.start_time = Time.now
        if run_in_threads?(opts)
          run_in_threads(filtered_test_case_cache, opts)
        else
          run_out_of_threads(filtered_test_case_cache, opts)
        end
        self.end_time = Time.now
        self
      end

      def rerun_failed!(opts = {})
        modified_options = opts.merge({:rerun => true})
        if run_in_threads?(opts)
          run_in_threads(failed_tests, modified_options)
        else
          run_out_of_threads(failed_tests, modified_options)
        end
        self.end_time = Time.now
        self
      end

      def failed_tests
        filtered_test_case_cache.select { |test_case|
          test_case.failed?
        }
      end

      def report!(opts = {})
        filtered_test_case_cache.each do |test_case|
          test_case.final_report!(opts)
        end
      end

      def configuration
        @configuration ||= Configuration.new
      end

      def filter_from_options!(options)
        files_to_run = options.fetch(:files_to_run, [])
        tags = options.fetch(:tags, {})
        include_tags = tags.fetch(:inclusion_filters, [])
        exclude_tags = tags.fetch(:exclusion_filters, [])
        test_case_cache.each do |test_case|
          if files_to_run.length > 0
            next unless files_to_run.any? { |file_name|
              Utilities::FileUtils.file_names_match?(file_name, test_case.file)
            }
          end

          if exclude_tags.length > 0
            next if exclude_tags.any? { |tag|
              test_case.keywords.include?(tag)
            }
          end

          if include_tags.length > 0
            next unless include_tags.any? { |tag|
              test_case.keywords.include?(tag)
            }
          end
          filtered_test_case_cache << test_case
        end
      end

      def name
        Utilities::FileUtils.file_name_without_ext(directory)
      end

      def has_available_tests?
        filtered_test_case_cache.size > 0
      end

      def metadata
        starting_metadata = [:time_elapsed,:start_time,:end_time,:directory,:description].inject({}) do |memo, method|
          begin
            memo.merge!(method => send(method))
            memo
          rescue => e
            # drop error for now
            memo
          end
        end
        starting_metadata.merge(
          :test_suite => test_suite.metadata
        )
      end

      def time_elapsed
        return unless end_time && start_time
        end_time - start_time
      end

      private

      def run_in_threads?(options = {})
        return configuration.run_in_threads unless configuration.run_in_threads.nil?
        option_to_run_in_threads = options.fetch(:run_in_threads, nil)
        return option_to_run_in_threads unless option_to_run_in_threads.nil?
        moose_config.run_in_threads
      end

      def filtered_test_case_cache
        @filtered_test_case_cache ||= []
      end

      def run_in_threads(test_collection, opts = {})
        test_collection.each_slice(moose_config.test_thread_count) do |test_case_set|
          threads = []
          test_case_set.each_with_index do |test_case, index|
            threads << Thread.new do
              run_test_case(
                test_case: test_case,
                options: opts
              )
            end
          end
          threads.map(&:join)
        end
      end

      def run_out_of_threads(test_collection, opts = {})
        test_collection.each do |test_case|
          run_test_case(
            test_case: test_case,
            options: opts
          )
        end
      end

      def run_test_case(test_case:, options: {})
        return if Moose.world.wants_to_quit
        test_case.run!(options)
      end

      def results
        @results ||= []
      end

      def add_test_case_from(file)
        file_name = file_name_for(file)
        test_case = TestCase.new(
          file: file,
          test_group: self,
          extra_metadata: keywords.fetch("test cases", {}).fetch(file_name, {})
        )
        test_case.build
        test_case_cache << test_case
      end

      def test_case_cache
        @test_case_cache ||= []
      end

      def keywords
        @keywords ||= {}
      end

      def read_key_words_yamls
        Dir.glob(File.join(directory, "/*.yml")) do |f|
          keywords.merge!(read_yaml_file(f))
        end
      end
    end
  end
end
