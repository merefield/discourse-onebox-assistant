# name: discourse-onebox-assistant
# about: provides alternative path for grabbing one-boxes when initial crawl fails
# version: 2.0.3
# authors: merefield
# url: https://github.com/merefield/discourse-onebox-assistant

gem 'mime-types-data', '3.2019.1009'
gem 'mime-types', '3.3.1'
gem 'httparty', '0.17.3'

require 'net/http'

enabled_site_setting :onebox_assistant_enabled

after_initialize do
  Oneboxer.module_eval do

    def self.external_onebox(url)
      Discourse.cache.fetch(onebox_cache_key(url), expires_in: 1.day) do
        fd_options = {
          ignore_redirects: ignore_redirects,
          ignore_hostnames: blocked_domains,
          force_get_hosts: force_get_hosts,
          force_custom_user_agent_hosts: force_custom_user_agent_hosts,
          preserve_fragment_url_hosts: preserve_fragment_url_hosts
        }

        user_agent_override = SiteSetting.cache_onebox_user_agent if Oneboxer.cache_response_body?(url) && SiteSetting.cache_onebox_user_agent.present?
        fd_options[:default_user_agent] = user_agent_override if user_agent_override

        fd = FinalDestination.new(url, fd_options)
        uri = fd.resolve

        unless SiteSetting.onebox_assistant_always_use_proxy

          if fd.status != :resolved
            args = { link: url }
            if fd.status == :invalid_address
              args[:error_message] = I18n.t("errors.onebox.invalid_address", hostname: fd.hostname)
            elsif fd.status_code
              args[:error_message] = I18n.t("errors.onebox.error_response", status_code: fd.status_code)
            end
    
            error_box = blank_onebox
            error_box[:preview] = preview_error_onebox(args)
            return error_box
          end

          return blank_onebox if uri.blank? || blocked_domains.any? { |hostname| uri.hostname.match?(hostname) }
        else
          uri = url
        end

        onebox_options = {
          max_width: 695,
          sanitize_config: Onebox::DiscourseOneboxSanitizeConfig::Config::DISCOURSE_ONEBOX,
          allowed_iframe_origins: allowed_iframe_origins,
          hostname: GlobalSetting.hostname,
          facebook_app_access_token: SiteSetting.facebook_app_access_token,
          disable_media_download_controls: SiteSetting.disable_onebox_media_download_controls,
          body_cacher: self
        }

        onebox_options[:cookie] = fd.cookie if fd.cookie
        onebox_options[:user_agent] = user_agent_override if user_agent_override

        r = Onebox.preview(SiteSetting.onebox_assistant_enabled ? url : uri.to_s, onebox_options)

        result = { onebox: r.to_s, preview: r&.placeholder_html.to_s }

        # NOTE: Call r.errors after calling placeholder_html
        if r.errors.any?
          error_keys = r.errors.keys
          skip_if_only_error = [:image]
          unless error_keys.length == 1 && skip_if_only_error.include?(error_keys.first)
            missing_attributes = error_keys.map(&:to_s).sort.join(I18n.t("word_connector.comma"))
            error_message = I18n.t("errors.onebox.missing_data", missing_attributes: missing_attributes, count: error_keys.size)
            args = r.data.merge(error_message: error_message)
  
            if result[:preview].blank?
              result[:preview] = preview_error_onebox(args)
            else
              doc = Nokogiri::HTML5::fragment(result[:preview])
              aside = doc.at('aside')
  
              if aside
                # Add an error message to the preview that was returned
                error_fragment = preview_error_onebox_fragment(args)
                aside.add_child(error_fragment)
                result[:preview] = doc.to_html
              end
            end
          end
        end

        result
      end
    end
  end

  Onebox::Helpers.module_eval do

    IGNORE_CANONICAL_DOMAINS ||= ['www.instagram.com', 'youtube.com']

    class MyResty
      include HTTParty
      base_uri SiteSetting.onebox_assistant_api_base_address

      def preview(url)
        base_query=SiteSetting.onebox_assistant_api_base_query + url
        query = base_query + SiteSetting.onebox_assistant_api_options
        key = SiteSetting.onebox_assistant_api_key
        self.class.get(query, headers: {'x-api-key' => key})
      end
    end

    def self.fetch_html_doc(url, headers = nil, body_cacher = nil)
      response = (fetch_response(url, headers: headers, body_cacher: body_cacher) rescue nil)

      if SiteSetting.onebox_assistant_always_use_proxy || (response.nil? && SiteSetting.onebox_assistant_enabled)
        retrieve_resty = MyResty.new
        Rails.logger.info "ONEBOX ASSIST: the url being sought from API is " + url
        initial_response = retrieve_resty.preview(url)
        response = initial_response[SiteSetting.onebox_assistant_api_page_source_field]
        if response.nil?
          Rails.logger.warn "ONEBOX ASSIST: the API returned nothing!!"
        end
      else
        Rails.logger.info "ONEBOX ASSIST: result from direct crawl, API was not called"
      end

      doc = Nokogiri::HTML(response)

      if !SiteSetting.onebox_assistant_enabled
        uri = Addressable::URI.parse(url)

        ignore_canonical_tag = doc.at('meta[property="og:ignore_canonical"]')
        should_ignore_canonical = IGNORE_CANONICAL_DOMAINS.map { |hostname| uri.hostname.match?(hostname) }.any?

        unless (ignore_canonical_tag && ignore_canonical_tag['content'].to_s == 'true') || should_ignore_canonical
          # prefer canonical link
          canonical_uri = Addressable::URI.parse(canonical_link)
          if canonical_link && "#{canonical_uri.host}#{canonical_uri.path}" != "#{uri.host}#{uri.path}"
            response = (fetch_response(canonical_uri.to_s, headers: headers, body_cacher: body_cacher) rescue nil)
            doc = Nokogiri::HTML(response) if response
          end
        end
      end

      doc
    end
  end
end
