Onebox::Helpers.module_eval do
  IGNORE_CANONICAL_DOMAINS ||= ['www.instagram.com', 'youtube.com']

  class RestfulCall
    include HTTParty
    base_uri SiteSetting.onebox_assistant_api_base_address

    def preview(url)
      base_query = SiteSetting.onebox_assistant_api_base_query + url
      query = base_query + SiteSetting.onebox_assistant_api_options
      key = SiteSetting.onebox_assistant_api_key
      self.class.get(query, headers: {'x-api-key' => key})
    end
  end

  def self.fetch_html_doc(url, headers = nil, body_cacher = nil)
    response = (fetch_response(url, headers: headers, body_cacher: body_cacher) rescue nil)

    if SiteSetting.onebox_assistant_always_use_proxy || (response.nil? && SiteSetting.onebox_assistant_enabled)
      retrieve_restful = RestfulCall.new
      Rails.logger.info "ONEBOX ASSIST: the url being sought from API is " + url
      initial_response = retrieve_restful.preview(url)
      response = initial_response[SiteSetting.onebox_assistant_api_page_source_field]
      if response.nil?
        Rails.logger.warn "ONEBOX ASSIST: the API returned nothing!!"
      end
    else
      Rails.logger.info "ONEBOX ASSIST: result from direct crawl, API was not called"
    end

    Nokogiri::HTML(response)
  end
end
