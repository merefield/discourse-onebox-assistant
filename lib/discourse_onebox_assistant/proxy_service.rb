# frozen_string_literal: true

require "cgi"
require "httparty"

module ::DiscourseOneboxAssistant
  class ProxyService
    def page_source(url)
      response = HTTParty.get(request_url(url), headers: request_headers)

      unless response.success? && response.parsed_response.is_a?(Hash)
        Rails.logger.warn(
          "ONEBOX ASSIST: unexpected response for #{url} " \
            "(status=#{response.code}, body=#{response.body.to_s.byteslice(0, 300)})"
        )
        return nil
      end

      response.parsed_response[
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
        CGI.escape(url.to_s),
        SiteSetting.onebox_assistant_api_options
      ].join
    end

    def request_headers
      { "x-api-key" => SiteSetting.onebox_assistant_api_key }
    end
  end
end
