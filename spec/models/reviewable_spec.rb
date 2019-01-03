require 'rails_helper'

RSpec.describe Reviewable, type: :model do

  context ".create" do
    let(:admin) { Fabricate(:admin) }
    let(:user) { Fabricate(:user) }

    let(:reviewable) { Fabricate.build(:reviewable, created_by: admin) }
    let(:queued_post) { Fabricate.build(:reviewable_queued_post) }

    it "can create a reviewable object" do
      expect(reviewable).to be_present
      expect(reviewable.pending?).to eq(true)
      expect(reviewable.created_by).to eq(admin)

      expect(reviewable.editable_for(Guardian.new(admin))).to be_blank

      expect(reviewable.payload).to be_present
      expect(reviewable.version).to eq(0)
      expect(reviewable.payload['name']).to eq('bandersnatch')
      expect(reviewable.payload['list']).to eq([1, 2, 3])
    end

    it "can add a target" do
      reviewable.target = user
      reviewable.save!

      expect(reviewable.target_type).to eq('User')
      expect(reviewable.target_id).to eq(user.id)
      expect(reviewable.target).to eq(user)
    end
  end

  context ".needs_review!" do
    let(:admin) { Fabricate(:admin) }
    let(:user) { Fabricate(:user) }

    it "will return a new reviewable the first them, and re-use the second time" do
      r0 = ReviewableUser.needs_review!(target: user, created_by: admin)
      expect(r0).to be_present

      r0.update_column(:status, Reviewable.statuses[:approved])

      r1 = ReviewableUser.needs_review!(target: user, created_by: admin)
      expect(r1.id).to eq(r0.id)
      expect(r1.pending?).to eq(true)
    end

    it "can create multiple objects with a NULL target" do
      r0 = ReviewableQueuedPost.needs_review!(created_by: admin, payload: { raw: 'hello world I am a post' })
      expect(r0).to be_present
      r0.update_column(:status, Reviewable.statuses[:approved])

      r1 = ReviewableQueuedPost.needs_review!(created_by: admin, payload: { raw: "another post's contents" })

      expect(ReviewableQueuedPost.count).to eq(2)
      expect(r1.id).not_to eq(r0.id)
      expect(r1.pending?).to eq(true)
      expect(r0.pending?).to eq(false)
    end
  end

  context ".list_for" do
    it "returns an empty list for nil user" do
      expect(Reviewable.list_for(nil)).to eq([])
    end

    context "with a pending item" do
      let(:post) { Fabricate(:post) }
      let(:user) { Fabricate(:user) }

      let(:reviewable) { Fabricate(:reviewable, target: post) }

      it "works with the reviewable by moderator flag" do
        reviewable.reviewable_by_moderator = true
        reviewable.save!

        expect(Reviewable.list_for(user, status: :pending)).to be_empty
        user.update_column(:moderator, true)
        expect(Reviewable.list_for(user, status: :pending)).to eq([reviewable])

        # Admins can review everything
        user.update_columns(moderator: false, admin: true)
        expect(Reviewable.list_for(user, status: :pending)).to eq([reviewable])
      end

      it "works with the reviewable by group" do
        group = Fabricate(:group)
        reviewable.reviewable_by_group_id = group.id
        reviewable.save!

        expect(Reviewable.list_for(user, status: :pending)).to be_empty
        gu = GroupUser.create!(group_id: group.id, user_id: user.id)
        expect(Reviewable.list_for(user, status: :pending)).to eq([reviewable])

        # Admins can review everything
        gu.destroy
        user.update_columns(moderator: false, admin: true)
        expect(Reviewable.list_for(user, status: :pending)).to eq([reviewable])
      end
    end
  end

  context "events" do
    let!(:moderator) { Fabricate(:moderator) }
    let(:reviewable) { Fabricate(:reviewable) }

    it "triggers events on create, transition_to" do
      event = DiscourseEvent.track(:reviewable_created) { reviewable.save! }
      expect(event).to be_present
      expect(event[:params].first).to eq(reviewable)

      event = DiscourseEvent.track(:reviewable_transitioned_to) do
        reviewable.transition_to(:approved, moderator)
      end
      expect(event).to be_present
      expect(event[:params][0]).to eq(:approved)
      expect(event[:params][1]).to eq(reviewable)
    end
  end

  context "message bus notifications" do
    let(:moderator) { Fabricate(:moderator) }

    it "triggers a notification on create" do
      Jobs.expects(:enqueue).with(:notify_reviewable, has_key(:reviewable_id))
      Fabricate(:reviewable_queued_post)
    end

    it "triggers a notification on pending -> approve" do
      reviewable = Fabricate(:reviewable_queued_post)
      Jobs.expects(:enqueue).with(:notify_reviewable, has_key(:reviewable_id))
      reviewable.perform(moderator, :approve)
    end

    it "triggers a notification on pending -> reject" do
      reviewable = Fabricate(:reviewable_queued_post)
      Jobs.expects(:enqueue).with(:notify_reviewable, has_key(:reviewable_id))
      reviewable.perform(moderator, :reject)
    end

    it "doesn't trigger a notification on approve -> reject" do
      reviewable = Fabricate(:reviewable_queued_post, status: Reviewable.statuses[:approved])
      Jobs.expects(:enqueue).with(:notify_reviewable, has_key(:reviewable_id)).never
      reviewable.perform(moderator, :reject)
    end

    it "doesn't trigger a notification on reject -> approve" do
      reviewable = Fabricate(:reviewable_queued_post, status: Reviewable.statuses[:approved])
      Jobs.expects(:enqueue).with(:notify_reviewable, has_key(:reviewable_id)).never
      reviewable.perform(moderator, :reject)
    end
  end

end
