require_dependency 'reviewable'

class ReviewableFlaggedPost < Reviewable

  def post
    target
  end

  def build_actions(actions, guardian, args)
    return unless pending?

    actions.add(:agree) do |action|
      action.icon = 'thumbs-up'
      action.title = 'reviewables.actions.agree.title'
    end
    actions.add(:disagree) do |action|
      action.icon = 'thumbs-down'
      action.title = 'reviewables.actions.disagree.title'
    end
    actions.add(:ignore) do |action|
      action.icon = 'thumbs-down'
      action.title = 'reviewables.actions.ignore.title'
    end
  end

  def perform_agree(performed_by, args)

    actions = PostAction.active
      .where(post_id: target_id)
      .where(post_action_type_id: PostActionType.notify_flag_types.values)

    trigger_spam = false
    actions.each do |action|
      action.agreed_at = Time.zone.now
      action.agreed_by_id = performed_by.id
      # so callback is called
      action.save
      action.add_moderator_post_if_needed(performed_by, :agreed, args[:delete_post])
      trigger_spam = true if action.post_action_type_id == PostActionType.types[:spam]
    end

    update_flag_stats(:agreed, actions.map(&:user_id))

    DiscourseEvent.trigger(:confirmed_spam_post, post) if trigger_spam

    if actions.first.present?
      DiscourseEvent.trigger(:flag_reviewed, post)
      DiscourseEvent.trigger(:flag_agreed, actions.first)

      if args[:hide_post]
        post.hide!(actions.first.post_action_type_id)
      end
    end

    PostAction.update_flagged_posts_count

    create_result(:success, :approved)
  end

  def perform_disagree(performed_by, args)

    # -1 is the automatic system cleary
    action_type_ids =
      if performed_by.id == Discourse::SYSTEM_USER_ID
        PostActionType.auto_action_flag_types.values
      else
        PostActionType.notify_flag_type_ids
      end

    actions = PostAction.active.where(post_id: target_id).where(post_action_type_id: action_type_ids)

    actions.each do |action|
      action.disagreed_at = Time.zone.now
      action.disagreed_by_id = performed_by.id
      # so callback is called
      action.save
      action.add_moderator_post_if_needed(performed_by, :disagreed)
    end

    update_flag_stats(:disagreed, actions.map(&:user_id))

    # reset all cached counters
    cached = {}
    action_type_ids.each do |atid|
      column = "#{PostActionType.types[atid]}_count"
      cached[column] = 0 if ActiveRecord::Base.connection.column_exists?(:posts, column)
    end

    Post.with_deleted.where(id: target_id).update_all(cached)

    if actions.first.present?
      DiscourseEvent.trigger(:flag_reviewed, post)
      DiscourseEvent.trigger(:flag_disagreed, actions.first)
    end

    PostAction.update_flagged_posts_count

    # Undo hide/silence if applicable
    if post&.hidden?
      post.unhide!
      UserSilencer.unsilence(post.user) if UserSilencer.was_silenced_for?(post)
    end

    create_result(:success, :rejected)
  end

  def perform_ignore(performed_by, args)

    actions = PostAction.active
      .where(post_id: target_id)
      .where(post_action_type_id: PostActionType.notify_flag_type_ids)

    actions.each do |action|
      action.deferred_at = Time.zone.now
      action.deferred_by_id = performed_by.id
      # so callback is called
      action.save
      action.add_moderator_post_if_needed(performed_by, :deferred, args[:delete_post])
    end

    update_flag_stats(:ignored, actions.map(&:user_id))

    if actions.first.present?
      DiscourseEvent.trigger(:flag_reviewed, post)
      DiscourseEvent.trigger(:flag_deferred, actions.first)
    end

    PostAction.update_flagged_posts_count
    create_result(:success, :ignored)
  end

  def update_flag_stats(status, user_ids)
    return unless [:agreed, :disagreed, :ignored].include?(status)

    result = DB.query(<<~SQL, user_ids: user_ids)
      UPDATE user_stats
      SET flags_#{status} = flags_#{status} + 1
      WHERE user_id IN (:user_ids)
      RETURNING user_id, flags_agreed + flags_disagreed + flags_ignored AS total
    SQL

    Jobs.enqueue(
      :truncate_user_flag_stats,
      user_ids: result.select { |r| r.total > Jobs::TruncateUserFlagStats.truncate_to }.map(&:user_id)
    )
  end

end

# == Schema Information
#
# Table name: reviewables
#
#  id                      :bigint(8)        not null, primary key
#  type                    :string           not null
#  status                  :integer          default(0), not null
#  created_by_id           :integer          not null
#  reviewable_by_moderator :boolean          default(FALSE), not null
#  reviewable_by_group_id  :integer
#  claimed_by_id           :integer
#  category_id             :integer
#  topic_id                :integer
#  score                   :float            default(0.0), not null
#  target_id               :integer
#  target_type             :string
#  target_created_by_id    :integer
#  payload                 :json
#  version                 :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_reviewables_on_status              (status)
#  index_reviewables_on_status_and_score    (status,score)
#  index_reviewables_on_status_and_type     (status,type)
#  index_reviewables_on_type_and_target_id  (type,target_id) UNIQUE
#
