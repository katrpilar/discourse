export default Ember.Controller.extend({
  reviewables: null,

  actions: {
    remove(ids) {
      if (!ids) {
        return;
      }

      let newList = this.get("reviewables").reject(reviewable => {
        return ids.indexOf(reviewable.id) !== -1;
      });
      this.set("reviewables", newList);
    }
  }
});
