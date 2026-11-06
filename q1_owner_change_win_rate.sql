-- QUESTION 1: Do account ownership changes affect/result in lost renewals?
-- Bringing in the tables dim_accounts & current_opportunities

with owner_history as (
  select account_id
    , date(record_valid_from) as owner_change_date
    , account_owner_id as current_owner_id
    , lag(account_owner_id) over (partition by account_id order by record_valid_from) as prior_owner_id
  from `project-d4d9e3db-6339-426d-80c.sales_mart.dim_accounts`
  where is_deleted = false
)

, owner_changes as (
  select account_id
    , owner_change_date
    , current_owner_id
    , prior_owner_id
  from owner_history
  where prior_owner_id is not null
    and prior_owner_id != current_owner_id
)

, closed_renewals as (
  select *
  from `project-d4d9e3db-6339-426d-80c.sales_mart.current_opportunities`
  where revenue_type in ('Renewal', 'Expansion Renewal')
    and stage_name in ('Closed Won', 'Closed Lost')
)

, last_change_before_close as (
  select r.opportunity_id
    , r.stage_name
    , r.available_to_renew
    , r.close_date
    , max(c.owner_change_date) as last_owner_change_date
    , date_diff(r.close_date, max(c.owner_change_date), day) as days_since_owner_change
  from closed_renewals as r
  left join owner_changes as c
    on c.account_id = r.account_id
    and c.owner_change_date <= r.close_date
  group by r.opportunity_id
  , r.stage_name
  , r.available_to_renew
  , r.close_date
)

-- select *
-- from last_change_before_close

select
  case when days_since_owner_change <= 10 then '0-10 Days'
      when days_since_owner_change <= 20 then '11-20 Days'
      when days_since_owner_change <= 30 then '21-30 Days'
      when days_since_owner_change <= 50 then '31-50 Days'
      when days_since_owner_change is null then 'No Owner Change'
      else '50+ Days'
      end as gap_bucket
  , count(*) as renewals
  , countif(stage_name = 'Closed Won') as won_renewals
  , safe_divide(countif(stage_name = 'Closed Won'), count(*)) as win_rate
  , sum(if(stage_name = 'Closed Lost', available_to_renew, 0)) as lost_renewal_value
from last_change_before_close
group by gap_bucket
order by gap_bucket
