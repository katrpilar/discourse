require_dependency 'enum'
require_dependency 'reviewable/actions'
require_dependency 'reviewable/editable_fields'
require_dependency 'reviewable/perform_result'
require_dependency 'reviewable_serializer'

class Reviewable < ActiveRecord::Base
  class UpdateConflict < StandardError; end

  class InvalidAction < StandardError
    def initialize(action_id, klass)
      @action_id, @klass = action_id, klass
      super("Can't peform `#{action_id}` on #{klass.name}")
    end
  end

  validates_presence_of :type, :status, :created_by_id
  belongs_to :target, polymorphic: true
  belongs_to :created_by, class_name: 'User'
  belongs_to :target_created_by, class_name: 'User'
  belongs_to :reviewable_by_group, class_name: 'Group'

  # Optional, for filtering
  belongs_to :topic
  belongs_to :category

  has_many :reviewable_histories
  has_many :reviewable_scores

  after_create do
    DiscourseEvent.trigger(:reviewable_created, self)
    Jobs.enqueue(:notify_reviewable, reviewable_id: self.id) if pending?
    log_history(:created, created_by)
  end

  def self.statuses
    @statuses ||= Enum.new(
      pending: 0,
      approved: 1,
      rejected: 2,
      ignored: 3,
      deleted: 4
    )
  end

  # Generate `pending?`, `rejected?`, etc helper methods
  statuses.each do |name, id|
    define_method("#{name}?") { status == id }
    self.class.define_method(name) { where(status: id) }
  end

  # Create a new reviewable, or if the target has already been reviewed return it to the
  # pending state and re-use it.
  #
  # You probably want to call this to create your reviewable rather than `.create`.
  def self.needs_review!(target: nil, topic: nil, created_by:, payload: nil, reviewable_by_moderator: false)
    target_created_by_id = target.is_a?(Post) ? target.user_id : nil

    create!(
      target: target,
      target_created_by_id: target_created_by_id,
      topic: topic,
      created_by: created_by,
      reviewable_by_moderator: reviewable_by_moderator
    )
  rescue ActiveRecord::RecordNotUnique
    where(target: target).update_all(status: statuses[:pending])
    find_by(target: target).tap { |r| r.log_history(:transitioned, created_by) }
  end

  def add_score(user, reviewable_score_type)
    reviewable_scores.create!(
      user: user,
      status: ReviewableScore.statuses[:pending],
      reviewable_score_type: reviewable_score_type,
      score: 1.0
    )
  end

  def history
    reviewable_histories.order(:created_at)
  end

  def log_history(reviewable_history_type, performed_by, edited: nil)
    reviewable_histories.create!(
      reviewable_history_type: ReviewableHistory.types[reviewable_history_type],
      status: status,
      created_by: performed_by,
      edited: edited
    )
  end

  def actions_for(guardian, args = nil)
    args ||= {}
    Actions.new(self, guardian).tap { |a| build_actions(a, guardian, args) }
  end

  def editable_for(guardian, args = nil)
    args ||= {}
    EditableFields.new(self, guardian, args).tap { |a| build_editable_fields(a, guardian, args) }
  end

  # subclasses implement "build_actions" to list the actions they're capable of
  def build_actions(actions, guardian, args)
  end

  # subclasses implement "build_editable_fields" to list stuff that can be edited
  def build_editable_fields(actions, guardian, args)
  end

  def update_fields(params, performed_by, version: nil)
    return true if params.blank?

    (params[:payload] || {}).each { |k, v| self.payload[k] = v }
    self.category_id = params[:category_id] if params.has_key?(:category_id)

    result = false

    Reviewable.transaction do
      increment_version!(version)
      changes_json = changes.as_json
      changes_json.delete('version')

      result = save
      log_history(:edited, performed_by, edited: changes_json) if result
    end

    result
  end

  # Delegates to a `perform_#{action_id}` method, which returns a `PerformResult` with
  # the result of the operation and whether the status of the reviewable changed.
  def perform(performed_by, action_id, args = nil)
    args ||= {}

    # Ensure the user has access to the action
    actions = actions_for(Guardian.new(performed_by), args)
    raise InvalidAction.new(action_id, self.class) unless actions.has?(action_id)

    perform_method = "perform_#{action_id}".to_sym
    raise InvalidAction.new(action_id, self.class) unless respond_to?(perform_method)

    result = nil
    Reviewable.transaction do
      increment_version!(args[:version])
      result = send(perform_method, performed_by, args)

      if result.success? && result.transition_to
        transition_to(result.transition_to, performed_by)
      end
    end
    result
  end

  def transition_to(status_symbol, performed_by)
    was_pending = pending?

    self.status = Reviewable.statuses[status_symbol]
    save!
    log_history(:transitioned, performed_by)
    DiscourseEvent.trigger(:reviewable_transitioned_to, status_symbol, self)

    if score_status = ReviewableScore.score_transitions[status_symbol]
      reviewable_scores.pending.update_all(status: score_status)
    end

    Jobs.enqueue(:notify_reviewable, reviewable_id: self.id) if was_pending
  end

  def post_options
    Discourse.deprecate(
      "Reviewable#post_options is deprecated. Please use #payload instead.",
      output_in_test: true
    )
  end

  def self.bulk_perform_targets(performed_by, action, type, target_ids, args = nil)
    args ||= {}
    viewable_by(performed_by).where(type: type, target_id: target_ids).each do |r|
      r.perform(performed_by, action, args)
    end
  end

  def self.viewable_by(user)
    return none unless user.present?
    result = order('score desc, created_at desc').includes(
      :created_by,
      :topic,
      :target,
      :target_created_by
    ).includes(reviewable_scores: :user)
    return result if user.admin?

    result.where(
      '(reviewable_by_moderator AND :staff) OR (reviewable_by_group_id IN (:group_ids))',
      staff: user.staff?,
      group_ids: user.group_users.pluck(:group_id)
    )
  end

  def self.list_for(user, status: :pending, type: nil)
    return [] if user.blank?
    result = viewable_by(user).where(status: statuses[status])
    result = result.where(type: type) if type
    result
  end

  def serializer
    self.class.serializer_for(self)
  end

  def self.lookup_serializer_for(type)
    "#{type}Serializer".constantize
  rescue NameError
    ReviewableSerializer
  end

  def self.serializer_for(reviewable)
    type = reviewable.type
    @@serializers ||= {}
    @@serializers[type] ||= lookup_serializer_for(type)
  end

  def create_result(status, transition_to = nil)
    result = PerformResult.new(self, status)
    result.transition_to = transition_to
    yield result if block_given?
    result
  end

protected

  def increment_version!(version = nil)
    version_result = nil

    if version
      version_result = DB.query_single(
        "UPDATE reviewables SET version = version + 1 WHERE version = :version RETURNING version",
        version: version
      )
    else
      # We didn't supply a version to update safely, so just increase it
      version_result = DB.query_single("UPDATE reviewables SET version = version + 1 RETURNING version")
    end

    if version_result && version_result[0]
      self.version = version_result[0]
    else
      raise UpdateConflict.new
    end
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
