class MigrateReviewableFlaggedPosts < ActiveRecord::Migration[5.2]
  def up
    execute(<<~SQL)
      INSERT INTO reviewables (
        type,
        status,
        topic_id,
        category_id,
        payload,
        target_type,
        target_id,
        target_created_by_id,
        score,
        created_by_id,
        created_at,
        updated_at
      )
      SELECT 'ReviewableFlaggedPost',
        CASE
          WHEN MAX(pa.agreed_at) IS NOT NULL THEN 1
          WHEN MAX(pa.disagreed_at) IS NOT NULL THEN 2
          WHEN MAX(pa.deferred_at) IS NOT NULL THEN 3
          WHEN MAX(pa.deleted_at) IS NOT NULL THEN 4
          ELSE 0
        END,
        t.id,
        t.category_id,
        json_build_object(),
        'Post',
        pa.post_id,
        p.user_id,
        SUM(
          CASE
            WHEN pa.staff_took_action THEN 3.0
            ELSE 1.0
          END
        ),
        MAX(pa.user_id),
        MIN(pa.created_at),
        MAX(pa.updated_at)
      FROM post_actions AS pa
      INNER JOIN posts AS p ON pa.post_id = p.id
      INNER JOIN topics AS t ON t.id = p.topic_id
      INNER JOIN post_action_types AS pat ON pat.id = pa.post_action_type_id
      WHERE pat.is_flag
        AND pat.name_key <> 'notify_user'
        AND p.user_id > 0
        AND p.deleted_at IS NULL
        AND t.deleted_at IS NULL
      GROUP BY pa.post_id,
        t.id,
        t.category_id,
        p.user_id
    SQL

    execute(<<~SQL)
      INSERT INTO reviewable_scores (
        reviewable_id,
        user_id,
        reviewable_score_type,
        status,
        score,
        created_at,
        updated_at
      )
      SELECT r.id,
        pa.user_id,
        pa.post_action_type_id,
        CASE
          WHEN pa.agreed_at IS NOT NULL THEN 1
          WHEN pa.disagreed_at IS NOT NULL THEN 2
          WHEN pa.deferred_at IS NOT NULL THEN 3
          WHEN pa.deleted_at IS NOT NULL THEN 3
          ELSE 0
        END,
        CASE
          WHEN pa.staff_took_action THEN 3.0
          ELSE 1.0
        END,
        pa.created_at,
        pa.updated_at
      FROM post_actions AS pa
      INNER JOIN post_action_types AS pat ON pat.id = pa.post_action_type_id
      INNER JOIN reviewables AS r ON pa.post_id = r.target_id
      WHERE pat.is_flag
        AND r.type = 'ReviewableFlaggedPost'
    SQL
  end

  def down
    execute "DELETE FROM reviewables WHERE type = 'ReviewableFlaggedPost'"
    execute "DELETE FROM reviewable_scores"
  end
end
