require_dependency 'reviewable/collection'

class Reviewable < ActiveRecord::Base
  class Actions < Reviewable::Collection

    # Add common actions here to make them easier for reviewables to re-use. If it's a
    # one off, add it manually.
    def self.common_actions
      {
        approve: Action.new(:approve, 'thumbs-up', 'reviewables.actions.approve.title'),
        reject: Action.new(:reject, 'thumbs-down', 'reviewables.actions.reject.title'),
      }
    end

    class Action < Item
      attr_accessor :icon, :title, :confirm_message

      def initialize(id, icon = nil, title = nil)
        super(id)
        @icon, @title = icon, title
      end
    end

    def add(id)
      action = Actions.common_actions[id] || Action.new(id)
      yield action if block_given?
      @content << action
    end
  end
end
