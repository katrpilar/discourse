class Jobs::TruncateUserFlagStats < Jobs::Base

  def self.truncate_to
    100
  end

  # To give users a chance to improve, we limit their flag stats to the last N flags
  def execute(args)
    raise Discourse::InvalidParameters.new(:user_ids) unless args[:user_ids].present?

    args[:user_ids].each do |u|
      user_stat = UserStat.find_by(user_id: u)
      next if user_stat.blank?

      total = user_stat.flags_agreed + user_stat.flags_disagreed + user_stat.flags_ignored
      next if total < self.class.truncate_to

      params = ReviewableScore.statuses.slice(:agreed, :disagreed, :ignored).
        merge(user_id: u, truncate_to: self.class.truncate_to)

      result = DB.query(<<~SQL, params)
        SELECT SUM(CASE WHEN rs.status = :agreed THEN 1 ELSE 0 END) AS agreed,
          SUM(CASE WHEN rs.status = :disagreed THEN 1 ELSE 0 END) AS disagreed,
          SUM(CASE WHEN rs.status = :ignored THEN 1 ELSE 0 END) AS ignored
        FROM (
          SELECT status
          FROM reviewable_scores
          WHERE user_id = :user_id
            AND status IN (:agreed, :disagreed, :ignored)
          ORDER BY created_at DESC
          LIMIT :truncate_to
        ) AS rs
      SQL

      user_stat.update_columns(
        flags_agreed: result[0].agreed || 0,
        flags_disagreed: result[0].disagreed || 0,
        flags_ignored: result[0].ignored || 0,
      )
    end

  end

end
