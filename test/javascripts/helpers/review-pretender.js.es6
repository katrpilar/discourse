export default function(helpers) {
  const { response } = helpers;

  this.get("/review", () => {
    return response(200, {
      reviewables: [
        {
          id: 1234,
          type: "ReviewableUser",
          status: 0,
          version: 0,
          created_at: "2019-01-14T19:49:53.571Z",
          username: "newbie",
          email: "newbie@example.com",
          reviewable_action_ids: ["approve", "reject"]
        },
        {
          id: 4321,
          type: "ReviewableQueuedPost",
          status: 0,
          created_at: "2019-01-14T19:49:53.571Z",
          payload: {
            raw: "existing body",
            tags: ["hello", "world"]
          },
          version: 1,
          can_edit: true,
          editable_fields: [
            { id: "category_id", type: "category" },
            { id: "payload.title", type: "text" },
            { id: "payload.raw", type: "textarea" },
            { id: "payload.tags", type: "tags" }
          ],
          reviewable_action_ids: ["approve", "reject"]
        }
      ],
      reviewable_actions: [
        { id: "approve", title: "Approve", icon: "far-thumbs-up" },
        { id: "reject", title: "Reject", icon: "far-thumbs-down" }
      ],
      __rest_serializer: "1"
    });
  });

  this.put("/review/:id/perform/:actionId", request => {
    return response(200, {
      reviewable_perform_result: {
        success: true,
        remove_reviewable_ids: [parseInt(request.params.id)]
      }
    });
  });

  this.put("/review/:id", request => {
    let result = { payload: {} };
    Object.entries(JSON.parse(request.requestBody).reviewable).forEach(t => {
      Ember.set(result, t[0], t[1]);
    });
    return response(200, result);
  });
}
