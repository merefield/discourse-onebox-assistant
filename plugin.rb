# frozen_string_literal: true

# name: discourse-onebox-assistant
# about: provides alternative path for grabbing one-boxes when initial crawl fails
# version: 3.1.1
# authors: merefield
# url: https://github.com/merefield/discourse-onebox-assistant

gem "httparty", "0.24.2"

enabled_site_setting :onebox_assistant_enabled

module ::DiscourseOneboxAssistant
end

require_relative "lib/discourse_onebox_assistant/proxy_service"
require_relative "discourse/lib/oneboxer_edits"
require_relative "discourse/lib/onebox/helpers_edits"

after_initialize do
  if Oneboxer.singleton_class.ancestors.exclude?(::DiscourseOneboxAssistant::OneboxerEdits)
    Oneboxer.singleton_class.prepend(::DiscourseOneboxAssistant::OneboxerEdits)
  end

  if Onebox::Helpers.singleton_class.ancestors.exclude?(
       ::DiscourseOneboxAssistant::OneboxHelpersEdits,
     )
    Onebox::Helpers.singleton_class.prepend(::DiscourseOneboxAssistant::OneboxHelpersEdits)
  end
end
