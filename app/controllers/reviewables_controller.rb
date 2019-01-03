class ReviewablesController < ApplicationController
  requires_login

  before_action :version_required, only: [:update, :perform]

  def index
    reviewables = Reviewable.list_for(current_user, status: :pending).to_a

    # This is a bit awkward, but ActiveModel serializers doesn't seem to serialize STI
    hash = {}
    json = {
      reviewables: reviewables.map do |r|
        result = r.serializer.new(r, root: nil, hash: hash, scope: guardian).as_json
        hash[:reviewable_actions].uniq!
        result
      end,
      meta: {
        types: {
          created_by: 'user',
          target_created_by: 'user'
        }
      }
    }
    json.merge!(hash)

    render_json_dump(json, rest_serializer: true)
  end

  def update
    reviewable = Reviewable.viewable_by(current_user).where(id: params[:reviewable_id]).first
    raise Discourse::NotFound.new if reviewable.blank?

    editable = reviewable.editable_for(guardian)
    raise Discourse::InvalidAccess.new unless editable.present?

    # Validate parameters are all editable
    edit_params = params[:reviewable] || {}
    edit_params.each do |name, value|
      if value.is_a?(ActionController::Parameters)
        value.each do |pay_name, pay_value|
          raise Discourse::InvalidAccess.new unless editable.has?("#{name}.#{pay_name}")
        end
      else
        raise Discourse::InvalidAccess.new unless editable.has?(name)
      end
    end

    begin
      if reviewable.update_fields(edit_params, current_user, version: params[:version].to_i)
        result = edit_params.merge(version: reviewable.version)
        render json: result
      else
        render_json_error(reviewable.errors)
      end
    rescue Reviewable::UpdateConflict
      return render_json_error(I18n.t('reviewables.conflict'), status: 409)
    end
  end

  def perform
    reviewable = Reviewable.viewable_by(current_user).where(id: params[:reviewable_id]).first
    raise Discourse::NotFound.new if reviewable.blank?

    args = {
      version: params[:version].to_i
    }

    begin
      result = reviewable.perform(current_user, params[:action_id].to_sym, args)
    rescue Reviewable::InvalidAction => e
      # Consider InvalidAction an InvalidAccess
      raise Discourse::InvalidAccess.new(e.message)
    rescue Reviewable::UpdateConflict
      return render_json_error(I18n.t('reviewables.conflict'), status: 409)
    end

    if result.success?
      render_serialized(result, ReviewablePerformResultSerializer)
    else
      render_json_error(result.errors)
    end
  end

protected

  def version_required
    if params[:version].blank?
      render_json_error(I18n.t('reviewables.missing_version'), status: 422)
    end
  end

end
