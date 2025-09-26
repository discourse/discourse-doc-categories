# frozen_string_literal: true

RSpec.describe ::DocCategories::DocsLegacyController do
  before do
    GlobalSetting.stubs(:docs_path).returns("docs")

    SiteSetting.navigation_menu = "sidebar"
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_homepage = "/redirect-test"
  end

  describe "#redirect_url" do
    context "when docs legacy mode is enabled" do
      before { SiteSetting.doc_categories_docs_legacy_enabled = true }

      context "when redirecting to a topic" do
        fab!(:topic)

        it "should redirect /docs?topic=ID to /t/slug/id if the topics exists and the user can see it" do
          get "/docs?topic=#{topic.id}"

          expect(response).to redirect_to(topic.relative_url)
          expect(response.status).to eq(302)
        end

        it "should redirect /docs?topic=ID to /t/slug/id keeping extra query parameters" do
          get "/docs?topic=#{topic.id}&test=true"

          expect(response).to redirect_to("#{topic.relative_url}?test=true")
          expect(response.status).to eq(302)
        end

        it "should redirect /docs.json?topic=ID to /t/slug/id.json" do
          get "/docs.json?topic=#{topic.id}&test=true"

          expect(response).to redirect_to("#{topic.relative_url}.json?test=true")
          expect(response.status).to eq(302)
        end

        it "should redirect /docs?topic=ID to 404 if the topics exists and the user can't see it" do
          get "/docs?topic=#{topic.id}"

          expect(response).to redirect_to(topic.relative_url)
          expect(response.status).to eq(302)
        end

        it "should redirect /docs?topic=ID to 404 if the topic doesn't exist" do
          private_group = Fabricate(:group)
          private_category = Fabricate(:private_category, group: private_group)
          private_topic = Fabricate(:topic, category: private_category)

          get "/docs?topic=#{private_topic.id}"

          expect(response.status).to eq(404)
        end
      end

      context "when redirecting to a homepage" do
        it "should redirect /docs to the page specified in the docs if one is provided" do
          get "/docs"

          expect(response).to redirect_to("/redirect-test")
          expect(response.status).to eq(302)
        end

        it "should redirect /docs keeping query parameters" do
          get "/docs?test=true"

          expect(response).to redirect_to("/redirect-test?test=true")
          expect(response.status).to eq(302)
        end

        it "should redirect /docs to 404 if a page is not specified in the settings" do
          SiteSetting.doc_categories_homepage = ""

          get "/docs"

          expect(response.status).to eq(404)
        end

        it "should redirect /knowledge-explorer to the page specified in the docs if one is provided" do
          get "/knowledge-explorer"

          expect(response).to redirect_to("/redirect-test")
          expect(response.status).to eq(302)
        end
      end
    end

    context "when docs legacy mode is disabled" do
      before { SiteSetting.doc_categories_docs_legacy_enabled = false }

      context "when redirecting to a topic" do
        fab!(:topic)

        it "should redirect /docs?topic=ID to 404" do
          get "/docs?topic=#{topic.id}"

          expect(response.status).to eq(404)
        end

        it "should redirect /docs.json?topic=ID to /t/slug/id.json" do
          get "/docs.json?topic=#{topic.id}&test=true"

          expect(response.status).to eq(404)
        end
      end

      context "when redirecting to a homepage" do
        it "should redirect /docs to 404" do
          get "/docs"

          expect(response.status).to eq(404)
        end

        it "should redirect /knowledge-explorer to 404" do
          get "/knowledge-explorer"
          follow_redirect!

          expect(response.status).to eq(404)
        end
      end
    end
  end
end
