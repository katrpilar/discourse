import debounce from "discourse/lib/debounce";
import { i18n } from "discourse/lib/computed";
import AdminUser from "admin/models/admin-user";
import { observes } from "ember-addons/ember-computed-decorators";
import CanCheckEmails from "discourse/mixins/can-check-emails";

export default Ember.Controller.extend(CanCheckEmails, {
  query: null,
  queryParams: ["order", "ascending"],
  order: null,
  ascending: null,
  showEmails: false,
  refreshing: false,
  listFilter: null,
  selectAll: false,
  searchHint: i18n("search_hint"),

  title: function() {
    return I18n.t("admin.users.titles." + this.get("query"));
  }.property("query"),

  _filterUsers: debounce(function() {
    this._refreshUsers();
  }, 250).observes("listFilter"),

  @observes("order", "ascending")
  _refreshUsers: function() {
    this.set("refreshing", true);

    AdminUser.findAll(this.get("query"), {
      filter: this.get("listFilter"),
      show_emails: this.get("showEmails"),
      order: this.get("order"),
      ascending: this.get("ascending")
    })
      .then(result => {
        this.set("model", result);
      })
      .finally(() => {
        this.set("refreshing", false);
      });
  },

  actions: {
    showEmails: function() {
      this.set("showEmails", true);
      this._refreshUsers(true);
    }
  }
});
