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

    def self.external_onebox(url, available_strategies = nil)
      Discourse.cache.fetch(onebox_cache_key(url), expires_in: 1.day) do
        uri = URI(url)
        available_strategies ||= Oneboxer.ordered_strategies(uri.hostname)
        strategy = available_strategies.shift

        fd = FinalDestination.new(url, get_final_destination_options(url, strategy))
        uri = fd.resolve

        unless SiteSetting.onebox_assistant_enabled && SiteSetting.onebox_assistant_always_use_proxy
          if fd.status != :resolved
            args = { link: url }
            if fd.status == :invalid_address
              args[:error_message] = I18n.t("errors.onebox.invalid_address", hostname: fd.hostname)
            elsif (fd.status_code || uri.nil?) && available_strategies.present?
              # Try a different oneboxing strategy, if we have any options left:
              return external_onebox(url, available_strategies)
            elsif fd.status_code
              args[:error_message] = I18n.t("errors.onebox.error_response", status_code: fd.status_code)
            end
    
            error_box = blank_onebox
            error_box[:preview] = preview_error_onebox(args)
            return error_box
          end

          return blank_onebox if uri.blank? || blocked_domains.any? { |hostname| uri.hostname.match?(hostname) }
        end

        onebox_options = {
          max_width: 695,
          sanitize_config: Onebox::DiscourseOneboxSanitizeConfig::Config::DISCOURSE_ONEBOX,
          allowed_iframe_origins: allowed_iframe_origins,
          hostname: GlobalSetting.hostname,
          facebook_app_access_token: SiteSetting.facebook_app_access_token,
          disable_media_download_controls: SiteSetting.disable_onebox_media_download_controls,
          body_cacher: self,
          content_type: fd.content_type
        }

        onebox_options[:cookie] = fd.cookie if fd.cookie

        user_agent_override = SiteSetting.cache_onebox_user_agent if Oneboxer.cache_response_body?(url) && SiteSetting.cache_onebox_user_agent.present?
        onebox_options[:user_agent] = user_agent_override if user_agent_override

        r = Onebox.preview(SiteSetting.onebox_assistant_enabled && SiteSetting.onebox_assistant_always_use_proxy ? url : uri.to_s, onebox_options)

        result = {
          onebox: WordWatcher.censor(r.to_s),
          preview: WordWatcher.censor(r&.placeholder_html.to_s)
        }

        # NOTE: Call r.errors after calling placeholder_html
        if r.errors.any?
          error_keys = r.errors.keys
          skip_if_only_error = [:image]
          unless error_keys.length == 1 && skip_if_only_error.include?(error_keys.first)
            missing_attributes = error_keys.map(&:to_s).sort.join(I18n.t("word_connector.comma"))
            error_message = I18n.t("errors.onebox.missing_data", missing_attributes: missing_attributes, count: error_keys.size)
            args = r.verified_data.merge(error_message: error_message)

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

        Oneboxer.cache_preferred_strategy(uri.hostname, strategy)

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

      Nokogiri::HTML(response)
    end
  end
end
