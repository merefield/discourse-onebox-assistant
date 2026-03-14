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

  describe ".assistant_use_proxy_for_response?" do
    it "returns false when the assistant is disabled" do
      SiteSetting.onebox_assistant_enabled = false

      expect(
        Onebox::Helpers.send(:assistant_use_proxy_for_response?, nil)
      ).to eq(false)
    end

    it "returns true when the direct response is missing" do
      expect(
        Onebox::Helpers.send(:assistant_use_proxy_for_response?, nil)
      ).to eq(true)
    end

    it "returns true when proxy mode is forced" do
      SiteSetting.onebox_assistant_always_use_proxy = true

      expect(
        Onebox::Helpers.send(
          :assistant_use_proxy_for_response?,
          "<html></html>"
        )
      ).to eq(true)
    end
  end

  describe ".assistant_fetch_html_response" do
    it "returns the direct response when proxy fallback is not needed" do
      Onebox::Helpers.stubs(:assistant_fetch_direct_html_response).returns(
        "<p>direct</p>"
      )
      DiscourseOneboxAssistant::ProxyService
        .any_instance
        .expects(:page_source)
        .never

      response =
        Onebox::Helpers.send(
          :assistant_fetch_html_response,
          "https://example.com",
          nil
        )

      expect(response).to eq("<p>direct</p>")
    end

    it "falls back to the proxy service when the direct response is missing" do
      Onebox::Helpers.stubs(:assistant_fetch_direct_html_response).returns(nil)

      DiscourseOneboxAssistant::ProxyService
        .any_instance
        .expects(:page_source)
        .with("https://example.com")
        .returns("<p>proxy</p>")

      response =
        Onebox::Helpers.send(
          :assistant_fetch_html_response,
          "https://example.com",
          nil
        )

      expect(response).to eq("<p>proxy</p>")
    end
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

      DiscourseOneboxAssistant::ProxyService
        .any_instance
        .expects(:page_source)
        .with(original_url)
        .once
        .returns(
          "<!DOCTYPE html><link rel='canonical' href='#{canonical_url}'><p>invalid</p>"
        )

      DiscourseOneboxAssistant::ProxyService
        .any_instance
        .expects(:page_source)
        .with(canonical_url)
        .once
        .returns("<!DOCTYPE html><p>success</p>")

      doc = Onebox::Helpers.fetch_html_doc(original_url)

      expect(doc.to_s).to include("success")
    end
  end
end

RSpec.describe DiscourseOneboxAssistant::ProxyService do
  before do
    SiteSetting.onebox_assistant_api_base_address = "https://proxy.example.com"
    SiteSetting.onebox_assistant_api_base_query = "?url="
    SiteSetting.onebox_assistant_api_options = "&render_js=false"
    SiteSetting.onebox_assistant_api_page_source_field = "source"
    SiteSetting.onebox_assistant_api_key = "secret"
  end

  describe "#page_source" do
    it "escapes the target URL before calling the proxy service" do
      target_url = "https://www.example.com/path?a=1&b=two words#fragment"

      HTTParty
        .expects(:get)
        .with(
          "https://proxy.example.com?url=https%3A%2F%2Fwww.example.com%2Fpath%3Fa%3D1%26b%3Dtwo+words%23fragment&render_js=false",
          headers: { "x-api-key" => "secret" }
        )
        .returns({ "source" => "<p>proxy</p>" })

      expect(described_class.new.page_source(target_url)).to eq("<p>proxy</p>")
    end
  end
end
