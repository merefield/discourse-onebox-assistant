# name: discourse-onebox-assistant
# about: provides alternative path for grabbing one-boxes when initial crawl fails
# version: 3.0.4
# authors: merefield
# url: https://github.com/merefield/discourse-onebox-assistant

gem 'mime-types-data', '3.2025.0422', { require: false }
gem 'mime-types', '3.6.2', { require: false }
gem 'httparty', '0.21.0'

require 'net/http'

enabled_site_setting :onebox_assistant_enabled

after_initialize do
  %w[
    ../discourse/lib/oneboxer_edits.rb
    ../discourse/lib/onebox/helpers_edits.rb
  ].each do |path|
    load File.expand_path(path, __FILE__)
  end
end
