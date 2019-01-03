require 'rails_helper'

describe ReviewablesController do

  context "anonymous" do
    it "denies listing" do
      get "/review.json"
      expect(response.code).to eq("403")
    end

    it "denies performing" do
      put "/review/123/perform/approve.json"
      expect(response.code).to eq("403")
    end
  end

  context "when logged in" do
    let(:admin) { Fabricate(:admin) }

    before do
      sign_in(admin)
    end

    context "#index" do
      it "returns empty JSON when nothing to review" do
        get "/review.json"
        expect(response.code).to eq("200")
        json = ::JSON.parse(response.body)
        expect(json['reviewables']).to eq([])
      end

      it "returns JSON with reviewable content" do
        reviewable = Fabricate(:reviewable)

        get "/review.json"
        expect(response.code).to eq("200")
        json = ::JSON.parse(response.body)
        expect(json['reviewables']).to be_present

        json_review = json['reviewables'][0]
        expect(json_review['id']).to eq(reviewable.id)
        expect(json_review['created_by_id']).to eq(reviewable.created_by_id)
        expect(json_review['status']).to eq(Reviewable.statuses[:pending])
        expect(json_review['type']).to eq('ReviewableUser')
        expect(json_review['target_created_by_id']).to eq(reviewable.target_created_by_id)
        expect(json_review['score']).to eq(reviewable.score)
        expect(json_review['version']).to eq(reviewable.version)

        expect(json['users'].any? { |u| u['id'] == reviewable.created_by_id }).to eq(true)
        expect(json['users'].any? { |u| u['id'] == reviewable.target_created_by_id }).to eq(true)
      end

      it "will use the ReviewableUser serializer for its fields" do
        SiteSetting.must_approve_users = true
        user = Fabricate(:user)
        reviewable = ReviewableUser.find_by(target: user)

        get "/review.json"
        expect(response.code).to eq("200")
        json = ::JSON.parse(response.body)

        json_review = json['reviewables'][0]
        expect(json_review['id']).to eq(reviewable.id)
        expect(json_review['user_id']).to eq(user.id)
      end
    end

    context "#perform" do
      let(:reviewable) { Fabricate(:reviewable) }
      before do
        sign_in(Fabricate(:moderator))
      end

      it "returns 404 when the reviewable does not exist" do
        put "/review/12345/perform/approve.json?version=0"
        expect(response.code).to eq("404")
      end

      it "validates the presenece of an action" do
        put "/review/#{reviewable.id}/perform/nope.json?version=#{reviewable.version}"
        expect(response.code).to eq("403")
      end

      it "ensures the user can see the reviewable" do
        reviewable.update_column(:reviewable_by_moderator, false)
        put "/review/#{reviewable.id}/perform/approve.json?version=#{reviewable.version}"
        expect(response.code).to eq("404")
      end

      it "can properly return errors" do
        qp = Fabricate(:reviewable_queued_post_topic, topic_id: -100)
        put "/review/#{qp.id}/perform/approve.json?version=#{qp.version}"
        expect(response.code).to eq("422")
        result = ::JSON.parse(response.body)
        expect(result['errors']).to be_present
      end

      it "requires a version parameter" do
        put "/review/#{reviewable.id}/perform/approve.json"
        expect(response.code).to eq("422")
        result = ::JSON.parse(response.body)
        expect(result['errors']).to be_present
      end

      it "succeeds for a valid action" do
        put "/review/#{reviewable.id}/perform/approve.json?version=#{reviewable.version}"
        expect(response.code).to eq("200")
        json = ::JSON.parse(response.body)
        expect(json['reviewable_perform_result']['success']).to eq(true)
        expect(json['reviewable_perform_result']['version'] > 0).to eq(true)
        expect(json['reviewable_perform_result']['transition_to']).to eq('approved')
        expect(json['reviewable_perform_result']['transition_to_id']).to eq(Reviewable.statuses[:approved])
        expect(json['reviewable_perform_result']['remove_reviewable_ids']).to eq([reviewable.id])
      end

      describe "simultaneous perform" do
        it "fails when the version is wrong" do
          put "/review/#{reviewable.id}/perform/approve.json?version=#{reviewable.version + 1}"
          expect(response.code).to eq("409")
          json = ::JSON.parse(response.body)
          expect(json['errors']).to be_present
        end
      end

    end

    context "#update" do
      let(:reviewable) { Fabricate(:reviewable) }
      let(:reviewable_post) { Fabricate(:reviewable_queued_post) }
      let(:reviewable_topic) { Fabricate(:reviewable_queued_post_topic) }
      let(:moderator) { Fabricate(:moderator) }

      before do
        sign_in(moderator)
      end

      it "returns 404 when the reviewable does not exist" do
        put "/review/12345.json?version=0"
        expect(response.code).to eq("404")
      end

      it "returns access denied if there are no editable fields" do
        put(
          "/review/#{reviewable.id}.json?version=#{reviewable.version}",
          params: { reviewable: { field: 'value' } }
        )
        expect(response.code).to eq("403")
      end

      it "returns access denied if you try to update a field that doesn't exist" do
        put(
          "/review/#{reviewable_post.id}.json?version=#{reviewable_post.version}",
          params: { reviewable: { field: 'value' } }
        )
        expect(response.code).to eq("403")
      end

      it "requires a version parameter" do
        put "/review/#{reviewable_post.id}.json"
        expect(response.code).to eq("422")
      end

      it "fails if there is a version conflict" do
        put "/review/#{reviewable_post.id}.json?version=#{reviewable_post.version + 2}",
          params: {
            reviewable: {
              payload: {
                raw: 'new raw content'
              }
            }
          }

        expect(response.code).to eq("409")
      end

      it "allows you to update a queued post" do
        put "/review/#{reviewable_post.id}.json?version=#{reviewable_post.version}",
          params: {
            reviewable: {
              payload: {
                raw: 'new raw content'
              }
            }
          }

        expect(response.code).to eq("200")
        reviewable_post.reload
        expect(reviewable_post.payload['raw']).to eq('new raw content')

        history = ReviewableHistory.find_by(
          reviewable_id: reviewable_post.id,
          created_by_id: moderator.id,
          reviewable_history_type: ReviewableHistory.types[:edited]
        )
        expect(history).to be_present

        json = ::JSON.parse(response.body)
        expect(json['payload']['raw']).to eq('new raw content')
        expect(json['version'] > 0).to eq(true)
      end

      it "allows you to update a queued post (for new topic)" do
        new_category_id = Fabricate(:category).id

        put "/review/#{reviewable_topic.id}.json?version=#{reviewable_topic.version}",
          params: {
            reviewable: {
              payload: {
                raw: 'new topic op',
                title: 'new topic title',
                tags: ['t2', 't3', 't1']
              },
              category_id: new_category_id
            }
          }

        expect(response.code).to eq("200")
        reviewable_topic.reload
        expect(reviewable_topic.payload['raw']).to eq('new topic op')
        expect(reviewable_topic.payload['title']).to eq('new topic title')
        expect(reviewable_topic.payload['extra']).to eq('some extra data')
        expect(reviewable_topic.payload['tags']).to eq(['t2', 't3', 't1'])
        expect(reviewable_topic.category_id).to eq(new_category_id)

        json = ::JSON.parse(response.body)
        expect(json['payload']['raw']).to eq('new topic op')
        expect(json['payload']['title']).to eq('new topic title')
        expect(json['payload']['extra']).to be_blank
        expect(json['category_id']).to eq(new_category_id.to_s)
      end

    end

  end

end
