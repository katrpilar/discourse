class ReviewableActionSerializer < ApplicationSerializer
  attributes :id, :icon, :title, :confirm_message

  def title
    I18n.t(object.title)
  end

  def confirm_message
    I18n.t(object.confirm_message)
  end

  def include_confirm_message?
    object.confirm_message.present?
  end

end
