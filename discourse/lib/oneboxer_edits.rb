# frozen_string_literal: true

module ::DiscourseOneboxAssistant
  module OneboxerEdits
    # Synced from core `lib/oneboxer.rb#external_onebox`.
    # Plugin-specific behavior is isolated in the `assistant_*` helper methods below.
    def external_onebox(url, available_strategies = nil)
      Discourse
        .cache
        .fetch(onebox_cache_key(url), expires_in: 1.day) do
          original_uri = URI(url)
          available_strategies ||=
            Oneboxer.ordered_strategies(original_uri.hostname)
          strategy = available_strategies.shift

          max_redirects = 0 if SiteSetting.block_onebox_on_redirect
          fd =
            FinalDestination.new(
              url,
              get_final_destination_options(url, strategy).merge(
                stop_at_blocked_pages: true,
                max_redirects: max_redirects,
                initial_https_redirect_ignore_limit:
                  SiteSetting.block_onebox_on_redirect
              )
            )
          resolved_uri = fd.resolve

          return blank_onebox if fd.status == :blocked_page

          unless assistant_allow_unresolved_preview?(fd)
            if fd.status != :resolved
              args = { link: url }
              if fd.status == :invalid_address
                args[:error_message] = I18n.t(
                  "errors.onebox.invalid_address",
                  hostname: fd.hostname
                )
              elsif (fd.status_code || resolved_uri.nil?) &&
                    available_strategies.present?
                return external_onebox(url, available_strategies)
              elsif fd.status_code
                args[:error_message] = I18n.t(
                  "errors.onebox.error_response",
                  status_code: fd.status_code
                )
              end

              error_box = blank_onebox
              error_box[:preview] = preview_error_onebox(args)
              return error_box
            end

            return blank_onebox if resolved_uri.blank?
          end

          onebox_options = {
            max_width: 695,
            sanitize_config: Onebox::SanitizeConfig::DISCOURSE_ONEBOX,
            allowed_iframe_origins: allowed_iframe_origins,
            hostname: GlobalSetting.hostname,
            facebook_app_access_token: SiteSetting.facebook_app_access_token,
            disable_media_download_controls:
              SiteSetting.disable_onebox_media_download_controls,
            content_type: fd.content_type
          }

          onebox_options[:cookie] = fd.cookie if fd.cookie

          preview_result =
            Onebox.preview(
              assistant_preview_url(url, resolved_uri),
              onebox_options
            )
          result = {
            onebox: WordWatcher.censor(preview_result.to_s),
            preview: WordWatcher.censor(preview_result.placeholder_html.to_s)
          }

          if preview_result.errors.any?
            error_keys = preview_result.errors.keys
            skip_if_only_error = [:image]
            unless error_keys.length == 1 &&
                     skip_if_only_error.include?(error_keys.first)
              missing_attributes =
                error_keys.map(&:to_s).sort.join(I18n.t("word_connector.comma"))
              error_message =
                I18n.t(
                  "errors.onebox.missing_data",
                  missing_attributes: missing_attributes,
                  count: error_keys.size
                )
              args =
                preview_result.verified_data.merge(error_message: error_message)

              if result[:preview].blank?
                result[:preview] = preview_error_onebox(args)
              else
                doc = Nokogiri::HTML5.fragment(result[:preview])
                aside = doc.at("aside")

                if aside
                  error_fragment = preview_error_onebox_fragment(args)
                  aside.add_child(error_fragment)
                  result[:preview] = doc.to_html
                end
              end
            end
          end

          Oneboxer.cache_preferred_strategy(
            assistant_strategy_hostname(original_uri, resolved_uri),
            strategy
          )

          result
        end
    end

    private

    def assistant_allow_unresolved_preview?(final_destination)
      SiteSetting.onebox_assistant_enabled &&
        SiteSetting.onebox_assistant_always_use_proxy &&
        final_destination.status != :blocked_page
    end

    def assistant_preview_url(original_url, resolved_uri)
      assistant_force_proxy_preview? ? original_url : resolved_uri.to_s
    end

    def assistant_strategy_hostname(original_uri, resolved_uri)
      resolved_uri&.hostname || original_uri.hostname
    end

    def assistant_force_proxy_preview?
      SiteSetting.onebox_assistant_enabled &&
        SiteSetting.onebox_assistant_always_use_proxy
    end
  end
end
