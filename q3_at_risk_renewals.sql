-- QUESTION 3: Which accounts are currently at risk of not renewing?
-- Bringing in current_opportunities (open renewals), fact_product_usage, dim_accounts (owner history), current_accounts, dim_users

-- Since I'm working with demo data, this is the equivalent of "current_date"
DECLARE as_of DATE DEFAULT DATE '2026-10-20';

with open_renewals as (
  select *
  from `project-d4d9e3db-6339-426d-80c.sales_mart.current_opportunities`
  where revenue_type in ('Renewal', 'Expansion Renewal')
    and stage_name not in ('Closed Won', 'Closed Lost')
)

, recent_usage as (
  select account_id
    , safe_divide(sum(active_users),sum(licensed_seats)) as utilization_90days
  from `project-d4d9e3db-6339-426d-80c.sales_mart.fact_product_usage`
  where usage_month between date_sub(date_trunc(as_of, month), interval 3 month)
                    and date_sub(date_trunc(as_of, month), interval 1 month)
  group by account_id
)

, owner_history as (
  select account_id
    , date(record_valid_from) as owner_change_date
    , account_owner_id as current_owner_id
    , lag(account_owner_id) over (partition by account_id order by record_valid_from) as prior_owner_id
  from `project-d4d9e3db-6339-426d-80c.sales_mart.dim_accounts`
  where is_deleted = false
)

, owner_changes as (
  select account_id
    , max(owner_change_date) as last_owner_change_date
  from owner_history
  where prior_owner_id is not null
    and prior_owner_id != current_owner_id
  group by account_id
)

select a.account_name
, u.user_full_name as owner
, o.close_date as expected_close_date
, o.available_to_renew
, round(r.utilization_90days, 2) as utilization_90days
, date_diff(as_of, c.last_owner_change_date, day) as days_since_owner_change
, ifnull(r.utilization_90days < 0.25, false) as low_usage
, ifnull(date_diff(as_of, c.last_owner_change_date, day) <= 30, false) as recent_owner_change
from open_renewals as o
inner join `project-d4d9e3db-6339-426d-80c.sales_mart.current_accounts` as a
  on a.account_id = o.account_id
left join `project-d4d9e3db-6339-426d-80c.sales_mart.dim_users` as u
  on u.user_id = o.owner_id
left join recent_usage as r
  on r.account_id = o.account_id
left join owner_changes as c
  on c.account_id = o.account_id
where ifnull(r.utilization_90days < 0.25, false) = true
   or ifnull(date_diff(as_of, c.last_owner_change_date, day) <= 30, false) = true
order by low_usage desc -- outputs true
, recent_owner_change desc -- flagging accounts at risk of low usage and ownership changes recently
, o.available_to_renew desc -- tie-breaker: highest amount of revenue first

-- o.expected_close_date desc -- prioritizing upcoming renewals
