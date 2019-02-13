require 'rails_helper'

RSpec.describe ReviewableFlaggedPost, type: :model do

  describe "flag_stats" do
    let(:user) { Fabricate(:user) }
    let(:post) { Fabricate(:post) }
    let(:reviewable) { PostActionCreator.spam(user, post).reviewable }

    it "increases flags_agreed when agreed" do
      expect(user.user_stat.flags_agreed).to eq(0)
      reviewable.perform(Discourse.system_user, :agree)
      expect(user.user_stat.reload.flags_agreed).to eq(1)
    end

    it "increases flags_disagreed when disagreed" do
      expect(user.user_stat.flags_disagreed).to eq(0)
      reviewable.perform(Discourse.system_user, :disagree)
      expect(user.user_stat.reload.flags_disagreed).to eq(1)
    end

    it "increases flags_ignored when ignored" do
      expect(user.user_stat.flags_ignored).to eq(0)
      reviewable.perform(Discourse.system_user, :ignore)
      expect(user.user_stat.reload.flags_ignored).to eq(1)
    end
  end

end
