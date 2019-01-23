# name: discourse-onebox-assistant
# about: provides alternative path for grabbing one-boxes when initial crawl fails
# version: 1.0
# authors: merefield

gem 'mime-types-data', '3.2018.0812'
gem 'mime-types', '3.2.2'
gem 'httparty', '0.16.3'
require 'net/http'

enabled_site_setting :onebox_assistant_enabled

after_initialize do

  Oneboxer.module_eval do

    def self.external_onebox(url)
      Rails.cache.fetch(onebox_cache_key(url), expires_in: 1.day) do

      fd = FinalDestination.new(url, ignore_redirects: ignore_redirects, ignore_hostnames: blacklisted_domains, force_get_hosts: force_get_hosts, preserve_fragment_url_hosts: preserve_fragment_url_hosts)
      uri = fd.resolve
      return blank_onebox if blacklisted_domains.map { |hostname| uri.hostname.match?(hostname) }.any?

        options = {
          cache: {},
          max_width: 695,
          sanitize_config: Sanitize::Config::DISCOURSE_ONEBOX
        }

      options[:cookie] = fd.cookie if fd.cookie

        if Rails.env.development? && SiteSetting.port.to_i > 0
          Onebox.options = { allowed_ports: [80, 443, SiteSetting.port.to_i] }
        end

        r = Onebox.preview(url.to_s, options)

        { onebox: r.to_s, preview: r&.placeholder_html.to_s }
      end
    end
  end

  Onebox::Helpers.module_eval do
    class MyResty
      include HTTParty
      base_uri SiteSetting.onebox_assistant_api_base_address

      def preview(url)
        base_query=SiteSetting.onebox_assistant_api_base_query + url
        query = base_query + SiteSetting.onebox_assistant_api_options
        key = SiteSetting.onebox_assistant_api_key
        response = self.class.get(query, headers: {'x-api-key' => key})
        response
      end
    end

    def self.fetch_html_doc(url, headers = nil)

      response = (fetch_response(url, nil, nil, headers) rescue nil)

      if response.nil?
        retrieve_resty = MyResty.new
        initial_response = retrieve_resty.preview(url)
        response = initial_response['source']
      end

      doc = Nokogiri::HTML(response)

      ignore_canonical = doc.at('meta[property="og:ignore_canonical"]')
      unless ignore_canonical && ignore_canonical['content'].to_s == 'true'
        # prefer canonical link
        canonical_link = doc.at('//link[@rel="canonical"]/@href')
        if canonical_link && "#{URI(canonical_link).host}#{URI(canonical_link).path}" != "#{URI(url).host}#{URI(url).path}"
          response = (fetch_response(canonical_link, nil, nil, headers) rescue nil)
          doc = Nokogiri::HTML(response) if response
        end
      end

      doc
    end
  end
end
