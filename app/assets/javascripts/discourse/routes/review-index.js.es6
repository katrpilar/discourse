export default Discourse.Route.extend({
  model() {
    return this.store.findAll("reviewable");
  },

  setupController(controller, model) {
    controller.set("reviewables", model);
  }
});
