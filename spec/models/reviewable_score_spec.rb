require 'rails_helper'

RSpec.describe ReviewableScore, type: :model do

  context "transitions" do
    let(:user) { Fabricate(:user, trust_level: 3) }
    let(:post) { Fabricate(:post) }
    let(:moderator) { Fabricate(:moderator) }

    it "a score is agreed when the reviewable is agreed" do
      reviewable = PostActionCreator.spam(user, post).reviewable
      score = reviewable.reviewable_scores.find_by(user: user)
      expect(score).to be_pending
      expect(score.score).to eq(4.0)

      reviewable.perform(moderator, :agree)
      expect(score.reload).to be_agreed
    end

    it "a score is disagreed when the reviewable is disagreed" do
      reviewable = PostActionCreator.spam(user, post).reviewable
      score = reviewable.reviewable_scores.find_by(user: user)
      expect(score).to be_pending
      expect(score.score).to eq(4.0)

      reviewable.perform(moderator, :disagree)
      expect(score.reload).to be_disagreed
    end
  end

  describe ".user_accuracy_bonus" do
    let(:user) { Fabricate(:user) }
    let(:user_stat) { user.user_stat }

    it "returns 0 for a user with no flags" do
      expect(ReviewableScore.user_accuracy_bonus(user)).to eq(0.0)
    end

    it "returns 0 until the user has made more than 5 flags" do
      user_stat.flags_agreed = 4
      user_stat.flags_disagreed = 1
      expect(ReviewableScore.user_accuracy_bonus(user)).to eq(0.0)
    end

    it "returns (agreed_flags / total) * 5.0" do
      user_stat.flags_agreed = 4
      user_stat.flags_disagreed = 2
      expect(ReviewableScore.user_accuracy_bonus(user).floor(2)).to eq(3.33)

      user_stat.flags_agreed = 121
      user_stat.flags_disagreed = 44
      user_stat.flags_ignored = 4
      expect(ReviewableScore.user_accuracy_bonus(user).floor(2)).to eq(3.57)
    end

  end

  describe ".user_flag_score" do
    context "a user with no flags" do
      it "returns 1.0 + trust_level" do
        expect(ReviewableScore.user_flag_score(Fabricate.build(:user, trust_level: 2))).to eq(3.0)
        expect(ReviewableScore.user_flag_score(Fabricate.build(:user, trust_level: 3))).to eq(4.0)
      end

      it "returns 6.0 for staff" do
        expect(ReviewableScore.user_flag_score(Fabricate.build(:moderator, trust_level: 2))).to eq(6.0)
        expect(ReviewableScore.user_flag_score(Fabricate.build(:admin, trust_level: 1))).to eq(6.0)
      end
    end

    context "a user with some flags" do
      let(:user) { Fabricate(:user) }
      let(:user_stat) { user.user_stat }

      it "returns 1.0 + trust_level + accuracy_bonus" do
        user.trust_level = 2
        user_stat.flags_agreed = 12
        user_stat.flags_disagreed = 2
        user_stat.flags_ignored = 2
        expect(ReviewableScore.user_flag_score(user)).to eq(6.75)
      end
    end
  end

end
