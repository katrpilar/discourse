import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import computed from "ember-addons/ember-computed-decorators";
import Category from "discourse/models/category";

let _components = {};

export default Ember.Component.extend({
  tagName: "",
  updating: null,
  editing: false,
  _updates: null,

  @computed("reviewable.type")
  customClass(type) {
    return type.dasherize();
  },

  @computed("reviewable.score")
  displayScore(score) {
    return score.toFixed(1);
  },

  // Find a component to render, if one exists. For example:
  // `ReviewableUser` will return `reviewable-user`
  @computed("reviewable.type")
  reviewableComponent(type) {
    if (_components[type] !== undefined) {
      return _components[type];
    }

    let dasherized = Ember.String.dasherize(type);
    let template = Ember.TEMPLATES[`components/${dasherized}`];
    if (template) {
      _components[type] = dasherized;
      return dasherized;
    }
    _components[type] = null;
  },

  _performConfirmed(actionId) {
    let reviewable = this.get("reviewable");
    let version = reviewable.get("version");
    this.set("updating", true);
    ajax(`/review/${reviewable.id}/perform/${actionId}?version=${version}`, {
      method: "PUT"
    })
      .then(result => {
        this.attrs.remove(
          result.reviewable_perform_result.remove_reviewable_ids
        );
      })
      .catch(popupAjaxError)
      .finally(() => {
        this.set("updating", false);
      });
  },

  actions: {
    edit() {
      this.set("editing", true);
      this._updates = { payload: {} };
    },

    cancelEdit() {
      this.set("editing", false);
    },

    saveEdit() {
      let updates = this._updates;

      // Remove empty objects
      Object.keys(updates).forEach(name => {
        let attr = updates[name];
        if (typeof attr === "object" && Object.keys(attr).length === 0) {
          delete updates[name];
        }
      });

      this.set("updating", true);
      return this.get("reviewable")
        .update(updates)
        .then(() => this.set("editing", false))
        .catch(popupAjaxError)
        .finally(() => {
          this.set("updating", false);
        });
    },

    categoryChanged(category) {
      if (!category) {
        category = Category.findUncategorized();
      }
      this._updates.category_id = category.id;
    },

    valueChanged(fieldId, event) {
      Ember.set(this._updates, fieldId, event.target.value);
    },

    perform(action) {
      if (this.get("updating")) {
        return;
      }

      let msg = action.get("confirm_message");
      if (msg) {
        bootbox.confirm(msg, answer => {
          if (answer) {
            return this._performConfirmed(action.id);
          }
        });
      } else {
        return this._performConfirmed(action.id);
      }
    }
  }
});
