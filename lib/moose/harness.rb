module Meese
  class Harness
    class << self
      def run_as(current_test:, suite:, opts: {}, &block)
        needs_browser = opts.fetch(:needs_browser, true)
        suite_instance = Meese.instance_for_suite(suite)
        browser = current_test.new_browser({test_suite: suite_instance}.merge(opts)) if needs_browser
        begin
          response = block.call(browser, suite_instance)
        ensure
          current_test.remove_browser(browser) if needs_browser
        end
        response
      end
    end
  end
end
