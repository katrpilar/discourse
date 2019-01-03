require 'rails_helper'

RSpec.describe ReviewableScore, type: :model do

  context "transitions" do
    let(:user) { Fabricate(:user) }
    let(:post) { Fabricate(:post) }
    let(:moderator) { Fabricate(:moderator) }

    it "a score is agreed when the reviewable is agreed" do
      reviewable = PostActionCreator.spam(user, post).reviewable
      score = reviewable.reviewable_scores.find_by(user: user)
      expect(score).to be_pending

      reviewable.perform(moderator, :agree)
      expect(score.reload).to be_agreed
    end

    it "a score is disagreed when the reviewable is disagreed" do
      reviewable = PostActionCreator.spam(user, post).reviewable
      score = reviewable.reviewable_scores.find_by(user: user)
      expect(score).to be_pending

      reviewable.perform(moderator, :disagree)
      expect(score.reload).to be_disagreed
    end

  end

end
