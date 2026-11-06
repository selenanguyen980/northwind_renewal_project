-- QUESTION 2: Does low product usage impact renewals? Looking at 3 months prior to renewal date (not including the month of renewal)
-- Bringing in the tables current_opportunities (closed renewals) & fact_product_usage

with closed_renewals as (
  select *
  from `project-d4d9e3db-6339-426d-80c.sales_mart.current_opportunities`
  where revenue_type in ('Renewal', 'Expansion Renewal')
    and stage_name in ('Closed Won', 'Closed Lost')
)

, usage as (
  select r.opportunity_id
  , safe_divide(sum(u.active_users), sum(u.licensed_seats)) as utilization_90days
  from closed_renewals as r
  inner join `project-d4d9e3db-6339-426d-80c.sales_mart.fact_product_usage` as u
    on u.account_id = r.account_id
    and u.usage_month between date_sub(date_trunc(r.close_date, month), interval 3 month)
                      and date_sub(date_trunc(r.close_date,month), interval 1 month)
  group by r.opportunity_id
)

-- select *
-- from usage

select
  case when u.utilization_90days < 0.25 then  'Under 25%'
        when u.utilization_90days < 0.40 then '25-40%'
        when u.utilization_90days < 0.55 then '40-55%'
        when u.utilization_90days < 0.70 then '55-70%'
        else '70%+'
        end as utilization_bucket
  , count(*) as renewals
  ,countif(r.stage_name = 'Closed Won') as won_renewals
  ,safe_divide(countif(r.stage_name = 'Closed Won'), count(*)) as win_rate
from closed_renewals as r
inner join usage as u
  on u.opportunity_id = r.opportunity_id
group by utilization_bucket
order by utilization_bucket
