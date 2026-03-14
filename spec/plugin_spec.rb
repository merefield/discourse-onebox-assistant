# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oneboxer do
  before do
    Discourse.cache.clear
    SiteSetting.onebox_assistant_enabled = true
    SiteSetting.onebox_assistant_always_use_proxy = false
    SiteSetting.onebox_assistant_api_base_address = "https://proxy.example.com"
    SiteSetting.onebox_assistant_api_base_query = "?url="
    SiteSetting.onebox_assistant_api_options = "&render_js=false"
    SiteSetting.onebox_assistant_api_page_source_field = "source"
    SiteSetting.onebox_assistant_api_key = "secret"
  end

  describe ".external_onebox" do
    it "returns a blank onebox when FinalDestination reports a blocked page" do
      url = "https://blocked.example.com"

      FinalDestination.any_instance.stubs(:resolve).returns(URI(url))
      FinalDestination.any_instance.stubs(:status).returns(:blocked_page)

      Onebox.expects(:preview).never

      result = Oneboxer.external_onebox(url)

      expect(result[:onebox]).to eq("")
      expect(result[:preview]).to eq("")
    end
  end
end

RSpec.describe Onebox::Helpers do
  before do
    Discourse.cache.clear
    SiteSetting.onebox_assistant_enabled = true
    SiteSetting.onebox_assistant_always_use_proxy = false
    SiteSetting.onebox_assistant_api_base_address = "https://proxy.example.com"
    SiteSetting.onebox_assistant_api_base_query = "?url="
    SiteSetting.onebox_assistant_api_options = "&render_js=false"
    SiteSetting.onebox_assistant_api_page_source_field = "source"
    SiteSetting.onebox_assistant_api_key = "secret"
  end

  describe ".fetch_html_doc" do
    it "uses the canonical URL for the proxy follow-up request" do
      original_url = "https://www.example.com/post"
      canonical_url = "https://canonical.example.com/post"

      SiteSetting.onebox_assistant_always_use_proxy = true

      Onebox::Helpers.stubs(:fetch_response).returns(nil)
      FinalDestination
        .any_instance
        .stubs(:resolve)
        .returns(Addressable::URI.parse(canonical_url))

      Onebox::Helpers::ProxyService
        .any_instance
        .expects(:get_page_data)
        .with(original_url)
        .once
        .returns(
          {
            "source" =>
              "<!DOCTYPE html><link rel='canonical' href='#{canonical_url}'><p>invalid</p>"
          }
        )

      Onebox::Helpers::ProxyService
        .any_instance
        .expects(:get_page_data)
        .with(canonical_url)
        .once
        .returns({ "source" => "<!DOCTYPE html><p>success</p>" })

      doc = Onebox::Helpers.fetch_html_doc(original_url)

      expect(doc.to_s).to include("success")
    end
  end
end
