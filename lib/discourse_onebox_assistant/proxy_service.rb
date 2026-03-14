# frozen_string_literal: true

require "httparty"

module ::DiscourseOneboxAssistant
  class ProxyService
    def page_source(url)
      response = HTTParty.get(request_url(url), headers: request_headers)
      response[
        SiteSetting.onebox_assistant_api_page_source_field
      ].tap do |page_source|
        if page_source.nil?
          Rails.logger.warn(
            "ONEBOX ASSIST: the API returned nothing for #{url}"
          )
        end
      end
    end

    private

    def request_url(url)
      [
        SiteSetting.onebox_assistant_api_base_address,
        SiteSetting.onebox_assistant_api_base_query,
        url,
        SiteSetting.onebox_assistant_api_options
      ].join
    end

    def request_headers
      { "x-api-key" => SiteSetting.onebox_assistant_api_key }
    end
  end
end
