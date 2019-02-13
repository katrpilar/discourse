class ReviewableScore < ActiveRecord::Base
  belongs_to :reviewable
  belongs_to :user

  def self.statuses
    @statuses ||= Enum.new(
      pending: 0,
      agreed: 1,
      disagreed: 2,
      ignored: 3
    )
  end

  def self.score_transitions
    {
      approved: statuses[:agreed],
      rejected: statuses[:disagreed],
      ignored: statuses[:ignored]
    }
  end

  # Generate `pending?`, `rejected?`, etc helper methods
  statuses.each do |name, id|
    define_method("#{name}?") { status == id }
    self.class.define_method(name) { where(status: id) }
  end

  def score_type
    Reviewable::Collection::Item.new(reviewable_score_type)
  end

  def self.user_flag_score(user)
    1.0 + (user.staff? ? 5.0 : user.trust_level.to_f) + user_accuracy_bonus(user)
  end

  def self.user_accuracy_bonus(user)
    user_stat = user&.user_stat
    return 0.0 if user_stat.blank?

    total = (user_stat.flags_agreed + user_stat.flags_disagreed + user_stat.flags_ignored).to_f
    return 0.0 if total <= 5

    (user_stat.flags_agreed / total) * 5.0
  end

end

# == Schema Information
#
# Table name: reviewable_scores
#
#  id                    :bigint(8)        not null, primary key
#  reviewable_id         :integer          not null
#  user_id               :integer          not null
#  reviewable_score_type :integer          not null
#  status                :integer          not null
#  score                 :float            default(0.0), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_reviewable_scores_on_reviewable_id  (reviewable_id)
#
