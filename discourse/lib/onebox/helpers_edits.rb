# frozen_string_literal: true

module ::DiscourseOneboxAssistant
  module OneboxHelpersEdits
    # Synced from core `lib/onebox/helpers.rb#fetch_html_doc`.
    # Plugin-specific behavior is isolated in the `assistant_*` helper methods below.
    def fetch_html_doc(url, headers = nil)
      response = assistant_fetch_html_response(url, headers)

      doc = Nokogiri.HTML(response)
      uri = Addressable::URI.parse(url).normalize!

      ignore_canonical_tag = doc.at('meta[property="og:ignore_canonical"]')
      should_ignore_canonical =
        Onebox::Helpers::IGNORE_CANONICAL_DOMAINS.any? { |hostname| uri.hostname.match?(hostname) }

      if !(ignore_canonical_tag && ignore_canonical_tag["content"].to_s == "true") &&
           !should_ignore_canonical
        canonical_link = doc.at('//link[@rel="canonical"]/@href')
        canonical_uri = Addressable::URI.parse(canonical_link)&.normalize!
        if canonical_link && canonical_uri &&
             "#{canonical_uri.host}#{canonical_uri.path}" != "#{uri.host}#{uri.path}"
          uri =
            FinalDestination.new(
              canonical_uri,
              Oneboxer.get_final_destination_options(canonical_uri),
            ).resolve
          if uri.present?
            response = assistant_fetch_html_response(uri.to_s, headers)
            doc = Nokogiri.HTML(response) if response
          end
        end
      end

      doc
    end

    private

    def assistant_fetch_html_response(url, headers)
      response = assistant_fetch_direct_html_response(url, headers)
      return response unless assistant_use_proxy_for_response?(response)

      assistant_proxy_service.page_source(url)
    end

    def assistant_fetch_direct_html_response(url, headers)
      fetch_response(url, headers:, raise_error_when_response_too_large: false)
    rescue StandardError
      nil
    end

    def assistant_use_proxy_for_response?(response)
      SiteSetting.onebox_assistant_enabled &&
        (SiteSetting.onebox_assistant_always_use_proxy || response.nil?)
    end

    def assistant_proxy_service
      @assistant_proxy_service ||= ::DiscourseOneboxAssistant::ProxyService.new
    end
  end
end
