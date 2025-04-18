Onebox::Helpers.module_eval do
  IGNORE_CANONICAL_DOMAINS = %w[www.instagram.com medium.com youtube.com]

  class ProxyService
    include HTTParty
    base_uri SiteSetting.onebox_assistant_api_base_address

    def get_page_data(url)
      base_query = SiteSetting.onebox_assistant_api_base_query + url
      query = base_query + SiteSetting.onebox_assistant_api_options
      key = SiteSetting.onebox_assistant_api_key
      self.class.get(query, headers: {'x-api-key' => key})
    end
  end

  def self.fetch_html_doc(url, headers = nil)
    response =
      (
        begin
          fetch_response(url, headers:, raise_error_when_response_too_large: false)
        rescue StandardError
          nil
        end
      )

    proxy_service = ProxyService.new

    if SiteSetting.onebox_assistant_enabled && (SiteSetting.onebox_assistant_always_use_proxy || response.nil?)
      proxy_service_response = proxy_service.get_page_data(url)
      response = proxy_service_response[SiteSetting.onebox_assistant_api_page_source_field]
      if response.nil?
        Rails.logger.warn "ONEBOX ASSIST: the API returned nothing!!"
      end
    else
      Rails.logger.info "ONEBOX ASSIST: result from direct crawl, API was not called"
    end

    doc = Nokogiri.HTML(response)
    uri = Addressable::URI.parse(url).normalize!

    ignore_canonical_tag = doc.at('meta[property="og:ignore_canonical"]')
    should_ignore_canonical =
      IGNORE_CANONICAL_DOMAINS.map { |hostname| uri.hostname.match?(hostname) }.any?

    if !(ignore_canonical_tag && ignore_canonical_tag["content"].to_s == "true") &&
        !should_ignore_canonical
      # prefer canonical link
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
          response =
            (
              begin
                fetch_response(uri.to_s, headers:, raise_error_when_response_too_large: false)
              rescue StandardError
                nil
              end
            )

          if SiteSetting.onebox_assistant_enabled && (SiteSetting.onebox_assistant_always_use_proxy || response.nil?)
            # retrieve_restful = CallProxy.new
            Rails.logger.info "ONEBOX ASSIST: the url being sought from API is " + url
            proxy_service_response = proxy_service.get_page_data(url)
            response = proxy_service_response[SiteSetting.onebox_assistant_api_page_source_field]
            if response.nil?
              Rails.logger.warn "ONEBOX ASSIST: the API returned nothing!!"
            end
          else
            Rails.logger.info "ONEBOX ASSIST: result from direct crawl, API was not called"
          end

          doc = Nokogiri.HTML(response) if response
        end
      end
    end

    doc
  end
end
